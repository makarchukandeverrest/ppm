public with sharing class DocuSignCompletedContractEmailService {
    private static final String ORG_WIDE_FROM_ADDRESS = 'office@premierswim.com';

    private static Set<Id> processedContentVersionIds = new Set<Id>();

    @TestVisible
    private static List<String> lastRecipientEmails;

    public static void handleCompletedFiles(List<ContentVersion> versions) {
        if (versions == null || versions.isEmpty()) {
            return;
        }

        List<ContentVersion> candidateVersions = filterUnprocessed(versions);
        if (candidateVersions.isEmpty()) {
            return;
        }

        Map<Id, Id> contentDocumentToBidId = CompletedContractBidResolver.resolveBidIdsByContentDocument(
            candidateVersions
        );
        Map<Id, Id> contentDocumentToProposalId = CompletedContractBidResolver.resolveProposalIdsByContentDocument(
            candidateVersions
        );

        List<ContentVersion> contractVersions = new List<ContentVersion>();
        List<ContentVersion> proposalVersions = new List<ContentVersion>();

        for (ContentVersion version : candidateVersions) {
            if (CompletedContractBidResolver.resolveBidIdForVersion(version, contentDocumentToBidId) != null) {
                contractVersions.add(version);
            } else if (
                CompletedContractBidResolver.resolveProposalIdForVersion(version, contentDocumentToProposalId) != null
            ) {
                proposalVersions.add(version);
            }
        }

        Id orgWideEmailId = resolveOrgWideEmailId();
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        emailsToSend.addAll(buildContractEmails(contractVersions, contentDocumentToBidId, orgWideEmailId));
        emailsToSend.addAll(buildProposalEmails(proposalVersions, contentDocumentToProposalId, orgWideEmailId));

        if (emailsToSend.isEmpty()) {
            return;
        }

        sendEmails(emailsToSend);
    }

    private static List<Messaging.SingleEmailMessage> buildContractEmails(
        List<ContentVersion> versions,
        Map<Id, Id> contentDocumentToBidId,
        Id orgWideEmailId
    ) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        if (versions.isEmpty()) {
            return emails;
        }

        Set<Id> bidIds = CompletedContractBidResolver.collectBidIds(versions, contentDocumentToBidId);
        if (bidIds.isEmpty()) {
            return emails;
        }

        Map<Id, Contract_Bid__c> bidsById = queryBids(bidIds);
        List<String> toAddresses = new SignedContractRecipientResolver().resolveToAddresses();
        if (toAddresses.isEmpty()) {
            return emails;
        }

        for (ContentVersion version : versions) {
            Id bidId = CompletedContractBidResolver.resolveBidIdForVersion(version, contentDocumentToBidId);
            Contract_Bid__c bid = bidsById.get(bidId);
            if (bid == null) {
                continue;
            }

            trackRecipients(toAddresses);
            processedContentVersionIds.add(version.Id);
            emails.add(buildContractEmail(version, bid, toAddresses, orgWideEmailId));
        }
        return emails;
    }

    private static List<Messaging.SingleEmailMessage> buildProposalEmails(
        List<ContentVersion> versions,
        Map<Id, Id> contentDocumentToProposalId,
        Id orgWideEmailId
    ) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        if (versions.isEmpty()) {
            return emails;
        }

        Set<Id> proposalIds = CompletedContractBidResolver.collectProposalIds(versions, contentDocumentToProposalId);
        if (proposalIds.isEmpty()) {
            return emails;
        }

        Map<Id, Opportunity> proposalsById = queryProposals(proposalIds);
        List<String> toAddresses = new SignedContractRecipientResolver().resolveProposalToAddresses();
        if (toAddresses.isEmpty()) {
            return emails;
        }

        for (ContentVersion version : versions) {
            Id proposalId = CompletedContractBidResolver.resolveProposalIdForVersion(
                version,
                contentDocumentToProposalId
            );
            Opportunity proposal = proposalsById.get(proposalId);
            if (proposal == null) {
                continue;
            }

            trackRecipients(toAddresses);
            processedContentVersionIds.add(version.Id);
            emails.add(buildProposalEmail(version, proposal, toAddresses, orgWideEmailId));
        }
        return emails;
    }

    private static List<ContentVersion> filterUnprocessed(List<ContentVersion> versions) {
        List<ContentVersion> result = new List<ContentVersion>();
        for (ContentVersion version : versions) {
            if (version != null && version.Id != null && !processedContentVersionIds.contains(version.Id)) {
                result.add(version);
            }
        }
        return result;
    }

    private static Map<Id, Contract_Bid__c> queryBids(Set<Id> bidIds) {
        return new Map<Id, Contract_Bid__c>([
            SELECT
                Id,
                Name,
                Customer__r.Name
            FROM Contract_Bid__c
            WHERE Id IN :bidIds
        ]);
    }

    private static Map<Id, Opportunity> queryProposals(Set<Id> proposalIds) {
        return new Map<Id, Opportunity>([
            SELECT
                Id,
                Name,
                Account.Name
            FROM Opportunity
            WHERE Id IN :proposalIds
        ]);
    }

    private static void trackRecipients(List<String> toAddresses) {
        if (lastRecipientEmails == null) {
            lastRecipientEmails = new List<String>();
        }
        lastRecipientEmails.addAll(toAddresses);
    }

    private static Messaging.SingleEmailMessage buildContractEmail(
        ContentVersion version,
        Contract_Bid__c bid,
        List<String> toAddresses,
        Id orgWideEmailId
    ) {
        String customerName = bid.Customer__r != null ? bid.Customer__r.Name : '';
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(toAddresses);
        mail.setSubject(String.format(Label.Signed_Contract_Email_Subject, new List<String>{ bid.Name }));
        mail.setPlainTextBody(String.format(
            Label.Signed_Contract_Email_Body,
            new List<String>{ bid.Name, customerName, version.Title }
        ));
        mail.setEntityAttachments(new List<String>{ version.Id });
        mail.setSaveAsActivity(false);
        if (orgWideEmailId != null) {
            mail.setOrgWideEmailAddressId(orgWideEmailId);
        }
        return mail;
    }

    private static Messaging.SingleEmailMessage buildProposalEmail(
        ContentVersion version,
        Opportunity proposal,
        List<String> toAddresses,
        Id orgWideEmailId
    ) {
        String customerName = proposal.Account != null ? proposal.Account.Name : '';
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(toAddresses);
        mail.setSubject(String.format(Label.Signed_Proposal_Email_Subject, new List<String>{ proposal.Name }));
        mail.setPlainTextBody(String.format(
            Label.Signed_Proposal_Email_Body,
            new List<String>{ proposal.Name, customerName, version.Title }
        ));
        mail.setEntityAttachments(new List<String>{ version.Id });
        mail.setSaveAsActivity(false);
        if (orgWideEmailId != null) {
            mail.setOrgWideEmailAddressId(orgWideEmailId);
        }
        return mail;
    }

    private static void sendEmails(List<Messaging.SingleEmailMessage> emailsToSend) {
        try {
            Messaging.sendEmail(emailsToSend, false);
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'Failed to send signed document copy email: ' + ex.getMessage() + '\n' + ex.getStackTraceString()
            );
        }
    }

    private static Id resolveOrgWideEmailId() {
        List<OrgWideEmailAddress> orgWideEmails = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_FROM_ADDRESS AND IsVerified = true
            LIMIT 1
        ];
        return orgWideEmails.isEmpty() ? null : orgWideEmails[0].Id;
    }
}
