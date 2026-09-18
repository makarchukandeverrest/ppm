@IsTest
private class CompletedContractEmailServiceTest {
    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Signed Copy Account');
        insert acc;

        insert new Contract_Bid__c(
            Name = 'Signed Copy Bid',
            Customer__c = acc.Id
        );
    }

    @IsTest
    static void handleCompletedContractFiles_SendsEmailWithSignedPdf() {
        Contract_Bid__c bid = [SELECT Id FROM Contract_Bid__c WHERE Name = 'Signed Copy Bid' LIMIT 1];

        ContentVersion completedFile = new ContentVersion(
            Title = 'Premier Contract_completed',
            PathOnClient = 'Premier Contract_completed.pdf',
            VersionData = Blob.valueOf('signed pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = bid.Id
        );

        Test.startTest();
        insert completedFile;
        Integer emailsSent = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(1, emailsSent, 'Signed copy should send one email');
        System.assertNotEquals(null, DocuSignCompletedContractEmailService.lastRecipientEmails);
    }

    @IsTest
    static void handleCompletedContractFiles_IgnoresNonCompletedPdf() {
        Contract_Bid__c bid = [SELECT Id FROM Contract_Bid__c WHERE Name = 'Signed Copy Bid' LIMIT 1];

        ContentVersion proposal = new ContentVersion(
            Title = 'Premier Contract',
            PathOnClient = 'Premier Contract.pdf',
            VersionData = Blob.valueOf('unsigned pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = bid.Id
        );

        Test.startTest();
        insert proposal;
        Integer emailsSent = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(0, emailsSent, 'Unsigned files should not send an email');
    }

    @IsTest
    static void handleCompletedContractFiles_IgnoresCompletedPdfNotOnBid() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Signed Copy Account' LIMIT 1];

        ContentVersion completedFile = new ContentVersion(
            Title = 'Orphan_completed',
            PathOnClient = 'Orphan_completed.pdf',
            VersionData = Blob.valueOf('signed pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = acc.Id
        );

        Test.startTest();
        insert completedFile;
        Integer emailsSent = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(0, emailsSent, 'Completed PDFs not on a Contract Bid should not send');
    }

    @IsTest
    static void handleCompletedContractFiles_DoesNotSendTwiceForSameFile() {
        Contract_Bid__c bid = [SELECT Id FROM Contract_Bid__c WHERE Name = 'Signed Copy Bid' LIMIT 1];

        ContentVersion completedFile = new ContentVersion(
            Title = 'Idempotent_completed',
            PathOnClient = 'Idempotent_completed.pdf',
            VersionData = Blob.valueOf('signed pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = bid.Id
        );

        Test.startTest();
        insert completedFile;
        Integer afterInsert = Limits.getEmailInvocations();

        completedFile = [
            SELECT Id, Title, PathOnClient, FileExtension, ContentDocumentId, FirstPublishLocationId
            FROM ContentVersion
            WHERE Id = :completedFile.Id
        ];
        DocuSignCompletedContractEmailService.handleCompletedContractFiles(
            new List<ContentVersion>{ completedFile }
        );
        Integer afterSecondCall = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(1, afterInsert, 'Insert of the completed PDF should send the signed copy');
        System.assertEquals(
            afterInsert,
            afterSecondCall,
            'The same ContentVersion should not be emailed twice in one transaction'
        );
    }

    @IsTest
    static void completedContractBidResolver_MapsContentDocumentToBid() {
        Contract_Bid__c bid = [SELECT Id FROM Contract_Bid__c WHERE Name = 'Signed Copy Bid' LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title = 'Resolver_completed',
            PathOnClient = 'Resolver_completed.pdf',
            VersionData = Blob.valueOf('signed pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = bid.Id
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId, FirstPublishLocationId FROM ContentVersion WHERE Id = :cv.Id];

        Map<Id, Id> docToBid = CompletedContractBidResolver.resolveBidIdsByContentDocument(
            new List<ContentVersion>{ cv }
        );
        Set<Id> bidIds = CompletedContractBidResolver.collectBidIds(
            new List<ContentVersion>{ cv },
            docToBid
        );

        System.assert(bidIds.contains(bid.Id));
    }

    private static void assertContainsEmail(String expectedEmail) {
        Boolean found = false;
        for (String actualEmail : DocuSignCompletedContractEmailService.lastRecipientEmails) {
            if (actualEmail == expectedEmail.toLowerCase()) {
                found = true;
                break;
            }
        }
        System.assert(found, 'Expected recipient missing: ' + expectedEmail);
    }
}
