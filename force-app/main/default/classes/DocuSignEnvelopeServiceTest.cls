@IsTest
private class DocuSignEnvelopeServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create User to act as Record Manager
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User recordManager = new User(
            FirstName = 'Test',
            LastName = 'Manager',
            Email = 'manager@example.com',
            Username = 'test.manager.' + System.currentTimeMillis() + '@example.com',
            Alias = 'tmanager',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert recordManager;

        Account acc = new Account(
            Name = 'Test Account',
            Email__c = 'test@example.com'
        );
        insert acc;

        Contract_Bid__c cb = new Contract_Bid__c(
            Name = 'Test Contract Bid',
            Customer__c = acc.Id,
            Record_Manager__c = recordManager.Id // assign created user!
        );
        insert cb;

        ContentVersion cv = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDoc.pdf',
            VersionData = Blob.valueOf('Dummy Content'),
            IsMajorVersion = true,
            To_Sent__c = true,
            DocuSign_Envelope_Status__c = 'Delivered'
        );
        insert cv;

        // Create a Welcome Letter content version and link it to the Account
        ContentVersion cv2 = new ContentVersion(
            Title = 'Test Welcome Letter',
            PathOnClient = 'Test Welcome Letter.pdf',
            VersionData = Blob.valueOf('Dummy Content 2'),
            IsMajorVersion = true,
            To_Sent__c = true
        );
        insert cv2;

        // After insert, query back to get ContentDocumentId and create the link
        ContentVersion cv2Reloaded = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv2.Id
            LIMIT 1
        ];
        ContentDocumentLink linkWelcome = new ContentDocumentLink(
            ContentDocumentId = cv2Reloaded.ContentDocumentId,
            LinkedEntityId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert linkWelcome;
    }


    @IsTest
    static void testSendEnvelopeWithSignature_success() {
        // Arrange
        Account acc = [SELECT Id, Name, Email__c FROM Account LIMIT 1];
        Contract_Bid__c cb = [SELECT Id, Name, Stage__c FROM Contract_Bid__c LIMIT 1];
        // Ensure Stage__c is active so service logic can include it when needed

        ContentVersion cv = [SELECT Id, ContentDocumentId, Title, VersionData, To_Sent__c, FileExtension, DocuSign_Envelope_Status__c FROM ContentVersion LIMIT 1];
        ContentDocumentLink link =  new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert link;
        FileWrapper fw = new FileWrapper(cv);

        List<AccountWithFiles> accWithFiles = new List<AccountWithFiles>{
            new AccountWithFiles(
                acc.Id,
                acc.Name,
                acc.Email__c,
                cb,
                new List<FileWrapper>{ fw },
                true
            )
        };
        String accountsJson = JSON.serialize(accWithFiles);

        // Mock callout
        Test.setMock(HttpCalloutMock.class, new DocuSignMockResponseGenerator());

        // Act
        Test.startTest();
            DocuSignEnvelopeService.sendEnvelopeWithSignature(accountsJson);
        Test.stopTest();
        // Assert
        Contract_Bid__c cbAfter = [SELECT Stage__c FROM Contract_Bid__c WHERE Id = :cb.Id];
        System.assertEquals('Contract Sent via DocuSign', cbAfter.Stage__c);

        Integer emailCount = [
            SELECT COUNT()
            FROM EmailMessage
            WHERE RelatedToId = :cb.Id
        ];
        System.assertEquals(1, emailCount, 'One EmailMessage should be created');
    }
    

    // Mock for HttpCallout
    private class DocuSignMockResponseGenerator implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"envelopeId": "12345", "status": "sent"}');
            res.setStatusCode(201);
            return res;
        }
    }
    
}