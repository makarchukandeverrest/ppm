@IsTest
private class SharePointCVAccountLinkerTest {

    @TestSetup
    static void setupTestData() {
        insert new Account(Name = 'Waycroft');
    }

    @IsTest
    static void testLinkToAccounts_CreatesAccountLink() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Waycroft' LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title = 'Waycroft-2026-2027 Bids-The Waycroft 11567 A -- Contract.docx',
            PathOnClient = 'Contract.docx',
            VersionData = Blob.valueOf('contract body'),
            IsMajorVersion = true,
            SharePoint_External_Id__c = '{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}',
            DocuSign_Envelope_Status__c = 'Start'
        );

        Test.startTest();
        insert cv;
        Test.stopTest();

        ContentVersion reloaded = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :reloaded.ContentDocumentId
            AND LinkedEntityId = :acc.Id
        ];
        System.assertEquals(1, links.size(), 'SharePoint file should be linked to matching Account');
    }

    @IsTest
    static void testLinkToAccounts_SkipsWithoutExternalId() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Waycroft' LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title = 'Waycroft-2026-2027 Bids-The Waycroft 11567 A -- Contract.docx',
            PathOnClient = 'Contract.docx',
            VersionData = Blob.valueOf('contract body'),
            IsMajorVersion = true
        );

        Test.startTest();
        insert cv;
        Test.stopTest();

        ContentVersion reloaded = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :reloaded.ContentDocumentId
            AND LinkedEntityId = :acc.Id
        ];
        System.assertEquals(0, links.size(), 'Non-SharePoint files should not be auto-linked');
    }

    @IsTest
    static void testLinkToAccounts_IdempotentWhenAlreadyLinked() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Waycroft' LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title = 'Waycroft-2026-2027 Bids-The Waycroft 11567 A -- Contract.docx',
            PathOnClient = 'Contract.docx',
            VersionData = Blob.valueOf('contract body'),
            IsMajorVersion = true,
            SharePoint_External_Id__c = '{bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee}'
        );
        insert cv;

        ContentVersion reloaded = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        // Second version of same document should not create a duplicate Account link.
        ContentVersion v2 = new ContentVersion(
            Title = 'Waycroft-2026-2027 Bids-The Waycroft 11567 A -- Contract.docx',
            PathOnClient = 'Contract.docx',
            VersionData = Blob.valueOf('updated body'),
            ContentDocumentId = reloaded.ContentDocumentId,
            SharePoint_External_Id__c = '{cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee}'
        );

        Test.startTest();
        insert v2;
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :reloaded.ContentDocumentId
            AND LinkedEntityId = :acc.Id
        ];
        System.assertEquals(1, links.size(), 'Account link should remain unique after new version');
    }

    @IsTest
    static void testExtractFolderName() {
        System.assertEquals(
            'Waycroft',
            SharePointContentVersionAccountLinker.extractFolderName(
                'Waycroft-2026-2027 Bids-The Waycroft 11567 A -- Contract.docx'
            )
        );
        System.assertEquals(null, SharePointContentVersionAccountLinker.extractFolderName('NoMarker.docx'));
        System.assertEquals(null, SharePointContentVersionAccountLinker.extractFolderName(null));
    }

    @IsTest
    static void testNamesMatch() {
        System.assertEquals(true, SharePointContentVersionAccountLinker.namesMatch('Waycroft', 'The Waycroft'));
        System.assertEquals(true, SharePointContentVersionAccountLinker.namesMatch('Waycroft', 'Waycroft'));
        System.assertEquals(false, SharePointContentVersionAccountLinker.namesMatch('Waycroft', 'Oronoco'));
    }
}
