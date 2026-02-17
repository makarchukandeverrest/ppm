@isTest
public with sharing class DocuSignSignedFileAssignerTest {

    @TestSetup
    static void setupTestData() {
        // Base Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName  = 'Contact',
            Email     = 'test@example.com',
            AccountId = acc.Id
        );
        insert con;

        // 1) Original file on Account (without extension in Title)
        ContentVersion originalCv = new ContentVersion(
            Title        = 'Test-2025-2026 Bids-Artem Test 10081 A--Contract',
            PathOnClient = 'Test-2025-2026 Bids-Artem Test 10081 A--Contract',
            VersionData  = Blob.valueOf('original content'),
            IsMajorVersion = true
        );
        insert originalCv;

        // Get ContentDocumentId (insert of ContentVersion creates ContentDocument)
        originalCv = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE Id = :originalCv.Id
        ];

        // Link original file to Account
        ContentDocumentLink cdlAcc = new ContentDocumentLink(
            ContentDocumentId = originalCv.ContentDocumentId,
            LinkedEntityId    = acc.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert cdlAcc;

        // 2) EmailMessage with signed file (same base title + .pdf)
        // Create EmailMessage record
        EmailMessage em = new EmailMessage();
        em.Subject      = 'DocuSign Signed Document';
        em.FromAddress  = 'sender@example.com';
        em.ToAddress    = 'test@example.com';
        em.Status       = '3'; // sent
        em.Incoming     = false;
        // relatedToId / FromId можно не заполнять для этого теста
        insert em;

        // Create signed ContentVersion (DocuSign-returned)
        ContentVersion signedCv = new ContentVersion(
            Title        = 'Test-2025-2026 Bids-Artem Test 10081 A--Contract.pdf',
            PathOnClient = 'Test-2025-2026 Bids-Artem Test 10081 A--Contract.pdf',
            VersionData  = Blob.valueOf('signed content'),
            IsMajorVersion = true
        );
        insert signedCv;

        signedCv = [
            SELECT Id, ContentDocumentId, Title, FileExtension
            FROM ContentVersion
            WHERE Id = :signedCv.Id
        ];

        // Link signed file to EmailMessage
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
        // Arrange: get EmailMessage from setup
        EmailMessage em = [
            SELECT Id
            FROM EmailMessage
            LIMIT 1
        ];

        Test.startTest();
        DocuSignSignedFileAssigner.assignDocuments(new List<EmailMessage>{ em });
        Test.stopTest();

        // Assert: signed file renamed with " - Completed"
        ContentVersion signedAfter = [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Title LIKE 'Test-2025-2026 Bids-Artem Test 10081 A--Contract%.pdf - Completed'
            LIMIT 1
        ];
        System.assertNotEquals(null, signedAfter, 'Signed ContentVersion should be renamed with " - Completed".');

        // Assert: there is a link from signed file to the Account
        Account acc = [
            SELECT Id
            FROM Account
            WHERE Name = 'Test Account'
            LIMIT 1
        ];

        ContentDocumentLink linkToAcc = [
            SELECT Id, ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :signedAfter.ContentDocumentId
            AND LinkedEntityId = :acc.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, linkToAcc, 'Signed file should be linked to the same Account as original.');
    }
}