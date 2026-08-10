@IsTest
private class DocuSignNotificationServiceTest {

    @TestSetup
    static void setupTestData() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User recordManager = new User(
            FirstName = 'Record',
            LastName = 'Manager',
            Email = 'record.manager@example.com',
            Username = 'record.manager.' + System.currentTimeMillis() + '@example.com',
            Alias = 'rmgr',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert recordManager;

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        StageReferenceSettings__mdt activeStageSettings = [
            SELECT Stage_Names__c
            FROM StageReferenceSettings__mdt
            WHERE DeveloperName = 'Active_Stages'
            LIMIT 1
        ];

        String activeStageName = activeStageSettings != null && String.isNotBlank(activeStageSettings.Stage_Names__c)
            ? activeStageSettings.Stage_Names__c.split(',')[0].trim()
            : 'Information Verified';

        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'Test Contract Bid',
            Customer__c = acc.Id,
            Stage__c = activeStageName,
            Record_Manager__c = recordManager.Id
        );
        insert bid;
    }

    @IsTest
    static void handleEnvelopeStatusChange_CreatesTaskForActiveBid() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        User recordManager = [SELECT Id FROM User WHERE Email = 'record.manager@example.com' LIMIT 1];

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
        DocuSignNotificationService.handleEnvelopeStatusChange(new List<ContentVersion>{ cv });
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id, OwnerId, WhatId, Subject, Status, Priority, ActivityDate
            FROM Task
            WHERE OwnerId = :recordManager.Id
        ];

        System.assertEquals(1, tasks.size(), 'One task should be created for the active Contract Bid');
        Task createdTask = tasks[0];
        System.assertEquals('Completed', createdTask.Status);
        System.assertEquals('Normal', createdTask.Priority);
        System.assertEquals(Date.today(), createdTask.ActivityDate);
        System.assert(createdTask.Subject.contains('Completed'), 'Subject should contain DocuSign status');
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
        DocuSignNotificationService.handleEnvelopeStatusChange(new List<ContentVersion>{ cv });
        Test.stopTest();

        List<Task> tasks = [SELECT Id FROM Task];
        System.assertEquals(0, tasks.size(), 'No task should be created when ContentVersion is not linked to an Account');
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
        DocuSignNotificationService.handleEnvelopeStatusChange(new List<ContentVersion>{ cv });
        Test.stopTest();

        List<Task> tasks = [SELECT Id FROM Task];
        System.assertEquals(0, tasks.size(), 'No task should be created when Account has no active Contract Bid');
    }

    @IsTest
    static void handleEnvelopeStatusChange_InactiveStage_NoTaskCreated() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        User recordManager = [SELECT Id FROM User WHERE Email = 'record.manager@example.com' LIMIT 1];

        Contract_Bid__c inactiveBid = new Contract_Bid__c(
            Name = 'Inactive Bid',
            Customer__c = acc.Id,
            Stage__c = 'Closed - LOST',
            Record_Manager__c = recordManager.Id
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
        DocuSignNotificationService.handleEnvelopeStatusChange(new List<ContentVersion>{ cv });
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id FROM Task
            WHERE WhatId = :inactiveBid.Id
        ];
        System.assertEquals(0, tasks.size(), 'No task should be created for a Contract Bid with inactive stage');
    }

    @IsTest
    static void handleEnvelopeStatusChange_MultipleVersions_OnlyMatchingProcessed() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        User recordManager = [SELECT Id FROM User WHERE Email = 'record.manager@example.com' LIMIT 1];

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
        DocuSignNotificationService.handleEnvelopeStatusChange(new List<ContentVersion>{ matchingCv, nonMatchingCv });
        Test.stopTest();

        List<Task> tasks = [SELECT Id FROM Task WHERE OwnerId = :recordManager.Id];
        System.assertEquals(1, tasks.size(), 'Only the matching ContentVersion should create a task');
    }
}
