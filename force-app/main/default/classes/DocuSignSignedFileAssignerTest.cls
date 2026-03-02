@IsTest
public with sharing class DocuSignSignedFileAssignerTest {

    @TestSetup
    static void setupTestData() {
        // 1. Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // 2. Оригинальный файл на Account (Title БЕЗ .pdf в Title, но с .pdf в PathOnClient)
        ContentVersion originalCv = new ContentVersion(
            Title          = 'Test-2025-2026 Bids-Artem Test 10081 A--Contract',
            PathOnClient   = 'Test-2025-2026 Bids-Artem Test 10081 A--Contract.pdf',
            VersionData    = Blob.valueOf('original content'),
            IsMajorVersion = true
        );
        insert originalCv;

        // Получаем ContentDocumentId
        originalCv = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE Id = :originalCv.Id
            LIMIT 1
        ];

        // Линкуем оригинальный файл к Account
        ContentDocumentLink cdlAcc = new ContentDocumentLink(
            ContentDocumentId = originalCv.ContentDocumentId,
            LinkedEntityId    = acc.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert cdlAcc;

        // 3. EmailMessage (минимально валидный)
        EmailMessage em = new EmailMessage(
            Subject     = 'DocuSign Signed Document',
            FromAddress = 'sender@example.com',
            ToAddress   = 'test@example.com',
            Status      = '3',      // типичное значение "Read"/"Sent"[web:26]
            Incoming    = false
        );
        insert em;

        // 4. Подписанный файл на Email (Title С .pdf)
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
            LIMIT 1
        ];

        // Линкуем подписанный файл к Email
        ContentDocumentLink cdlEmail = new ContentDocumentLink(
            ContentDocumentId = signedCv.ContentDocumentId,
            LinkedEntityId    = em.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert cdlEmail;
    }

    @IsTest
    static void testAssignDocuments_Positive_LinkAndRename() {
        // Берём тестовый Account и Email
        Account acc = [
            SELECT Id, Name
            FROM Account
            WHERE Name = 'Test Account'
            LIMIT 1
        ];

        EmailMessage em = [
            SELECT Id
            FROM EmailMessage
            LIMIT 1
        ];

        // Находим подписанный файл ДО запуска логики
        ContentVersion signedBefore = [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Title = 'Test-2025-2026 Bids-Artem Test 10081 A--Contract.pdf'
            LIMIT 1
        ];

        Test.startTest();
        DocuSignSignedFileAssigner.assignDocuments(new List<EmailMessage>{ em });
        Test.stopTest();

        // 1. Проверяем, что файл ПРИВЯЗАН к Account (через ContentDocumentLink)
        Integer linkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :signedBefore.ContentDocumentId
            AND LinkedEntityId = :acc.Id
        ];
        System.assertEquals(
            1,
            linkCount,
            'Signed file must be linked to the Account.'
        );

        // 2. Проверяем, что файл ПЕРЕИМЕНОВАН (Title заканчивается на " - Completed")
        ContentVersion signedAfter = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE Id = :signedBefore.Id
            LIMIT 1
        ];
        System.assertEquals(
            true,
            signedAfter.Title != null &&
            signedAfter.Title.endsWith(' - Completed'),
            'Signed file Title must be renamed with " - Completed".'
        );
    }

    @IsTest
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

        // Signed file with BLANK title attached to the same email
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
            LIMIT 1
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

        // 1. Не должен быть залинкован к Account
        Integer linkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :blankTitleCv.ContentDocumentId
            AND LinkedEntityId = :acc.Id
        ];
        System.assertEquals(
            0,
            linkCount,
            'Blank-titled signed file must be ignored and not linked to Account.'
        );

        // 2. Не должен быть переименован
        ContentVersion postCheck = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE Id = :blankTitleCv.Id
            LIMIT 1
        ];
        Boolean renamed =
            postCheck.Title != null &&
            postCheck.Title.endsWith(' - Completed');

        System.assertEquals(
            false,
            renamed,
            'Blank-titled signed file must not be renamed with " - Completed".'
        );
    }

    @IsTest
    static void testAssignDocuments_NullAndEmptyInput_EarlyReturn() {
        Test.startTest();
        // null
        DocuSignSignedFileAssigner.assignDocuments(null);

        // пустой список
        DocuSignSignedFileAssigner.assignDocuments(new List<EmailMessage>());
        Test.stopTest();

        // Если сюда дошли без исключений — ок.
        System.assertEquals(true, true, 'Method must safely handle null and empty input.');
    }
}
