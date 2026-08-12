@IsTest
private class DocuSignDfsleEnvelopeServiceTest {
    @TestSetup
    static void setupTestData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        // Create default CC users so the service's hard-coded CC query finds rows.
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
        System.assertEquals(
            ('TEST-DFSLE-ENVELOPE-' + mainCv.Id).toUpperCase(),
            updated.DocuSign_Envelope_Id__c
        );
        System.assertEquals(false, updated.To_Sent__c);
    }

    @IsTest
    static void testSendEnvelope_multipleInvocations_updateEachContentVersion() {
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        Contract_Bid__c cb = [SELECT Id FROM Contract_Bid__c LIMIT 1];

        ContentVersion mainCv = [
            SELECT Id
            FROM ContentVersion
            WHERE Title = 'Dfsle Main Contract'
            LIMIT 1
        ];
        ContentVersion secondCv = new ContentVersion(
            Title = 'Dfsle Second Contract',
            PathOnClient = 'Second.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 dfsle test 2'),
            IsMajorVersion = true,
            To_Sent__c = true
        );
        insert secondCv;

        Test.startTest();
        DocuSignDfsleEnvelopeService.sendEnvelope(
            cb.Id,
            mainCv.Id,
            'customer@example.com',
            acc.Name,
            false,
            acc.Id,
            null,
            new List<DocuSignDfsleEnvelopeService.CcRecipient>(),
            null,
            null
        );
        DocuSignDfsleEnvelopeService.sendEnvelope(
            cb.Id,
            secondCv.Id,
            'customer@example.com',
            acc.Name,
            false,
            acc.Id,
            null,
            new List<DocuSignDfsleEnvelopeService.CcRecipient>(),
            null,
            null
        );
        Test.stopTest();

        List<ContentVersion> updated = [
            SELECT DocuSign_Envelope_Id__c, To_Sent__c
            FROM ContentVersion
            WHERE Id IN :new Set<Id>{ mainCv.Id, secondCv.Id }
        ];
        System.assertEquals(2, updated.size());
        for (ContentVersion cv : updated) {
            System.assertEquals(
                ('TEST-DFSLE-ENVELOPE-' + cv.Id).toUpperCase(),
                cv.DocuSign_Envelope_Id__c
            );
            System.assertEquals(false, cv.To_Sent__c);
        }
    }

    @IsTest
    static void testBatchHttpSender_singleDfsleRequest() {
        Contract_Bid__c cb = [SELECT Id FROM Contract_Bid__c LIMIT 1];
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        ContentVersion mainCv = [SELECT Id FROM ContentVersion WHERE Title = 'Dfsle Main Contract' LIMIT 1];

        List<DocuSignDfsleEnvelopeService.DfsleEnvelopeSendRequest> requests = new List<DocuSignDfsleEnvelopeService.DfsleEnvelopeSendRequest>{
            new DocuSignDfsleEnvelopeService.DfsleEnvelopeSendRequest(
                cb.Id,
                mainCv.Id,
                'customer@example.com',
                acc.Name,
                false,
                acc.Id,
                null,
                new List<DocuSignDfsleEnvelopeService.CcRecipient>(),
                null,
                null
            )
        };

        Test.startTest();
        Database.executeBatch(new BatchHttpSender(requests), 1);
        Test.stopTest();

        ContentVersion updated = [
            SELECT DocuSign_Envelope_Id__c, To_Sent__c
            FROM ContentVersion
            WHERE Id = :mainCv.Id
        ];
        System.assertEquals(
            ('TEST-DFSLE-ENVELOPE-' + mainCv.Id).toUpperCase(),
            updated.DocuSign_Envelope_Id__c
        );
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
    static void testBuildEnvelopeEmailSubject_usesSecondYearFromContractFileName() {
        String subject = DocuSignDfsleEnvelopeService.buildEnvelopeEmailSubject(
            'Regents Park Pool 1',
            'Regents Park Pool 1-2026-2027 Bids-Regents Park Pool 1 10290 A--Contract.docx'
        );

        System.assertEquals(
            '2027 Premier Pool Management Proposal - Regents Park Pool 1',
            subject,
            'Expected subject to use the second year from the contract file name.'
        );
    }

    @IsTest
    static void testBuildEnvelopeEmailSubject_withoutYearRange_omitsYearPrefix() {
        String subject = DocuSignDfsleEnvelopeService.buildEnvelopeEmailSubject(
            'Regents Park Pool 1',
            'Regents Park Pool 1 Contract'
        );

        System.assertEquals(
            'Premier Pool Management Proposal - Regents Park Pool 1',
            subject,
            'Expected subject without a year range to omit the year prefix.'
        );
    }

    @IsTest
    static void testBuildEnvelopeEmailBody_existingClient_usesDefaultBodyAndSameSubjectFormat() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        String subject = DocuSignDfsleEnvelopeService.buildEnvelopeEmailSubject(
            'Regents Park Pool 1',
            'Regents Park Pool 1-2026-2027 Bids-Regents Park Pool 1 10290 A--Contract.docx'
        );
        String body = DocuSignDfsleEnvelopeService.buildEnvelopeEmailBody(false, acc.Id);

        System.assertEquals(
            '2027 Premier Pool Management Proposal - Regents Park Pool 1',
            subject,
            'Existing clients should use the same dynamic subject format as new clients.'
        );
        System.assertNotEquals(null, body, 'Expected a default envelope body for existing clients.');
        System.assert(
            body.contains('Please review the attached pool management proposal'),
            'Expected proposal review instructions for existing clients.'
        );
        System.assert(
            body.contains('Best regards'),
            'Expected closing signature for existing clients.'
        );
        System.assert(
            body.contains('Premier Pool Management Team'),
            'Expected team signature for existing clients.'
        );
        System.assert(
            !body.contains('Thank you for considering our pool management proposal'),
            'Existing clients should not receive the new-customer proposal email body.'
        );
    }

    @IsTest
    static void testBuildEnvelopeEmailBody_includesContractCopyWithContactFirstName() {
        Contact primaryContact = new Contact(
            FirstName = 'Jane',
            LastName = 'Smith',
            Email = 'jane.smith@example.com'
        );
        insert primaryContact;

        Account acc = [SELECT Id FROM Account LIMIT 1];
        acc.Primary_Contact__c = primaryContact.Id;
        update acc;

        String body = DocuSignDfsleEnvelopeService.buildEnvelopeEmailBody(true, acc.Id);

        System.assertNotEquals(null, body, 'Expected envelope email body for new customers.');
        System.assert(body.contains('Hello Jane,'), 'Expected greeting with contact first name.');
        System.assert(
            body.contains('Thank you for considering our pool management proposal'),
            'Expected proposal intro in envelope email body.'
        );
        System.assert(
            body.contains('Our "turn-key" pool management contract includes:'),
            'Expected turn-key contract section in envelope email body.'
        );
        System.assert(
            body.contains('Spring Start-up (inspection, repairs, health department inspection and permits)'),
            'Expected contract bullet list in envelope email body.'
        );
        System.assert(
            body.contains('Please let us know if there is anything else that we can do to earn your business.'),
            'Expected closing paragraph in envelope email body.'
        );
        System.assert(
            body.contains('Additional reference documents:'),
            'Expected reference documents section in envelope email body.'
        );
        System.assert(body.contains('>COI</a>'), 'Expected human-readable COI link label.');
        System.assert(
            !body.contains('>Recommendation Letter</a>'),
            'Recommendation Letter link should not be included.'
        );
        System.assert(
            !body.contains('>General References</a>'),
            'General References link should not be included.'
        );
        System.assert(body.contains('Best Regards,'), 'Expected email signature greeting.');
        System.assert(body.contains('Premier Pool Management Team'), 'Expected email signature team name.');
        System.assert(
            body.contains('href="https://www.premierswim.com/"'),
            'Expected website link in envelope email body.'
        );
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
            null,
            new List<DocuSignDfsleEnvelopeService.CcRecipient>(),
            null,
            null
        );
        Test.stopTest();
        DocuSignDfsleEnvelopeService.FORCE_RESOLVE_DOCUSIGN_ID_IN_TEST = false;

        System.assertEquals(expected, resolved, 'Expected dynamic DocuSignId resolver to return inserted id.');
    }

    @IsTest
    static void testSendEnvelope_docxSchedulesSentPdfSaverJob() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contract_Bid__c cb = [SELECT Id FROM Contract_Bid__c LIMIT 1];

        ContentVersion docxCv = new ContentVersion(
            Title = 'Dfsle Docx Contract.docx',
            PathOnClient = 'Dfsle Docx Contract.docx',
            VersionData = Blob.valueOf('docx-content'),
            IsMajorVersion = true,
            To_Sent__c = true
        );
        insert docxCv;

        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :docxCv.Id
            LIMIT 1
        ].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        DocuSignSentPdfService.skipCalloutInTest = true;
        DocuSignSentPdfService.testPdfBlob = Blob.valueOf('%PDF-1.4 sent via envelope');

        Test.startTest();
        DocuSignDfsleEnvelopeService.sendEnvelope(
            cb.Id,
            docxCv.Id,
            'customer@example.com',
            acc.Name,
            false,
            acc.Id,
            null,
            new List<DocuSignDfsleEnvelopeService.CcRecipient>(),
            null,
            null
        );
        Test.stopTest();

        DocuSignSentPdfService.skipCalloutInTest = false;
        DocuSignSentPdfService.testPdfBlob = null;

        ContentVersion savedPdf = [
            SELECT Id, Title, DocuSign_Envelope_Id__c
            FROM ContentVersion
            WHERE Title = 'Dfsle Docx Contract.pdf'
            LIMIT 1
        ];
        System.assertEquals(
            ('TEST-DFSLE-ENVELOPE-' + docxCv.Id).toUpperCase(),
            savedPdf.DocuSign_Envelope_Id__c
        );
    }
}
