@IsTest
private class CompletedContractBidResolverTest {
    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Resolver Account');
        insert acc;
        insert new Contract_Bid__c(Name = 'Resolver Bid', Customer__c = acc.Id);
    }

    @IsTest
    static void resolveBidIdsByContentDocument_PreferFirstPublishLocation() {
        Contract_Bid__c bid = [SELECT Id FROM Contract_Bid__c WHERE Name = 'Resolver Bid' LIMIT 1];
        ContentVersion cv = new ContentVersion(
            Title = 'Publish_completed',
            PathOnClient = 'Publish_completed.pdf',
            VersionData = Blob.valueOf('pdf'),
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

        System.assert(docToBid.isEmpty(), 'No link lookup needed when FirstPublishLocationId is a Bid');
        System.assert(bidIds.contains(bid.Id));
    }

    @IsTest
    static void resolveBidIdsByContentDocument_FallsBackToContentDocumentLink() {
        Contract_Bid__c bid = [SELECT Id FROM Contract_Bid__c WHERE Name = 'Resolver Bid' LIMIT 1];
        Account acc = [SELECT Id FROM Account WHERE Name = 'Resolver Account' LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title = 'Link_completed',
            PathOnClient = 'Link_completed.pdf',
            VersionData = Blob.valueOf('pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = acc.Id
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId, FirstPublishLocationId FROM ContentVersion WHERE Id = :cv.Id];

        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = bid.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Map<Id, Id> docToBid = CompletedContractBidResolver.resolveBidIdsByContentDocument(
            new List<ContentVersion>{ cv }
        );
        Set<Id> bidIds = CompletedContractBidResolver.collectBidIds(
            new List<ContentVersion>{ cv },
            docToBid
        );

        System.assertEquals(bid.Id, docToBid.get(cv.ContentDocumentId));
        System.assert(bidIds.contains(bid.Id));
    }

    @IsTest
    static void collectBidIds_SkipsNonBidLocations() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Resolver Account' LIMIT 1];
        ContentVersion cv = new ContentVersion(
            Title = 'Account_completed',
            PathOnClient = 'Account_completed.pdf',
            VersionData = Blob.valueOf('pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = acc.Id
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

        System.assert(bidIds.isEmpty());
    }

    @IsTest
    static void resolveProposalIdsByContentDocument_PreferFirstPublishLocation() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Resolver Account' LIMIT 1];
        Opportunity proposal = new Opportunity(
            Name = 'Resolver Proposal',
            AccountId = acc.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft'
        );
        insert proposal;

        ContentVersion cv = new ContentVersion(
            Title = 'Proposal_Publish_completed',
            PathOnClient = 'Proposal_Publish_completed.pdf',
            VersionData = Blob.valueOf('pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = proposal.Id
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId, FirstPublishLocationId FROM ContentVersion WHERE Id = :cv.Id];

        Map<Id, Id> docToProposal = CompletedContractBidResolver.resolveProposalIdsByContentDocument(
            new List<ContentVersion>{ cv }
        );
        Set<Id> proposalIds = CompletedContractBidResolver.collectProposalIds(
            new List<ContentVersion>{ cv },
            docToProposal
        );

        System.assert(docToProposal.isEmpty(), 'No link lookup needed when FirstPublishLocationId is a Proposal');
        System.assert(proposalIds.contains(proposal.Id));
    }

    @IsTest
    static void resolveProposalIdsByContentDocument_FallsBackToContentDocumentLink() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Resolver Account' LIMIT 1];
        Opportunity proposal = new Opportunity(
            Name = 'Resolver Proposal Link',
            AccountId = acc.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft'
        );
        insert proposal;

        ContentVersion cv = new ContentVersion(
            Title = 'Proposal_Link_completed',
            PathOnClient = 'Proposal_Link_completed.pdf',
            VersionData = Blob.valueOf('pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = acc.Id
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId, FirstPublishLocationId FROM ContentVersion WHERE Id = :cv.Id];

        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = proposal.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Map<Id, Id> docToProposal = CompletedContractBidResolver.resolveProposalIdsByContentDocument(
            new List<ContentVersion>{ cv }
        );
        Set<Id> proposalIds = CompletedContractBidResolver.collectProposalIds(
            new List<ContentVersion>{ cv },
            docToProposal
        );

        System.assertEquals(proposal.Id, docToProposal.get(cv.ContentDocumentId));
        System.assert(proposalIds.contains(proposal.Id));
    }

    @IsTest
    static void collectProposalIds_SkipsNonProposalLocations() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Resolver Account' LIMIT 1];
        ContentVersion cv = new ContentVersion(
            Title = 'Account_Proposal_completed',
            PathOnClient = 'Account_Proposal_completed.pdf',
            VersionData = Blob.valueOf('pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = acc.Id
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId, FirstPublishLocationId FROM ContentVersion WHERE Id = :cv.Id];

        Map<Id, Id> docToProposal = CompletedContractBidResolver.resolveProposalIdsByContentDocument(
            new List<ContentVersion>{ cv }
        );
        Set<Id> proposalIds = CompletedContractBidResolver.collectProposalIds(
            new List<ContentVersion>{ cv },
            docToProposal
        );

        System.assert(proposalIds.isEmpty());
    }
}
