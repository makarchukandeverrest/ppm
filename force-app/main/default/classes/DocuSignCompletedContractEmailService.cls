public with sharing class DocuSignCompletedContractEmailService {
    private static final String ORG_WIDE_FROM_ADDRESS = 'office@premierswim.com';

    private static Set<Id> processedContentVersionIds = new Set<Id>();

    @TestVisible
    private static List<String> lastRecipientEmails;

    public static void handleCompletedContractFiles(List<ContentVersion> versions) {
        if (versions == null || versions.isEmpty()) {
            return;
        }

        List<ContentVersion> candidateVersions = filterUnprocessed(versions);
        if (candidateVersions.isEmpty()) {
            return;
        }

        Map<Id, Id> contentDocumentToBidId = CompletedContractBidResolver.resolveBidIdsByContentDocument(candidateVersions);
        Set<Id> bidIds = CompletedContractBidResolver.collectBidIds(candidateVersions, contentDocumentToBidId);
        if (bidIds.isEmpty()) {
            return;
        }

        Map<Id, Contract_Bid__c> bidsById = queryBids(bidIds);
        List<String> toAddresses = new SignedContractRecipientResolver().resolveToAddresses();
        if (toAddresses.isEmpty()) {
            return;
        }

        Id orgWideEmailId = resolveOrgWideEmailId();
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        for (ContentVersion version : candidateVersions) {
            Id bidId = CompletedContractBidResolver.resolveBidIdForVersion(version, contentDocumentToBidId);
            Contract_Bid__c bid = bidsById.get(bidId);
            if (bid == null) {
                continue;
            }

            trackRecipients(toAddresses);
            processedContentVersionIds.add(version.Id);
            emailsToSend.add(buildEmail(version, bid, toAddresses, orgWideEmailId));
        }

        if (emailsToSend.isEmpty()) {
            return;
        }

        sendEmails(emailsToSend);
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

    private static void trackRecipients(List<String> toAddresses) {
        if (lastRecipientEmails == null) {
            lastRecipientEmails = new List<String>();
        }
        lastRecipientEmails.addAll(toAddresses);
    }

    private static Messaging.SingleEmailMessage buildEmail(
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

    private static void sendEmails(List<Messaging.SingleEmailMessage> emailsToSend) {
        try {
            Messaging.sendEmail(emailsToSend, false);
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'Failed to send signed contract copy email: ' + ex.getMessage() + '\n' + ex.getStackTraceString()
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
