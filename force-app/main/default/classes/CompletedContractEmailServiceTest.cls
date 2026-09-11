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
        DocuSignCompletedContractEmailService.handleCompletedFiles(
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

    @IsTest
    static void handleCompletedProposalFiles_SendsEmailToProposalRecipients() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Signed Copy Account' LIMIT 1];
        Opportunity proposal = new Opportunity(
            Name = 'Signed Copy Proposal',
            AccountId = acc.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft'
        );
        insert proposal;

        ContentVersion completedFile = new ContentVersion(
            Title = 'Premier Proposal_completed',
            PathOnClient = 'Premier Proposal_completed.pdf',
            VersionData = Blob.valueOf('signed pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = proposal.Id
        );

        Test.startTest();
        insert completedFile;
        Integer emailsSent = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(1, emailsSent, 'Signed proposal copy should send one email');
        System.assertNotEquals(null, DocuSignCompletedContractEmailService.lastRecipientEmails);

        List<String> expectedProposalEmails = new SignedContractRecipientResolver().resolveProposalToAddresses();
        System.assert(
            !expectedProposalEmails.isEmpty(),
            'Proposal recipient metadata should resolve to at least one email'
        );
        for (String expectedEmail : expectedProposalEmails) {
            assertContainsEmail(expectedEmail);
        }
        System.assertEquals(
            new Set<String>(expectedProposalEmails),
            new Set<String>(DocuSignCompletedContractEmailService.lastRecipientEmails),
            'Proposal signed copy should go only to Proposal Applies To recipients'
        );
    }

    @IsTest
    static void handleCompletedProposalFiles_IgnoresNonCompletedPdf() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Signed Copy Account' LIMIT 1];
        Opportunity proposal = new Opportunity(
            Name = 'Unsigned Proposal',
            AccountId = acc.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft'
        );
        insert proposal;

        ContentVersion unsignedFile = new ContentVersion(
            Title = 'Premier Proposal',
            PathOnClient = 'Premier Proposal.pdf',
            VersionData = Blob.valueOf('unsigned pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = proposal.Id
        );

        Test.startTest();
        insert unsignedFile;
        Integer emailsSent = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(0, emailsSent, 'Unsigned proposal files should not send an email');
    }

    @IsTest
    static void docuSignCompletedEmailJob_SendsForContentVersionIds() {
        Contract_Bid__c bid = [SELECT Id FROM Contract_Bid__c WHERE Name = 'Signed Copy Bid' LIMIT 1];

        ContentVersion completedFile = new ContentVersion(
            Title = 'Job_completed',
            PathOnClient = 'Job_completed.pdf',
            VersionData = Blob.valueOf('signed pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = bid.Id
        );
        insert completedFile;

        Test.startTest();
        new DocuSignCompletedEmailJob(new List<Id>{ completedFile.Id }).execute(null);
        Test.stopTest();

        System.assertEquals(1, Limits.getEmailInvocations(), 'Queueable job should send the signed copy');
    }

    @IsTest
    static void signedContractRecipientResolver_SplitsContractAndProposalLists() {
        SignedContractRecipientResolver resolver = new SignedContractRecipientResolver();
        List<String> contractEmails = resolver.resolveToAddresses();
        List<String> proposalEmails = resolver.resolveProposalToAddresses();

        System.assert(
            contractEmails.contains('office@premierswim.com'),
            'Office should remain on Contract Bid emails'
        );
        System.assert(
            proposalEmails.contains('office@premierswim.com'),
            'Office should be on Proposal emails'
        );
        System.assert(
            proposalEmails.contains('angelly@premierswim.com'),
            'Angelley should receive Proposal emails'
        );
        System.assert(
            !contractEmails.contains('angelly@premierswim.com'),
            'Angelley should not receive Contract Bid emails'
        );
        System.assert(
            !proposalEmails.contains('jessica@premierswim.com'),
            'Jessica should not receive Proposal emails'
        );
        System.assert(
            !proposalEmails.contains('accounting@premierswim.com'),
            'Accounting should not receive Proposal emails'
        );
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
