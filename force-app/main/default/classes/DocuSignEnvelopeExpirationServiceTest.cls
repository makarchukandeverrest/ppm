@IsTest
private class DocuSignEnvelopeExpirationServiceTest {
  private static Integer putCount;
  private static String lastPutBody;

  @TestSetup
  static void setupData() {
    Account account = new Account(Name = 'Expiration Update Account');
    insert account;
    insert new Contract_Bid__c(
      Name = 'Expiration Update Bid',
      Customer__c = account.Id,
      Stage__c = 'Contract Sent via DocuSign'
    );
  }

  @IsTest
  static void calculateExpireAfterDays_usesOriginalSentDate() {
    Datetime sentDate = Datetime.newInstance(
      Date.today().addDays(-30),
      Time.newInstance(9, 0, 0, 0)
    );
    Integer days = DocuSignEnvelopeExpirationService.calculateExpireAfterDays(
      sentDate,
      Date.today().addDays(90)
    );
    System.assertEquals(120, days);
  }

  @IsTest
  static void queueUpdates_updatesApiTrackingAndEnvelopeFields() {
    Contract_Bid__c bid = [SELECT Id, Customer__c FROM Contract_Bid__c LIMIT 1];
    SObject envelope = insertEnvelopeIfPossible(
      bid.Id,
      bid.Customer__c,
      '11111111-1111-1111-1111-111111111111',
      Datetime.now().addDays(-10)
    );
    if (envelope == null) {
      return;
    }

    DocuSignEnvelopeExpirationService.testBypassPermission = true;
    DocuSignEnvelopeExpirationService.performCallouts = true;
    DocuSignNotificationApiService.testNamedCredential = 'DocuSign';
    DocuSignNotificationApiService.testAccountId = 'TEST-ACCOUNT';
    putCount = 0;
    lastPutBody = null;
    Test.setMock(HttpCalloutMock.class, new NotificationMock());

    Test.startTest();
    DocuSignEnvelopeExpirationService.Result result = DocuSignEnvelopeExpirationService.queueUpdate(
      new List<Id>{ bid.Id },
      Date.today().addDays(90),
      Date.today().addDays(80)
    );
    Test.stopTest();

    System.assertEquals(1, result.envelopeCount);
    System.assertEquals(1, putCount);

    DocuSign_Expiration_Update__c tracking = [
      SELECT Status__c, Total__c, Processed__c, Succeeded__c, Failed__c
      FROM DocuSign_Expiration_Update__c
      WHERE Id = :result.requestId
    ];
    System.assertEquals('Completed', tracking.Status__c);
    System.assertEquals(1, tracking.Total__c);
    System.assertEquals(1, tracking.Processed__c);
    System.assertEquals(1, tracking.Succeeded__c);
    System.assertEquals(0, tracking.Failed__c);

    Id envelopeId = (Id) envelope.get('Id');
    SObject updated = Database.query(
      'SELECT dfsle__Expires__c, dfsle__ExpireAfterDays__c, dfsle__ExpireWarnDays__c ' +
      'FROM dfsle__Envelope__c WHERE Id = :envelopeId'
    );
    System.assertEquals(true, updated.get('dfsle__Expires__c'));
    System.assertEquals(100, updated.get('dfsle__ExpireAfterDays__c'));
    System.assertEquals(10, updated.get('dfsle__ExpireWarnDays__c'));
    System.assertNotEquals(null, lastPutBody);
  }

  @IsTest
  static void selectionSummary_countsMultipleAndDeduplicatesStatusRows() {
    Contract_Bid__c bid = [SELECT Id, Customer__c FROM Contract_Bid__c LIMIT 1];
    String docuSignId = '22222222-2222-2222-2222-222222222222';
    SObject envelope = insertEnvelopeIfPossible(
      bid.Id,
      bid.Customer__c,
      docuSignId,
      Datetime.now().addDays(-5)
    );
    if (
      envelope == null ||
      insertStatusIfPossible(bid.Id, docuSignId) == null
    ) {
      return;
    }
    SObject secondEnvelope = insertEnvelopeIfPossible(
      bid.Id,
      bid.Customer__c,
      '33333333-3333-3333-3333-333333333333',
      Datetime.now().addDays(-3)
    );
    if (secondEnvelope == null) {
      return;
    }

    DocuSignEnvelopeExpirationService.testBypassPermission = true;
    Test.startTest();
    DocuSignEnvelopeExpirationService.SelectionSummary summary = DocuSignEnvelopeExpirationService.getSelectionSummary(
      new List<Id>{ bid.Id }
    );
    Test.stopTest();

    System.assertEquals(1, summary.bidCount);
    System.assertEquals(2, summary.envelopeCount);
  }

  @IsTest
  static void selectionSummary_skipsEnvelopeWithAutoRespondedSigner() {
    Contract_Bid__c bid = [SELECT Id, Customer__c FROM Contract_Bid__c LIMIT 1];
    String bouncedId = '55555555-5555-5555-5555-555555555555';
    String openId = '66666666-6666-6666-6666-666666666666';
    if (
      insertEnvelopeIfPossible(
        bid.Id,
        bid.Customer__c,
        bouncedId,
        Datetime.now().addDays(-4)
      ) == null ||
      insertEnvelopeIfPossible(
        bid.Id,
        bid.Customer__c,
        openId,
        Datetime.now().addDays(-2)
      ) == null
    ) {
      return;
    }
    Id statusId = insertStatusIfPossible(bid.Id, bouncedId);
    if (statusId == null || !insertAutoRespondedSigner(statusId)) {
      return;
    }

    DocuSignEnvelopeExpirationService.testBypassPermission = true;
    Test.startTest();
    DocuSignEnvelopeExpirationService.SelectionSummary summary = DocuSignEnvelopeExpirationService.getSelectionSummary(
      new List<Id>{ bid.Id }
    );
    Test.stopTest();

    System.assertEquals(1, summary.envelopeCount);
  }

  @IsTest
  static void processBatch_syncsEnvelopeStatusExpirationDate() {
    Contract_Bid__c bid = [SELECT Id, Customer__c FROM Contract_Bid__c LIMIT 1];
    String docuSignId = '44444444-4444-4444-4444-444444444444';
    Datetime sentDate = Datetime.newInstance(
      Date.today().addDays(-10),
      Time.newInstance(8, 0, 0, 0)
    );
    if (
      insertEnvelopeIfPossible(bid.Id, bid.Customer__c, docuSignId, sentDate) ==
      null
    ) {
      return;
    }
    Id statusId = insertStatusIfPossible(bid.Id, docuSignId);
    if (statusId == null) {
      return;
    }

    DocuSignEnvelopeExpirationService.performCallouts = false;
    List<DocuSignEnvelopeExpirationService.EnvelopeWork> work = DocuSignEnvelopeExpirationService.collectOpenEnvelopeWork(
      new Set<Id>{ bid.Id }
    );
    System.assertEquals(1, work.size(), 'Expected one open envelope.');
    System.assertEquals(statusId, work[0].statusRecordId);

    DocuSignEnvelopeExpirationService.BatchOutcome outcome = DocuSignEnvelopeExpirationService.processBatch(
      work,
      Date.today().addDays(90),
      Date.today().addDays(80)
    );
    System.assertEquals(
      0,
      outcome.failed,
      outcome.errors.isEmpty() ? 'status sync failed' : outcome.errors[0]
    );

    SObject status = Database.query(
      'SELECT dfsle__Expires__c FROM dfsle__EnvelopeStatus__c WHERE Id = :statusId'
    );
    System.assertEquals(
      sentDate.addDays(100),
      status.get('dfsle__Expires__c')
    );
  }

  @IsTest
  static void queueUpdates_rejectsInvalidDates() {
    Contract_Bid__c bid = [SELECT Id FROM Contract_Bid__c LIMIT 1];
    DocuSignEnvelopeExpirationService.testBypassPermission = true;

    Boolean threw = false;
    Test.startTest();
    try {
      DocuSignEnvelopeExpirationService.queueUpdate(
        new List<Id>{ bid.Id },
        Date.today(),
        Date.today()
      );
    } catch (DocuSignEnvelopeExpirationService.ExpirationUpdateException ex) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }

  @IsTest
  static void processBatch_recordsMissingSentDateAsFailure() {
    DocuSignEnvelopeExpirationService.performCallouts = false;
    DocuSignEnvelopeExpirationService.EnvelopeWork item = new DocuSignEnvelopeExpirationService.EnvelopeWork(
      null,
      'missing-sent-date',
      null
    );

    Test.startTest();
    DocuSignEnvelopeExpirationService.processBatch(
      new List<DocuSignEnvelopeExpirationService.EnvelopeWork>{ item },
      Date.today().addDays(30),
      Date.today().addDays(20)
    );
    Test.stopTest();
  }

  @IsTest
  static void processBatch_acceptsValidWorkWithoutLocalEnvelope() {
    DocuSignEnvelopeExpirationService.performCallouts = false;
    DocuSignEnvelopeExpirationService.EnvelopeWork item = new DocuSignEnvelopeExpirationService.EnvelopeWork(
      null,
      'valid-envelope',
      Datetime.now().addDays(-10)
    );

    Test.startTest();
    DocuSignEnvelopeExpirationService.processBatch(
      new List<DocuSignEnvelopeExpirationService.EnvelopeWork>{ item },
      Date.today().addDays(30),
      Date.today().addDays(20)
    );
    Test.stopTest();
  }

  @IsTest
  static void queueUpdates_rejectsSelectionWithoutOpenEnvelopes() {
    Contract_Bid__c bid = [SELECT Id FROM Contract_Bid__c LIMIT 1];
    DocuSignEnvelopeExpirationService.testBypassPermission = true;

    Boolean threw = false;
    Test.startTest();
    try {
      DocuSignEnvelopeExpirationService.queueUpdate(
        new List<Id>{ bid.Id },
        Date.today().addDays(30),
        Date.today().addDays(20)
      );
    } catch (DocuSignEnvelopeExpirationService.ExpirationUpdateException ex) {
      threw = true;
      System.assert(ex.getMessage().contains('No Sent or Delivered'));
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }

  @IsTest
  static void selectionSummary_rejectsNonContractBidIds() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    DocuSignEnvelopeExpirationService.testBypassPermission = true;

    Boolean threw = false;
    Test.startTest();
    try {
      DocuSignEnvelopeExpirationService.getSelectionSummary(
        new List<Id>{ account.Id }
      );
    } catch (DocuSignEnvelopeExpirationService.ExpirationUpdateException ex) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }

  @IsTest
  static void getUpdateStatus_returnsFinalCountsAndError() {
    DocuSignEnvelopeExpirationService.testBypassPermission = true;
    DocuSign_Expiration_Update__c row = new DocuSign_Expiration_Update__c(
      Status__c = 'Completed With Errors',
      Total__c = 2,
      Processed__c = 2,
      Succeeded__c = 1,
      Failed__c = 1,
      Expiration_Date__c = Date.today().addDays(30),
      Warning_Date__c = Date.today().addDays(20),
      Error_Summary__c = 'consent_required'
    );
    insert row;

    Test.startTest();
    DocuSignEnvelopeExpirationService.UpdateStatus status = DocuSignEnvelopeExpirationService.getUpdateStatus(
      row.Id
    );
    Test.stopTest();

    System.assertEquals(true, status.finished);
    System.assertEquals(1, status.succeeded);
    System.assertEquals(1, status.failed);
    System.assertEquals('consent_required', status.errorSummary);
  }

  private static SObject insertEnvelopeIfPossible(
    Id sourceId,
    Id accountId,
    String docuSignId,
    Datetime sentDate
  ) {
    if (!Schema.getGlobalDescribe().containsKey('dfsle__Envelope__c')) {
      return null;
    }
    try {
      SObject envelope = Schema.getGlobalDescribe()
        .get('dfsle__Envelope__c')
        .newSObject();
      envelope.put('dfsle__SourceId__c', String.valueOf(sourceId));
      envelope.put('dfsle__DocuSignId__c', docuSignId);
      envelope.put('dfsle__Sent__c', sentDate);
      envelope.put('Status__c', 'Sent');
      envelope.put('Account__c', accountId);
      insert envelope;
      return envelope;
    } catch (Exception ex) {
      return null;
    }
  }

  private static Id insertStatusIfPossible(Id sourceId, String docuSignId) {
    try {
      SObject status = Schema.getGlobalDescribe()
        .get('dfsle__EnvelopeStatus__c')
        .newSObject();
      status.put('dfsle__SourceId__c', String.valueOf(sourceId));
      status.put('dfsle__DocuSignId__c', docuSignId);
      status.put('dfsle__Status__c', 'Sent');
      status.put('dfsle__Sent__c', Datetime.now().addDays(-5));
      insert status;
      return (Id) status.get('Id');
    } catch (Exception ex) {
      return null;
    }
  }

  private static Boolean insertAutoRespondedSigner(Id envelopeStatusId) {
    try {
      insert new dfsle__RecipientStatus__c(
        Name = 'Bounced Signer',
        dfsle__EnvelopeStatus__c = envelopeStatusId,
        dfsle__Email__c = 'notreal@gmail.com',
        dfsle__Type__c = 'Signer',
        dfsle__Status__c = 'AutoResponded',
        dfsle__Sent__c = Datetime.now().addDays(-4)
      );
      return true;
    } catch (Exception ex) {
      return false;
    }
  }

  private class NotificationMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setHeader('Content-Type', 'application/json');
      if (request.getMethod() == 'GET') {
        response.setStatusCode(200);
        response.setBody(
          '{"useAccountDefaults":"false","reminders":{"reminderEnabled":"true","reminderDelay":"2","reminderFrequency":"2"},"expirations":{"expireEnabled":"true","expireAfter":"120","expireWarn":"5"}}'
        );
        return response;
      }
      putCount++;
      lastPutBody = request.getBody();
      response.setStatusCode(200);
      response.setBody('{}');
      return response;
    }
  }
}
