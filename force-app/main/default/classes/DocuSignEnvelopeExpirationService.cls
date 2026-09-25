public with sharing class DocuSignEnvelopeExpirationService {
  private static final Set<String> OPEN_STATUSES = new Set<String>{
    'sent',
    'delivered'
  };
  private static final Integer ENVELOPES_PER_JOB = 40;
  private static final Integer MAX_SELECTED_BIDS = 200;
  private static final Integer MAX_ERROR_LENGTH = 32000;

  @TestVisible
  static Boolean testBypassPermission = false;
  @TestVisible
  static Boolean performCallouts = !Test.isRunningTest();

  public class ExpirationUpdateException extends Exception {
  }

  public class SelectionSummary {
    @AuraEnabled
    public Integer bidCount;
    @AuraEnabled
    public Integer envelopeCount;
  }

  public class Result {
    @AuraEnabled
    public Id requestId;

    @AuraEnabled
    public Integer envelopeCount;

    @AuraEnabled
    public String message;
  }

  public class UpdateStatus {
    @AuraEnabled
    public Id requestId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer total;
    @AuraEnabled
    public Integer processed;
    @AuraEnabled
    public Integer succeeded;
    @AuraEnabled
    public Integer failed;
    @AuraEnabled
    public String errorSummary;
    @AuraEnabled
    public Boolean finished;
  }

  public class EnvelopeWork {
    public Id envelopeRecordId;
    public Id statusRecordId;
    public String docuSignId;
    public Datetime sentDate;
    public Boolean reminderEnabled = false;
    public Integer reminderDelay = 0;
    public Integer reminderFrequency = 0;

    public EnvelopeWork(
      Id envelopeRecordId,
      String docuSignId,
      Datetime sentDate
    ) {
      this.envelopeRecordId = envelopeRecordId;
      this.docuSignId = docuSignId;
      this.sentDate = sentDate;
    }
  }

  @AuraEnabled
  public static SelectionSummary getSelectionSummary(List<Id> contractBidIds) {
    assertPermission();
    Set<Id> authorizedBidIds = authorizeBidIds(contractBidIds);
    SelectionSummary summary = new SelectionSummary();
    summary.bidCount = authorizedBidIds.size();
    summary.envelopeCount = collectOpenEnvelopeWork(authorizedBidIds).size();
    return summary;
  }

  @AuraEnabled
  public static Result queueUpdate(
    List<Id> contractBidIds,
    Date expirationDate,
    Date warningDate
  ) {
    assertPermission();
    validateDates(expirationDate, warningDate);
    Set<Id> authorizedBidIds = authorizeBidIds(contractBidIds);
    List<EnvelopeWork> work = collectOpenEnvelopeWork(authorizedBidIds);
    if (work.isEmpty()) {
      throw new ExpirationUpdateException(
        'No Sent or Delivered DocuSign envelopes were found.'
      );
    }

    DocuSign_Expiration_Update__c tracking = new DocuSign_Expiration_Update__c(
      Status__c = 'Queued',
      Total__c = work.size(),
      Processed__c = 0,
      Succeeded__c = 0,
      Failed__c = 0,
      Expiration_Date__c = expirationDate,
      Warning_Date__c = warningDate
    );
    insert tracking;

    System.enqueueJob(
      new Job(tracking.Id, work, expirationDate, warningDate)
    );

    Result result = new Result();
    result.requestId = tracking.Id;
    result.envelopeCount = work.size();
    result.message = work.size() + ' envelope update(s) queued.';
    return result;
  }

  @AuraEnabled
  public static UpdateStatus getUpdateStatus(Id requestId) {
    assertPermission();
    if (requestId == null) {
      throw new ExpirationUpdateException('Update request Id is required.');
    }
    List<DocuSign_Expiration_Update__c> rows = [
      SELECT
        Status__c,
        Total__c,
        Processed__c,
        Succeeded__c,
        Failed__c,
        Error_Summary__c
      FROM DocuSign_Expiration_Update__c
      WHERE Id = :requestId
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new ExpirationUpdateException(
        'The update request could not be found.'
      );
    }
    DocuSign_Expiration_Update__c row = rows[0];
    UpdateStatus status = new UpdateStatus();
    status.requestId = row.Id;
    status.status = row.Status__c;
    status.total = integerValue(row.Total__c);
    status.processed = integerValue(row.Processed__c);
    status.succeeded = integerValue(row.Succeeded__c);
    status.failed = integerValue(row.Failed__c);
    status.errorSummary = row.Error_Summary__c;
    status.finished =
      row.Status__c == 'Completed' ||
      row.Status__c == 'Completed With Errors';
    return status;
  }

  public class Job implements Queueable, Database.AllowsCallouts {
    private Id trackingId;
    private List<EnvelopeWork> work;
    private Date expirationDate;
    private Date warningDate;

    public Job(
      Id trackingId,
      List<EnvelopeWork> work,
      Date expirationDate,
      Date warningDate
    ) {
      this.trackingId = trackingId;
      this.work = work == null ? new List<EnvelopeWork>() : work;
      this.expirationDate = expirationDate;
      this.warningDate = warningDate;
    }

    public void execute(QueueableContext context) {
      if (work.isEmpty()) {
        finishEmptyRequest();
        return;
      }

      Integer endIndex = Math.min(ENVELOPES_PER_JOB, work.size());
      List<EnvelopeWork> current = new List<EnvelopeWork>();
      for (Integer index = 0; index < endIndex; index++) {
        current.add(work[index]);
      }

      BatchOutcome outcome = processBatch(current, expirationDate, warningDate);
      Boolean hasRemaining = endIndex < work.size();
      updateTracking(outcome, !hasRemaining);

      if (hasRemaining) {
        List<EnvelopeWork> remaining = new List<EnvelopeWork>();
        for (Integer index = endIndex; index < work.size(); index++) {
          remaining.add(work[index]);
        }
        System.enqueueJob(
          new Job(trackingId, remaining, expirationDate, warningDate)
        );
      }
    }

    private void finishEmptyRequest() {
      if (trackingId == null) {
        return;
      }
      update new DocuSign_Expiration_Update__c(
        Id = trackingId,
        Status__c = 'Completed'
      );
    }

    private void updateTracking(BatchOutcome outcome, Boolean isFinal) {
      DocuSign_Expiration_Update__c tracking = [
        SELECT Processed__c, Succeeded__c, Failed__c, Error_Summary__c
        FROM DocuSign_Expiration_Update__c
        WHERE Id = :trackingId
        LIMIT 1
        FOR UPDATE
      ];
      tracking.Processed__c += outcome.processed;
      tracking.Succeeded__c += outcome.succeeded;
      tracking.Failed__c += outcome.failed;
      tracking.Error_Summary__c = appendErrors(
        tracking.Error_Summary__c,
        outcome.errors
      );
      if (isFinal) {
        tracking.Status__c = tracking.Failed__c > 0
          ? 'Completed With Errors'
          : 'Completed';
      } else {
        tracking.Status__c = 'Processing';
      }
      update tracking;
    }
  }

  public class BatchOutcome {
    public Integer processed = 0;
    public Integer succeeded = 0;
    public Integer failed = 0;
    public List<String> errors = new List<String>();
  }

  @TestVisible
  static BatchOutcome processBatch(
    List<EnvelopeWork> work,
    Date expirationDate,
    Date warningDate
  ) {
    BatchOutcome outcome = new BatchOutcome();
    if (work == null || work.isEmpty()) {
      return outcome;
    }

    DocuSignNotificationApiService.Connection connection;
    if (performCallouts) {
      try {
        connection = DocuSignNotificationApiService.resolveConnection();
      } catch (Exception ex) {
        for (EnvelopeWork item : work) {
          outcome.processed++;
          outcome.failed++;
          outcome.errors.add(errorFor(item, ex.getMessage()));
        }
        return outcome;
      }
    }

    List<dfsle__Envelope__c> envelopesToUpdate = new List<dfsle__Envelope__c>();
    List<dfsle__EnvelopeStatus__c> statusesToUpdate = new List<dfsle__EnvelopeStatus__c>();
    List<EnvelopeWork> successfulWork = new List<EnvelopeWork>();
    for (EnvelopeWork item : work) {
      outcome.processed++;
      try {
        Integer expireAfterDays = calculateExpireAfterDays(
          item.sentDate,
          expirationDate
        );
        Integer expireWarnDays = warningDate.daysBetween(expirationDate);
        validateRelativeDays(expireAfterDays, expireWarnDays);

        if (performCallouts) {
          DocuSignNotificationApiService.updateExpiration(
            connection.namedCredential,
            connection.accountId,
            item.docuSignId,
            expireAfterDays,
            expireWarnDays,
            item.reminderEnabled,
            item.reminderDelay,
            item.reminderFrequency
          );
        }

        if (item.envelopeRecordId != null) {
          envelopesToUpdate.add(
            new dfsle__Envelope__c(
              Id = item.envelopeRecordId,
              dfsle__Expires__c = true,
              dfsle__ExpireAfterDays__c = expireAfterDays,
              dfsle__ExpireWarnDays__c = expireWarnDays
            )
          );
        }
        if (item.statusRecordId != null && item.sentDate != null) {
          statusesToUpdate.add(
            new dfsle__EnvelopeStatus__c(
              Id = item.statusRecordId,
              dfsle__Expires__c = item.sentDate.addDays(expireAfterDays)
            )
          );
        }
        successfulWork.add(item);
      } catch (Exception ex) {
        outcome.failed++;
        outcome.errors.add(errorFor(item, ex.getMessage()));
      }
    }

    Map<Id, EnvelopeWork> workByEnvelopeId = new Map<Id, EnvelopeWork>();
    Map<Id, EnvelopeWork> workByStatusId = new Map<Id, EnvelopeWork>();
    for (EnvelopeWork item : successfulWork) {
      if (item.envelopeRecordId != null) {
        workByEnvelopeId.put(item.envelopeRecordId, item);
      }
      if (item.statusRecordId != null) {
        workByStatusId.put(item.statusRecordId, item);
      }
    }

    Set<String> localFailures = new Set<String>();
    if (!envelopesToUpdate.isEmpty()) {
      Database.SaveResult[] saveResults = Database.update(
        envelopesToUpdate,
        false
      );
      for (Integer index = 0; index < saveResults.size(); index++) {
        if (saveResults[index].isSuccess()) {
          continue;
        }
        EnvelopeWork item = workByEnvelopeId.get(envelopesToUpdate[index].Id);
        localFailures.add(item.docuSignId);
        outcome.errors.add(
          errorFor(
            item,
            'DocuSign updated, but Salesforce envelope synchronization failed: ' +
            firstDmlError(saveResults[index])
          )
        );
      }
    }
    if (!statusesToUpdate.isEmpty()) {
      Database.SaveResult[] saveResults = Database.update(
        statusesToUpdate,
        false
      );
      for (Integer index = 0; index < saveResults.size(); index++) {
        if (saveResults[index].isSuccess()) {
          continue;
        }
        EnvelopeWork item = workByStatusId.get(statusesToUpdate[index].Id);
        if (localFailures.add(item.docuSignId)) {
          outcome.errors.add(
            errorFor(
              item,
              'DocuSign updated, but Salesforce status expiration failed: ' +
              firstDmlError(saveResults[index])
            )
          );
        }
      }
    }

    for (EnvelopeWork item : successfulWork) {
      if (localFailures.contains(item.docuSignId)) {
        outcome.failed++;
      } else {
        outcome.succeeded++;
      }
    }
    return outcome;
  }

  @TestVisible
  static Integer calculateExpireAfterDays(
    Datetime sentDate,
    Date expirationDate
  ) {
    if (sentDate == null) {
      throw new ExpirationUpdateException(
        'Envelope sent date is missing; expiration cannot be calculated safely.'
      );
    }
    return sentDate.date().daysBetween(expirationDate);
  }

  private static void validateRelativeDays(
    Integer expireAfterDays,
    Integer expireWarnDays
  ) {
    if (expireAfterDays < 1 || expireAfterDays > 999) {
      throw new ExpirationUpdateException(
        'Calculated expiration is outside the supported 1-999 day range.'
      );
    }
    if (
      expireWarnDays < 0 ||
      expireWarnDays >= expireAfterDays ||
      expireWarnDays > 999
    ) {
      throw new ExpirationUpdateException(
        'Calculated expiration warning is outside the supported range.'
      );
    }
  }

  private static void validateDates(Date expirationDate, Date warningDate) {
    if (expirationDate == null || warningDate == null) {
      throw new ExpirationUpdateException(
        'Expiration date and expiration warning date are required.'
      );
    }
    if (expirationDate <= Date.today()) {
      throw new ExpirationUpdateException(
        'Expiration date must be in the future.'
      );
    }
    if (warningDate < Date.today()) {
      throw new ExpirationUpdateException(
        'Expiration warning date cannot be in the past.'
      );
    }
    if (warningDate >= expirationDate) {
      throw new ExpirationUpdateException(
        'Expiration warning date must be before expiration.'
      );
    }
    if (Date.today().daysBetween(expirationDate) > 999) {
      throw new ExpirationUpdateException(
        'Expiration date must be within 999 days.'
      );
    }
  }

  private static Set<Id> authorizeBidIds(List<Id> contractBidIds) {
    if (contractBidIds == null || contractBidIds.isEmpty()) {
      throw new ExpirationUpdateException('Select at least one Contract Bid.');
    }
    if (contractBidIds.size() > MAX_SELECTED_BIDS) {
      throw new ExpirationUpdateException(
        'A maximum of 200 Contract Bids can be processed at once.'
      );
    }

    Set<Id> requested = new Set<Id>();
    for (Id recordId : contractBidIds) {
      if (
        recordId == null ||
        recordId.getSObjectType() != Contract_Bid__c.SObjectType
      ) {
        throw new ExpirationUpdateException(
          'Only Contract Bid records can be processed.'
        );
      }
      requested.add(recordId);
    }

    Set<Id> authorized = new Map<Id, Contract_Bid__c>(
        [
          SELECT Id
          FROM Contract_Bid__c
          WHERE Id IN :requested
          WITH USER_MODE
        ]
      )
      .keySet();
    if (authorized.size() != requested.size()) {
      throw new ExpirationUpdateException(
        'One or more selected Contract Bids are unavailable or inaccessible.'
      );
    }
    return authorized;
  }

  @TestVisible
  static List<EnvelopeWork> collectOpenEnvelopeWork(Set<Id> contractBidIds) {
    Map<String, EnvelopeWork> byDocuSignId = new Map<String, EnvelopeWork>();
    if (contractBidIds == null || contractBidIds.isEmpty()) {
      return new List<EnvelopeWork>();
    }

    Set<String> sourceIds = new Set<String>();
    for (Id bidId : contractBidIds) {
      sourceIds.add((String) bidId);
    }

    for (dfsle__Envelope__c envelope : [
      SELECT
        Id,
        dfsle__DocuSignId__c,
        dfsle__Sent__c,
        Status__c,
        dfsle__Remind__c,
        dfsle__RemindAfterDays__c,
        dfsle__RemindFrequencyDays__c
      FROM dfsle__Envelope__c
      WHERE dfsle__SourceId__c IN :sourceIds AND dfsle__DocuSignId__c != NULL
    ]) {
      if (!isOpen(envelope.Status__c)) {
        continue;
      }
      String docuSignId = envelope.dfsle__DocuSignId__c.trim();
      EnvelopeWork item = new EnvelopeWork(
        envelope.Id,
        docuSignId,
        envelope.dfsle__Sent__c
      );
      applyReminderSettings(item, envelope);
      byDocuSignId.put(docuSignId, item);
    }
    removeAutoRespondedSigners(byDocuSignId);
    attachVisibleStatus(byDocuSignId);
    return byDocuSignId.values();
  }

  private static void removeAutoRespondedSigners(
    Map<String, EnvelopeWork> byDocuSignId
  ) {
    if (byDocuSignId.isEmpty()) {
      return;
    }
    Set<String> bouncedDocuSignIds = new Set<String>();
    for (dfsle__RecipientStatus__c recipient : [
      SELECT dfsle__EnvelopeStatus__r.dfsle__DocuSignId__c
      FROM dfsle__RecipientStatus__c
      WHERE
        dfsle__Status__c = 'AutoResponded'
        AND dfsle__Type__c = 'Signer'
        AND dfsle__EnvelopeStatus__r.dfsle__DocuSignId__c IN :byDocuSignId.keySet()
    ]) {
      String docuSignId = recipient.dfsle__EnvelopeStatus__r.dfsle__DocuSignId__c;
      if (String.isNotBlank(docuSignId)) {
        bouncedDocuSignIds.add(docuSignId.trim());
      }
    }
    for (String docuSignId : bouncedDocuSignIds) {
      byDocuSignId.remove(docuSignId);
    }
  }

  private static void attachVisibleStatus(
    Map<String, EnvelopeWork> byDocuSignId
  ) {
    if (byDocuSignId.isEmpty()) {
      return;
    }
    for (dfsle__EnvelopeStatus__c status : [
      SELECT Id, dfsle__DocuSignId__c
      FROM dfsle__EnvelopeStatus__c
      WHERE
        dfsle__DocuSignId__c IN :byDocuSignId.keySet()
        AND dfsle__Status__c IN ('Sent', 'Delivered')
    ]) {
      EnvelopeWork item = byDocuSignId.get(status.dfsle__DocuSignId__c.trim());
      if (item != null) {
        item.statusRecordId = status.Id;
      }
    }
  }

  private static void applyReminderSettings(
    EnvelopeWork item,
    dfsle__Envelope__c envelope
  ) {
    item.reminderEnabled = envelope.dfsle__Remind__c == true;
    item.reminderDelay = integerValue(envelope.dfsle__RemindAfterDays__c);
    item.reminderFrequency = integerValue(envelope.dfsle__RemindFrequencyDays__c);
  }

  private static void assertPermission() {
    if (
      !testBypassPermission &&
      !FeatureManagement.checkPermission('Update_DocuSign_Envelope_Expiration')
    ) {
      throw new ExpirationUpdateException(
        'Missing permission: Update DocuSign Envelope Expiration.'
      );
    }
  }

  private static Integer integerValue(Decimal value) {
    return value == null ? 0 : value.intValue();
  }

  private static Boolean isOpen(String status) {
    return String.isNotBlank(status) &&
      OPEN_STATUSES.contains(status.trim().toLowerCase());
  }

  private static String errorFor(EnvelopeWork item, String message) {
    String envelopeId = item == null || String.isBlank(item.docuSignId)
      ? 'Unknown envelope'
      : item.docuSignId;
    return envelopeId + ': ' + message;
  }

  private static String firstDmlError(Database.SaveResult saveResult) {
    if (
      saveResult == null ||
      saveResult.getErrors() == null ||
      saveResult.getErrors().isEmpty()
    ) {
      return 'Unknown DML error';
    }
    return saveResult.getErrors()[0].getMessage();
  }

  private static String appendErrors(String existing, List<String> additions) {
    String combined = String.isBlank(existing) ? '' : existing;
    if (additions != null && !additions.isEmpty()) {
      if (String.isNotBlank(combined)) {
        combined += '\n';
      }
      combined += String.join(additions, '\n');
    }
    if (combined.length() > MAX_ERROR_LENGTH) {
      combined = combined.substring(0, MAX_ERROR_LENGTH);
    }
    return combined;
  }
}
