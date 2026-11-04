@IsTest
private class DocuSignNotificationServiceTest {
  private static final String CREATOR_PICKLIST = 'Marijana to Complete';

  @TestSetup
  static void setupTestData() {
    Account acc = new Account(Name = 'Test Account');
    insert acc;

    // Must be both active on Stage__c and listed in StageReferenceSettings.Active_Stages
    Contract_Bid__c bid = new Contract_Bid__c(
      Name = 'Test Contract Bid',
      Customer__c = acc.Id,
      Stage__c = 'Contract Sent via DocuSign',
      Contract_Creator_Picklist__c = CREATOR_PICKLIST
    );
    insert bid;
  }

  @IsTest
  static void handleEnvelopeStatusChange_CreatesTaskForActiveBid() {
    Id creatorUserId = ContractCreatorUserResolver.resolveUserId(
      CREATOR_PICKLIST
    );
    System.assertNotEquals(
      null,
      creatorUserId,
      'Mapped Contract Creator user must exist for ' + CREATOR_PICKLIST
    );

    Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

    ContentVersion cv = new ContentVersion(
      Title = 'Signed Contract.pdf',
      PathOnClient = 'Signed Contract.pdf',
      VersionData = Blob.valueOf('Test content'),
      IsMajorVersion = true,
      DocuSign_Envelope_Status__c = 'Completed'
    );
    insert cv;

    cv = [
      SELECT Id, ContentDocumentId, Title, DocuSign_Envelope_Status__c
      FROM ContentVersion
      WHERE Id = :cv.Id
      LIMIT 1
    ];

    ContentDocumentLink cdl = new ContentDocumentLink(
      ContentDocumentId = cv.ContentDocumentId,
      LinkedEntityId = acc.Id,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
    insert cdl;

    Test.startTest();
    DocuSignNotificationService.handleEnvelopeStatusChange(
      new List<ContentVersion>{ cv }
    );
    Test.stopTest();

    List<Task> tasks = [
      SELECT Id, OwnerId, WhatId, Subject, Status, Priority, ActivityDate
      FROM Task
      WHERE OwnerId = :creatorUserId
    ];

    System.assertEquals(
      1,
      tasks.size(),
      'One task should be created for the active Contract Bid'
    );
    Task createdTask = tasks[0];
    System.assertEquals('Completed', createdTask.Status);
    System.assertEquals('Normal', createdTask.Priority);
    System.assertEquals(Date.today(), createdTask.ActivityDate);
    System.assert(
      createdTask.Subject.contains('Completed'),
      'Subject should contain DocuSign status'
    );
  }

  @IsTest
  static void handleEnvelopeStatusChange_NoAccountLink_NoTaskCreated() {
    ContentVersion cv = new ContentVersion(
      Title = 'Orphan Document.pdf',
      PathOnClient = 'Orphan Document.pdf',
      VersionData = Blob.valueOf('Test content'),
      IsMajorVersion = true,
      DocuSign_Envelope_Status__c = 'Completed'
    );
    insert cv;

    cv = [
      SELECT Id, ContentDocumentId, Title, DocuSign_Envelope_Status__c
      FROM ContentVersion
      WHERE Id = :cv.Id
      LIMIT 1
    ];

    Test.startTest();
    DocuSignNotificationService.handleEnvelopeStatusChange(
      new List<ContentVersion>{ cv }
    );
    Test.stopTest();

    List<Task> tasks = [SELECT Id FROM Task];
    System.assertEquals(
      0,
      tasks.size(),
      'No task should be created when ContentVersion is not linked to an Account'
    );
  }

  @IsTest
  static void handleEnvelopeStatusChange_NoActiveBid_NoTaskCreated() {
    Account acc = new Account(Name = 'Account Without Active Bid');
    insert acc;

    ContentVersion cv = new ContentVersion(
      Title = 'No Active Bid.pdf',
      PathOnClient = 'No Active Bid.pdf',
      VersionData = Blob.valueOf('Test content'),
      IsMajorVersion = true,
      DocuSign_Envelope_Status__c = 'Completed'
    );
    insert cv;

    cv = [
      SELECT Id, ContentDocumentId, Title, DocuSign_Envelope_Status__c
      FROM ContentVersion
      WHERE Id = :cv.Id
      LIMIT 1
    ];

    ContentDocumentLink cdl = new ContentDocumentLink(
      ContentDocumentId = cv.ContentDocumentId,
      LinkedEntityId = acc.Id,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
    insert cdl;

    Test.startTest();
    DocuSignNotificationService.handleEnvelopeStatusChange(
      new List<ContentVersion>{ cv }
    );
    Test.stopTest();

    List<Task> tasks = [SELECT Id FROM Task];
    System.assertEquals(
      0,
      tasks.size(),
      'No task should be created when Account has no active Contract Bid'
    );
  }

  @IsTest
  static void handleEnvelopeStatusChange_InactiveStage_NoTaskCreated() {
    Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

    Contract_Bid__c inactiveBid = new Contract_Bid__c(
      Name = 'Inactive Bid',
      Customer__c = acc.Id,
      Stage__c = 'Closed - LOST',
      Contract_Creator_Picklist__c = CREATOR_PICKLIST
    );
    insert inactiveBid;

    ContentVersion cv = new ContentVersion(
      Title = 'Inactive Bid Document.pdf',
      PathOnClient = 'Inactive Bid Document.pdf',
      VersionData = Blob.valueOf('Test content'),
      IsMajorVersion = true,
      DocuSign_Envelope_Status__c = 'Completed'
    );
    insert cv;

    cv = [
      SELECT Id, ContentDocumentId, Title, DocuSign_Envelope_Status__c
      FROM ContentVersion
      WHERE Id = :cv.Id
      LIMIT 1
    ];

    ContentDocumentLink cdl = new ContentDocumentLink(
      ContentDocumentId = cv.ContentDocumentId,
      LinkedEntityId = acc.Id,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
    insert cdl;

    Test.startTest();
    DocuSignNotificationService.handleEnvelopeStatusChange(
      new List<ContentVersion>{ cv }
    );
    Test.stopTest();

    List<Task> tasks = [
      SELECT Id
      FROM Task
      WHERE WhatId = :inactiveBid.Id
    ];
    System.assertEquals(
      0,
      tasks.size(),
      'No task should be created for a Contract Bid with inactive stage'
    );
  }

  @IsTest
  static void handleEnvelopeStatusChange_MultipleVersions_OnlyMatchingProcessed() {
    Id creatorUserId = ContractCreatorUserResolver.resolveUserId(
      CREATOR_PICKLIST
    );
    System.assertNotEquals(
      null,
      creatorUserId,
      'Mapped Contract Creator user must exist for ' + CREATOR_PICKLIST
    );

    Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

    Account otherAcc = new Account(Name = 'Other Account');
    insert otherAcc;

    ContentVersion matchingCv = new ContentVersion(
      Title = 'Matching Document.pdf',
      PathOnClient = 'Matching Document.pdf',
      VersionData = Blob.valueOf('Test content'),
      IsMajorVersion = true,
      DocuSign_Envelope_Status__c = 'Sent'
    );
    ContentVersion nonMatchingCv = new ContentVersion(
      Title = 'Non Matching Document.pdf',
      PathOnClient = 'Non Matching Document.pdf',
      VersionData = Blob.valueOf('Other content'),
      IsMajorVersion = true,
      DocuSign_Envelope_Status__c = 'Delivered'
    );
    insert new List<ContentVersion>{ matchingCv, nonMatchingCv };

    matchingCv = [
      SELECT Id, ContentDocumentId, Title, DocuSign_Envelope_Status__c
      FROM ContentVersion
      WHERE Id = :matchingCv.Id
      LIMIT 1
    ];
    nonMatchingCv = [
      SELECT Id, ContentDocumentId, Title, DocuSign_Envelope_Status__c
      FROM ContentVersion
      WHERE Id = :nonMatchingCv.Id
      LIMIT 1
    ];

    ContentDocumentLink matchingLink = new ContentDocumentLink(
      ContentDocumentId = matchingCv.ContentDocumentId,
      LinkedEntityId = acc.Id,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
    ContentDocumentLink nonMatchingLink = new ContentDocumentLink(
      ContentDocumentId = nonMatchingCv.ContentDocumentId,
      LinkedEntityId = otherAcc.Id,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
    insert new List<ContentDocumentLink>{ matchingLink, nonMatchingLink };

    Test.startTest();
    DocuSignNotificationService.handleEnvelopeStatusChange(
      new List<ContentVersion>{ matchingCv, nonMatchingCv }
    );
    Test.stopTest();

    List<Task> tasks = [SELECT Id FROM Task WHERE OwnerId = :creatorUserId];
    System.assertEquals(
      1,
      tasks.size(),
      'Only the matching ContentVersion should create a task'
    );
  }
}
