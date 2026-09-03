public with sharing class SignedContractRecipientResolver {
    @TestVisible
    private static final List<String> PROPOSAL_RECIPIENT_DEVELOPER_NAMES = new List<String>{
        'Accounting',
        'Adrian'
    };

    private final List<Signed_Contract_Recipient__mdt> activeRecipients;

    public SignedContractRecipientResolver() {
        this.activeRecipients = loadActiveRecipients();
    }

    public List<String> resolveToAddresses() {
        Set<String> uniqueEmails = new Set<String>();
        for (Signed_Contract_Recipient__mdt recipient : activeRecipients) {
            if (String.isBlank(recipient.Email__c)) {
                continue;
            }
            uniqueEmails.add(recipient.Email__c.trim().toLowerCase());
        }
        return new List<String>(uniqueEmails);
    }

    public List<String> resolveProposalToAddresses() {
        Set<String> uniqueEmails = new Set<String>();
        for (String developerName : PROPOSAL_RECIPIENT_DEVELOPER_NAMES) {
            Signed_Contract_Recipient__mdt recipient = Signed_Contract_Recipient__mdt.getInstance(developerName);
            if (recipient == null || String.isBlank(recipient.Email__c)) {
                continue;
            }
            uniqueEmails.add(recipient.Email__c.trim().toLowerCase());
        }
        return new List<String>(uniqueEmails);
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
