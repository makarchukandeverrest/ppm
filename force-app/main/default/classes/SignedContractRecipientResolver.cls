public with sharing class SignedContractRecipientResolver {
    @TestVisible
    public static final String APPLIES_TO_CONTRACT_BID = 'Contract_Bid';
    @TestVisible
    public static final String APPLIES_TO_PROPOSAL = 'Proposal';
    private static final String APPLIES_TO_BOTH = 'Both';

    private final List<Signed_Contract_Recipient__mdt> activeRecipients;

    public SignedContractRecipientResolver() {
        this.activeRecipients = loadActiveRecipients();
    }

    public List<String> resolveToAddresses() {
        return resolveToAddresses(APPLIES_TO_CONTRACT_BID);
    }

    public List<String> resolveProposalToAddresses() {
        return resolveToAddresses(APPLIES_TO_PROPOSAL);
    }

    public List<String> resolveToAddresses(String appliesTo) {
        String target = String.isBlank(appliesTo) ? APPLIES_TO_CONTRACT_BID : appliesTo;
        Set<String> uniqueEmails = new Set<String>();
        for (Signed_Contract_Recipient__mdt recipient : activeRecipients) {
            if (!appliesToTarget(recipient, target) || String.isBlank(recipient.Email__c)) {
                continue;
            }
            uniqueEmails.add(recipient.Email__c.trim().toLowerCase());
        }
        return new List<String>(uniqueEmails);
    }

    private static Boolean appliesToTarget(Signed_Contract_Recipient__mdt recipient, String target) {
        if (String.isBlank(recipient.Applies_To__c) || recipient.Applies_To__c == APPLIES_TO_CONTRACT_BID) {
            return target == APPLIES_TO_CONTRACT_BID;
        }
        if (recipient.Applies_To__c == APPLIES_TO_PROPOSAL) {
            return target == APPLIES_TO_PROPOSAL;
        }
        return recipient.Applies_To__c == APPLIES_TO_BOTH;
    }

    private static List<Signed_Contract_Recipient__mdt> loadActiveRecipients() {
        List<Signed_Contract_Recipient__mdt> recipients = new List<Signed_Contract_Recipient__mdt>();
        for (Signed_Contract_Recipient__mdt recipient : Signed_Contract_Recipient__mdt.getAll().values()) {
            if (recipient.Is_Active__c == true) {
                recipients.add(recipient);
            }
        }
        return recipients;
    }
}
