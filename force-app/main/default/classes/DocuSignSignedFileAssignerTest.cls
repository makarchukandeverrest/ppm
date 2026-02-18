@isTest
public with sharing class DocuSignSignedFileAssignerTest {

    @TestSetup
    static void setupTestData() {
        // Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Оригинальный файл на Account (Title БЕЗ .pdf)
        ContentVersion originalCv = new ContentVersion(
            Title          = 'Test-2025-2026 Bids-Artem Test 10081 A--Contract',
            PathOnClient   = 'Test-2025-2026 Bids-Artem Test 10081 A--Contract.pdf',
            VersionData    = Blob.valueOf('original content'),
            IsMajorVersion = true
        );
        insert originalCv;

        originalCv = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE Id = :originalCv.Id
        ];

        ContentDocumentLink cdlAcc = new ContentDocumentLink(
            ContentDocumentId = originalCv.ContentDocumentId,
            LinkedEntityId    = acc.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert cdlAcc;

        // EmailMessage
        EmailMessage em = new EmailMessage(
            Subject     = 'DocuSign Signed Document',
            FromAddress = 'sender@example.com',
            ToAddress   = 'test@example.com',
            Status      = '3',
            Incoming    = false
        );
        insert em;

        // Signed файл на Email (Title С .pdf)
        ContentVersion signedCv = new ContentVersion(
            Title          = 'Test-2025-2026 Bids-Artem Test 10081 A--Contract.pdf',
            PathOnClient   = 'Test-2025-2026 Bids-Artem Test 10081 A--Contract.pdf',
            VersionData    = Blob.valueOf('signed content'),
            IsMajorVersion = true
        );
        insert signedCv;

        signedCv = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE Id = :signedCv.Id
        ];

        ContentDocumentLink cdlEmail = new ContentDocumentLink(
            ContentDocumentId = signedCv.ContentDocumentId,
            LinkedEntityId    = em.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert cdlEmail;
    }

    @isTest
    static void testAssignDocuments_SignedFileLinkedToAccountAndRenamed() {
        // EmailMessage
        EmailMessage em = [
            SELECT Id
            FROM EmailMessage
            LIMIT 1
        ];

        // Именно подписанный документ — через EmailMessage
        ContentDocumentLink signedLink = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :em.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, signedLink, 'Precondition: signed CDL must exist.');

        Test.startTest();
        DocuSignSignedFileAssigner.assignDocuments(new List<EmailMessage>{ em });
        Test.stopTest();

        // Latest версия этого документа
        ContentVersion latestCv = [
            SELECT Id, Title, ContentDocumentId, IsLatest
            FROM ContentVersion
            WHERE ContentDocumentId = :signedLink.ContentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        System.assertNotEquals(null, latestCv, 'Latest CV must exist.');

        Boolean latestRenamed =
            latestCv.Title != null &&
            latestCv.Title.endsWith(' - Completed');

        Integer anyRenamedCount = 0;
        if (!latestRenamed) {
            anyRenamedCount = [
                SELECT COUNT()
                FROM ContentVersion
                WHERE ContentDocumentId = :signedLink.ContentDocumentId
                AND Title LIKE '% - Completed%'
            ];
        }

        System.assertEquals(
            true,
            latestRenamed || anyRenamedCount > 0,
            'Signed ContentVersion should be renamed with " - Completed". Latest Title: ' + latestCv.Title
        );

        // Линк к Account
        Account acc = [
            SELECT Id
            FROM Account
            WHERE Name = 'Test Account'
            LIMIT 1
        ];

        Integer linkCountToAcc = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :signedLink.ContentDocumentId
            AND LinkedEntityId = :acc.Id
        ];
        System.assertEquals(true, linkCountToAcc > 0,
            'Signed file should be linked to the same Account as original.');
    }

    @isTest
    static void testAssignDocuments_BlankSignedTitle_IsIgnored() {
        Account acc = [
            SELECT Id
            FROM Account
            WHERE Name = 'Test Account'
            LIMIT 1
        ];
        EmailMessage em = [
            SELECT Id
            FROM EmailMessage
            LIMIT 1
        ];

        ContentVersion blankTitleCv = new ContentVersion(
            Title          = '',
            PathOnClient   = 'blank.pdf',
            VersionData    = Blob.valueOf('blank title content'),
            IsMajorVersion = true
        );
        insert blankTitleCv;

        blankTitleCv = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE Id = :blankTitleCv.Id
        ];

        ContentDocumentLink blankCdlEmail = new ContentDocumentLink(
            ContentDocumentId = blankTitleCv.ContentDocumentId,
            LinkedEntityId    = em.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert blankCdlEmail;

        Test.startTest();
        DocuSignSignedFileAssigner.assignDocuments(new List<EmailMessage>{ em });
        Test.stopTest();

        Integer linkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :blankTitleCv.ContentDocumentId
            AND LinkedEntityId = :acc.Id
        ];
        System.assertEquals(0, linkCount,
            'Blank-titled signed file must be ignored and not linked to Account.');

        ContentVersion postCheck = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE Id = :blankTitleCv.Id
            LIMIT 1
        ];
        Boolean renamed =
            postCheck.Title != null &&
            postCheck.Title.endsWith(' - Completed');

        System.assertEquals(false, renamed,
            'Blank-titled signed file must not be renamed with " - Completed".');
    }
}
