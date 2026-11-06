public with sharing class ContractBidSendCleanupService {
  private static final String STATUS_COMPLETED = 'Completed';
  private static final String STAGE_CONTRACT_SENT = 'Contract Sent via DocuSign';
  private static final String STAGE_CLOSED_WON = 'Closed - WON';
  private static final String STAGE_CLOSED_LOST = 'Closed - LOST';
  private static final String CONTRACT_STATUS_ACTIVE = 'Active';

  private static final String SUBJECT_REQUEST_NEW_VERSION = 'Request New Version';
  private static final String SUBJECT_OPENED_UNSIGNED_PREFIX = 'Call about opened unsigned contract';
  private static final String SUBJECT_CALL_PROPERTY_PREFIX = 'Call Property Owner about Contract for ';
  private static final String SUBJECT_ONSITE_VISIT_PREFIX = 'On-site visit to ';
  private static final String SUBJECT_CONTRACT_NOT_SIGNED = 'Contract not signed';
  private static final String SUBJECT_FOLLOW_UP_NOT_DELIVERED_PREFIX = 'Follow up: Contract not delivered';
  private static final String SUBJECT_VERIFY_CONTACT_INFO = 'Verify contact info';

  private static final Set<String> AUTOMATIC_LABELS = new Set<String>{
    'Contract Created',
    'info verified',
    'New record created'
  };

  private static Set<Id> processedSendBidIds = new Set<Id>();
  private static Set<Id> processedCloseBidIds = new Set<Id>();

  public static void onEnvelopeSent(Set<Id> bidIds) {
    Set<Id> pendingBidIds = takeUnprocessed(bidIds, processedSendBidIds);
    if (pendingBidIds.isEmpty()) {
      return;
    }

    completeOpenTasks(pendingBidIds, false);
    refreshBidsAfterSuccessfulSend(pendingBidIds);
  }

  public static void onBidsClosed(Set<Id> bidIds) {
    Set<Id> pendingBidIds = takeUnprocessed(bidIds, processedCloseBidIds);
    if (pendingBidIds.isEmpty()) {
      return;
    }

    completeOpenTasks(pendingBidIds, true);
    clearAutomaticLabelsAndFlags(pendingBidIds);
  }

  /** @deprecated Use onEnvelopeSent */
  public static void completeOpenFollowUpTasks(Set<Id> bidIds) {
    onEnvelopeSent(bidIds);
  }

  private static Set<Id> takeUnprocessed(Set<Id> bidIds, Set<Id> processed) {
    Set<Id> pending = new Set<Id>();
    if (bidIds == null || bidIds.isEmpty()) {
      return pending;
    }
    for (Id bidId : bidIds) {
      if (bidId == null || processed.contains(bidId)) {
        continue;
      }
      processed.add(bidId);
      pending.add(bidId);
    }
    return pending;
  }

  private static void completeOpenTasks(Set<Id> bidIds, Boolean allAutomatic) {
    List<Task> openTasks = [
      SELECT Id, Subject
      FROM Task
      WHERE WhatId IN :bidIds AND IsClosed = FALSE
    ];

    List<Task> toComplete = new List<Task>();
    for (Task taskRecord : openTasks) {
      Boolean shouldComplete = allAutomatic
        ? isAutomaticTask(taskRecord.Subject)
        : isSendCleanupTask(taskRecord.Subject);
      if (!shouldComplete) {
        continue;
      }
      toComplete.add(new Task(Id = taskRecord.Id, Status = STATUS_COMPLETED));
    }

    if (!toComplete.isEmpty()) {
      update toComplete;
    }
  }

  private static void refreshBidsAfterSuccessfulSend(Set<Id> bidIds) {
    List<Contract_Bid__c> bids = [
      SELECT
        Id,
        Stage__c,
        Expired_No_Response__c,
        Viewed__c,
        Contract_Status__c,
        Sent_Contract_Date__c,
        Next_Follow_up_Date__c
      FROM Contract_Bid__c
      WHERE Id IN :bidIds
    ];

    List<Contract_Bid__c> toUpdate = new List<Contract_Bid__c>();
    Datetime sentAt = System.now();
    for (Contract_Bid__c bid : bids) {
      Boolean changed = false;

      if (bid.Expired_No_Response__c == true) {
        bid.Expired_No_Response__c = false;
        changed = true;
      }
      if (bid.Viewed__c == true) {
        bid.Viewed__c = false;
        changed = true;
      }
      if (bid.Contract_Status__c != CONTRACT_STATUS_ACTIVE) {
        bid.Contract_Status__c = CONTRACT_STATUS_ACTIVE;
        changed = true;
      }
      if (bid.Next_Follow_up_Date__c != null) {
        bid.Next_Follow_up_Date__c = null;
        changed = true;
      }
      if (bid.Sent_Contract_Date__c != sentAt) {
        bid.Sent_Contract_Date__c = sentAt;
        changed = true;
      }
      if (
        bid.Stage__c != STAGE_CLOSED_WON &&
        bid.Stage__c != STAGE_CLOSED_LOST &&
        bid.Stage__c != STAGE_CONTRACT_SENT
      ) {
        bid.Stage__c = STAGE_CONTRACT_SENT;
        changed = true;
      }

      if (changed) {
        toUpdate.add(bid);
      }
    }

    if (!toUpdate.isEmpty()) {
      update toUpdate;
    }
  }

  private static void clearAutomaticLabelsAndFlags(Set<Id> bidIds) {
    List<Contract_Bid__c> bids = [
      SELECT Id, Label__c, Expired_No_Response__c, Viewed__c
      FROM Contract_Bid__c
      WHERE Id IN :bidIds
    ];

    List<Contract_Bid__c> toUpdate = new List<Contract_Bid__c>();
    for (Contract_Bid__c bid : bids) {
      Boolean changed = false;

      String cleanedLabels = removeAutomaticLabels(bid.Label__c);
      if (cleanedLabels != bid.Label__c) {
        bid.Label__c = cleanedLabels;
        changed = true;
      }
      if (bid.Expired_No_Response__c == true) {
        bid.Expired_No_Response__c = false;
        changed = true;
      }
      if (bid.Viewed__c == true) {
        bid.Viewed__c = false;
        changed = true;
      }

      if (changed) {
        toUpdate.add(bid);
      }
    }

    if (!toUpdate.isEmpty()) {
      update toUpdate;
    }
  }

  @TestVisible
  static String removeAutomaticLabels(String labels) {
    if (String.isBlank(labels)) {
      return labels;
    }
    List<String> kept = new List<String>();
    for (String raw : labels.split(';')) {
      String value = raw == null ? null : raw.trim();
      if (String.isBlank(value) || AUTOMATIC_LABELS.contains(value)) {
        continue;
      }
      kept.add(value);
    }
    return kept.isEmpty() ? null : String.join(kept, ';');
  }

  @TestVisible
  static Boolean isSendCleanupTask(String subject) {
    if (String.isBlank(subject)) {
      return false;
    }
    String value = subject.trim();
    if (value == SUBJECT_REQUEST_NEW_VERSION) {
      return true;
    }
    if (value.startsWith(SUBJECT_OPENED_UNSIGNED_PREFIX)) {
      return true;
    }
    if (value.startsWith(SUBJECT_CALL_PROPERTY_PREFIX)) {
      return true;
    }
    if (
      value.startsWith(SUBJECT_ONSITE_VISIT_PREFIX) &&
      value.contains(SUBJECT_CONTRACT_NOT_SIGNED)
    ) {
      return true;
    }
    if (value.startsWith(SUBJECT_FOLLOW_UP_NOT_DELIVERED_PREFIX)) {
      return true;
    }
    return false;
  }

  @TestVisible
  static Boolean isAutomaticTask(String subject) {
    if (isSendCleanupTask(subject)) {
      return true;
    }
    if (String.isBlank(subject)) {
      return false;
    }
    return subject.trim() == SUBJECT_VERIFY_CONTACT_INFO;
  }

  /** @deprecated Use isSendCleanupTask */
  @TestVisible
  static Boolean isFollowUpTask(String subject) {
    return isSendCleanupTask(subject);
  }
}
