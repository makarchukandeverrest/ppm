@IsTest
private class DocuSignDfsleEnvelopeServiceTest {
    @TestSetup
    static void setupTestData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        // Create "Roman Shestakov" so the service's hard-coded CC query finds a row.
        User romanUser = new User(
            FirstName = 'Roman',
            LastName = 'Shestakov',
            Email = 'roman.shestakov@example.com',
            Username = 'roman.shestakov.' + System.currentTimeMillis() + '@example.com',
            Alias = 'rshes',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert romanUser;

        // Create User to act as Record Manager (copied structure from DocuSignEnvelopeServiceTest).
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

        // Users for Lead Generator / Lead Owner (used by getAccountToUsersMap).
        User leadGenerator = new User(
            FirstName = 'Lead',
            LastName = 'Generator',
            Email = 'lead.generator@example.com',
            Username = 'lead.generator.' + System.currentTimeMillis() + '@example.com',
            Alias = 'lgen',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        User leadOwner = new User(
            FirstName = 'Lead',
            LastName = 'Owner',
            Email = 'lead.owner@example.com',
            Username = 'lead.owner.' + System.currentTimeMillis() + '@example.com',
            Alias = 'lown',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert new List<User>{ leadGenerator, leadOwner };

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Pick one active stage name from custom metadata so getAccountToUsersMap returns these users.
        StageReferenceSettings__mdt settings = [
            SELECT Stage_Names__c
            FROM StageReferenceSettings__mdt
            WHERE DeveloperName = 'Active_Stages'
            LIMIT 1
        ];
        String stageName = settings != null && String.isNotBlank(settings.Stage_Names__c)
            ? settings.Stage_Names__c.split(',')[0].trim()
            : 'Active';

        Contract_Bid__c cb = new Contract_Bid__c(
            Name = 'Test Contract Bid',
            Customer__c = acc.Id,
            Record_Manager__c = recordManager.Id,
            Stage__c = stageName,
            Lead_Generator__c = leadGenerator.Id,
            Lead_Owner__c = leadOwner.Id
        );
        insert cb;

        // Main contract document (dfsle service will update DocuSign_Envelope_Id__c on this ContentVersion).
        ContentVersion mainCv = new ContentVersion(
            Title = 'Dfsle Main Contract',
            PathOnClient = 'Main.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 dfsle test'),
            IsMajorVersion = true,
            To_Sent__c = true
        );
        insert mainCv;

        // Welcome letter for new customer envelope (extra docs are SharePoint links in email).
        ContentVersion welcomeCv = new ContentVersion(
            Title = 'Customer Welcome Letter',
            PathOnClient = 'Welcome.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 welcome'),
            IsMajorVersion = true
        );
        insert welcomeCv;

        ContentVersion welcomeReloaded = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :welcomeCv.Id
            LIMIT 1
        ];
        insert new ContentDocumentLink(
            ContentDocumentId = welcomeReloaded.ContentDocumentId,
            LinkedEntityId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

    }

    @IsTest
    static void testSendEnvelopeWithSignature_success() {
        // Arrange payload exactly like contractsSendSelector.js sends.
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Contract_Bid__c cb = [SELECT Id, Stage__c FROM Contract_Bid__c LIMIT 1];

        ContentVersion mainCv = [
            SELECT Id, ContentDocumentId, Title, To_Sent__c, FileExtension, DocuSign_Envelope_Id__c
            FROM ContentVersion
            WHERE Title = 'Dfsle Main Contract'
            LIMIT 1
        ];
        FileWrapper fw = new FileWrapper(mainCv);
        fw.ToSent = true;

        List<AccountWithFiles> accWithFiles = new List<AccountWithFiles>{
            new AccountWithFiles(
                acc.Id,
                acc.Name,
                'customer@example.com',
                cb,
                new List<FileWrapper>{ fw },
                false,
                '3',
                '120',
                null
            )
        };
        String accountsJson = JSON.serialize(accWithFiles);

        // Act (DFSLE service fakes envelope id in tests; no callout mock needed).
        Test.startTest();
        DocuSignDfsleEnvelopeService.sendEnvelopeWithSignature(accountsJson);
        Test.stopTest();

        // Assert: stage updated
        Contract_Bid__c cbAfter = [
            SELECT Stage__c
            FROM Contract_Bid__c
            WHERE Id = :cb.Id
        ];
        System.assertEquals('Contract Sent via DocuSign', cbAfter.Stage__c);

        // Assert: EmailMessage created (InsertEmailMessagesJob runs in stopTest)
        Integer emailCount = [
            SELECT COUNT()
            FROM EmailMessage
            WHERE RelatedToId = :cb.Id
        ];
        System.assertEquals(1, emailCount, 'One EmailMessage should be created');

        // Assert: ContentVersion updated with the test envelope id
        ContentVersion updated = [
            SELECT DocuSign_Envelope_Id__c, To_Sent__c
            FROM ContentVersion
            WHERE Id = :mainCv.Id
        ];
        System.assertEquals('TEST-DFSLE-ENVELOPE', updated.DocuSign_Envelope_Id__c);
        System.assertEquals(false, updated.To_Sent__c);
    }

    @IsTest
    static void testSendEnvelopeWithSignature_blankOrNoSelection_doesNothing() {
        // Blank payload: should not throw.
        DocuSignDfsleEnvelopeService.sendEnvelopeWithSignature('');

        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Contract_Bid__c cb = [SELECT Id FROM Contract_Bid__c LIMIT 1];
        ContentVersion mainCv = [
            SELECT Id, ContentDocumentId, Title, To_Sent__c, FileExtension
            FROM ContentVersion
            WHERE Title = 'Dfsle Main Contract'
            LIMIT 1
        ];

        FileWrapper fw = new FileWrapper(mainCv);
        fw.ToSent = false;
        List<AccountWithFiles> accWithFiles = new List<AccountWithFiles>{
            new AccountWithFiles(
                acc.Id,
                acc.Name,
                'customer@example.com',
                cb,
                new List<FileWrapper>{ fw },
                false,
                null,
                null,
                null
            )
        };

        Integer emailBefore = [SELECT COUNT() FROM EmailMessage WHERE RelatedToId = :cb.Id];
        Test.startTest();
        DocuSignDfsleEnvelopeService.sendEnvelopeWithSignature(JSON.serialize(accWithFiles));
        Test.stopTest();
        Integer emailAfter = [SELECT COUNT() FROM EmailMessage WHERE RelatedToId = :cb.Id];

        System.assertEquals(emailBefore, emailAfter, 'No EmailMessage should be created if no files selected.');
    }

    @IsTest
    static void testGetContentVersionIds_newCustomer_includesWelcomeAndMainOnly() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion mainCv = [SELECT Id FROM ContentVersion WHERE Title = 'Dfsle Main Contract' LIMIT 1];

        List<Id> cvIds = DocuSignDfsleEnvelopeService.getContentVersionIdsForEnvelope(
            mainCv.Id,
            true,
            acc.Id
        );
        System.assertEquals(2, cvIds.size(), 'Expected welcome letter + main contract only.');
        System.assertEquals(mainCv.Id, cvIds[1], 'Main contract should come right after welcome letter when present.');
    }

    @IsTest
    static void testBuildEnvelopeEmailBody_includesLabeledLinksInBody() {
        Map<String, String> developerNameByLabel = new Map<String, String>{
            'Recommendation Letter' => 'Recommendation_Letter',
            'General References' => 'General_References',
            'COI' => 'COI'
        };
        List<String> labelsInOrder = new List<String>{
            'Recommendation Letter',
            'General References',
            'COI'
        };

        List<String> items = new List<String>();
        for (String label : labelsInOrder) {
            Document_Link__mdt docLink = Document_Link__mdt.getInstance(developerNameByLabel.get(label));
            System.assertNotEquals(null, docLink, label + ' Document_Link metadata should exist.');
            System.assertNotEquals(null, docLink.Sharing_Link__c, label + ' sharing link should be configured.');
            System.assertEquals(label, docLink.Label, label + ' metadata label should match envelope link text.');
            items.add('<li><a href="' + docLink.Sharing_Link__c + '">' + label + '</a></li>');
        }

        String body =
            '<p>I am sending you this request for your electronic signature, please review and electronically sign by following the link. Additional reference documents:</p>' +
            '<ul>' +
            String.join(items, '') +
            '</ul>';

        System.assert(
            body.contains('I am sending you this request for your electronic signature'),
            'Expected intro in envelope email body.'
        );
        System.assert(body.contains('https://premierswim-my.sharepoint.com/'), 'Expected SharePoint href in body.');
        System.assert(body.contains('>COI</a>'), 'Expected human-readable COI link label.');
        System.assert(body.contains('>Recommendation Letter</a>'), 'Expected Recommendation Letter link.');
        System.assert(body.contains('>General References</a>'), 'Expected General References link.');
    }

    @IsTest
    static void testDocuSignIdResolutionPath_inTest() {
        // This test exercises the dynamic query path (dfsle__EnvelopeStatus__c / dfsle__Envelope__c).
        Contract_Bid__c cb = [SELECT Id FROM Contract_Bid__c LIMIT 1];
        ContentVersion mainCv = [
            SELECT Id, DocuSign_Envelope_Id__c
            FROM ContentVersion
            WHERE Title = 'Dfsle Main Contract'
            LIMIT 1
        ];

        String expected = 'DYN-DFSLE-ID-123';

        // Create a dfsle envelope row that the dynamic resolver can find.
        // Prefer dfsle__EnvelopeStatus__c, fall back to dfsle__Envelope__c.
        Map<String, Schema.SObjectType> g = Schema.getGlobalDescribe();
        String objName = g.containsKey('dfsle__EnvelopeStatus__c')
            ? 'dfsle__EnvelopeStatus__c'
            : (g.containsKey('dfsle__Envelope__c') ? 'dfsle__Envelope__c' : null);
        System.assertNotEquals(null, objName, 'DFSLE envelope object is expected to exist in this org.');

        SObject row = g.get(objName).newSObject();
        row.put('dfsle__DocuSignId__c', expected);

        // Populate any one of the supported source lookup fields.
        // Try in order and use the first available on this object.
        List<String> candidateFields = new List<String>{
            'dfsle__Source_Id__c',
            'dfsle__SourceId__c',
            'dfsle__ParentId__c',
            'dfsle__Contract_Bid__c'
        };
        Map<String, Schema.SObjectField> fm = g.get(objName).getDescribe().fields.getMap();
        Boolean setSource = false;
        for (String f : candidateFields) {
            if (fm.containsKey(f.toLowerCase())) {
                row.put(f, cb.Id);
                setSource = true;
                break;
            }
        }
        System.assertEquals(true, setSource, 'No compatible source field found on ' + objName);

        insert row;

        // Force resolver path during test, but still avoid real send.
        DocuSignDfsleEnvelopeService.FORCE_RESOLVE_DOCUSIGN_ID_IN_TEST = true;
        Test.startTest();
        String resolved = DocuSignDfsleEnvelopeService.sendEnvelope(
            cb.Id,
            mainCv.Id,
            'customer@example.com',
            'Customer Name',
            false,
            null,
            new List<User>(),
            null,
            null
        );
        Test.stopTest();
        DocuSignDfsleEnvelopeService.FORCE_RESOLVE_DOCUSIGN_ID_IN_TEST = false;

        System.assertEquals(expected, resolved, 'Expected dynamic DocuSignId resolver to return inserted id.');
    }
}
