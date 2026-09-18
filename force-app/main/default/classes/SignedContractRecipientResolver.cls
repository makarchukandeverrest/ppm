public with sharing class SignedContractRecipientResolver {
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
