@IsTest
private class DocuSignSentPdfServiceTest {

    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'PDF Save Test Account');
        insert acc;

        ContentVersion docxCv = new ContentVersion(
            Title = 'Customer-2026-2027 Bids-Customer 10290 A--Contract.docx',
            PathOnClient = 'Customer-2026-2027 Bids-Customer 10290 A--Contract.docx',
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
    }

    @IsTest
    static void testBuildPdfTitle_replacesDocxExtension() {
        String pdfTitle = DocuSignSentPdfService.buildPdfTitle(
            'Customer-2026-2027 Bids-Customer 10290 A--Contract.docx'
        );

        System.assertEquals(
            'Customer-2026-2027 Bids-Customer 10290 A--Contract.pdf',
            pdfTitle
        );
    }

    @IsTest
    static void testRequiresSentPdfCopy_trueForDocx_falseForPdf() {
        ContentVersion docxCv = [
            SELECT Id, Title, FileExtension
            FROM ContentVersion
            WHERE Title LIKE '%Contract.docx'
            LIMIT 1
        ];

        ContentVersion pdfCv = new ContentVersion(
            Title = 'Contract.pdf',
            PathOnClient = 'Contract.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'),
            IsMajorVersion = true
        );
        insert pdfCv;
        pdfCv = [
            SELECT Id, Title, FileExtension
            FROM ContentVersion
            WHERE Id = :pdfCv.Id
            LIMIT 1
        ];

        System.assertEquals(true, DocuSignSentPdfService.requiresSentPdfCopy(docxCv));
        System.assertEquals(false, DocuSignSentPdfService.requiresSentPdfCopy(pdfCv));
    }

    @IsTest
    static void testSaveSentPdfFromEnvelope_createsPdfOnAccount() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion sourceCv = [
            SELECT Id, Title, FileExtension
            FROM ContentVersion
            WHERE Title LIKE '%Contract.docx'
            LIMIT 1
        ];

        DocuSignSentPdfService.skipCalloutInTest = true;
        DocuSignSentPdfService.testPdfBlob = Blob.valueOf('%PDF-1.4 sent contract copy');

        Test.startTest();
        DocuSignSentPdfService.saveSentPdfFromEnvelope(
            acc.Id,
            sourceCv.Id,
            'TEST-ENVELOPE-123'
        );
        Test.stopTest();

        DocuSignSentPdfService.skipCalloutInTest = false;
        DocuSignSentPdfService.testPdfBlob = null;

        ContentVersion savedPdf = [
            SELECT Id, Title, ContentDocumentId, DocuSign_Envelope_Id__c, DocuSign_Envelope_Status__c, To_Sent__c
            FROM ContentVersion
            WHERE Title = 'Customer-2026-2027 Bids-Customer 10290 A--Contract.pdf'
            LIMIT 1
        ];
        System.assertEquals(null, savedPdf.DocuSign_Envelope_Id__c);
        System.assertEquals('Sent', savedPdf.DocuSign_Envelope_Status__c);
        System.assertEquals(false, savedPdf.To_Sent__c);

        Integer accountLinks = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :acc.Id
            AND ContentDocumentId = :savedPdf.ContentDocumentId
        ];
        System.assertEquals(1, accountLinks, 'Saved PDF should be linked to the Account.');
    }

    @IsTest
    static void testSaveSentPdfFromEnvelope_replacesExistingPdfOnAccount() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion sourceCv = [
            SELECT Id
            FROM ContentVersion
            WHERE Title LIKE '%Contract.docx'
            LIMIT 1
        ];

        ContentVersion existingPdf = new ContentVersion(
            Title = 'Customer-2026-2027 Bids-Customer 10290 A--Contract.pdf',
            PathOnClient = 'Customer-2026-2027 Bids-Customer 10290 A--Contract.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 existing'),
            IsMajorVersion = true
        );
        insert existingPdf;

        Id existingDocId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :existingPdf.Id
            LIMIT 1
        ].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = existingDocId,
            LinkedEntityId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        DocuSignSentPdfService.skipCalloutInTest = true;
        DocuSignSentPdfService.testPdfBlob = Blob.valueOf('%PDF-1.4 replaced sent copy');

        Test.startTest();
        DocuSignSentPdfService.saveSentPdfFromEnvelope(
            acc.Id,
            sourceCv.Id,
            'TEST-ENVELOPE-456'
        );
        Test.stopTest();

        DocuSignSentPdfService.skipCalloutInTest = false;
        DocuSignSentPdfService.testPdfBlob = null;

        ContentVersion savedPdf = [
            SELECT Id, ContentSize
            FROM ContentVersion
            WHERE Title = 'Customer-2026-2027 Bids-Customer 10290 A--Contract.pdf'
            AND IsLatest = true
            LIMIT 1
        ];
        System.assertEquals(
            Blob.valueOf('%PDF-1.4 replaced sent copy').size(),
            savedPdf.ContentSize,
            'Existing PDF on Account should be replaced with the fresh DocuSign copy.'
        );
    }

    @IsTest
    static void testDocuSignSentPdfSaverJob_executesService() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion sourceCv = [
            SELECT Id
            FROM ContentVersion
            WHERE Title LIKE '%Contract.docx'
            LIMIT 1
        ];

        DocuSignSentPdfService.skipCalloutInTest = true;
        DocuSignSentPdfService.testPdfBlob = Blob.valueOf('%PDF-1.4 queueable pdf');

        Test.startTest();
        System.enqueueJob(new DocuSignSentPdfSaverJob(acc.Id, sourceCv.Id, 'TEST-ENVELOPE-789'));
        Test.stopTest();

        DocuSignSentPdfService.skipCalloutInTest = false;
        DocuSignSentPdfService.testPdfBlob = null;

        Integer savedCount = [
            SELECT COUNT()
            FROM ContentVersion
            WHERE Title = 'Customer-2026-2027 Bids-Customer 10290 A--Contract.pdf'
        ];
        System.assertEquals(1, savedCount, 'Queueable job should persist the sent PDF copy.');
    }
}
