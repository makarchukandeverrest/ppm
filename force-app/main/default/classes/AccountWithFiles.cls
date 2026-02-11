public class AccountWithFiles {
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String email;
    @AuraEnabled public Contract_Bid__c contract;
    @AuraEnabled public List<FileWrapper> files;
    @AuraEnabled public Boolean newClient;
    
    // Filter-related fields for display
    @AuraEnabled public String regionalManagerName;
    @AuraEnabled public String countyName;
    @AuraEnabled public String supervisorName;

    // Reminder and expiration – FINAL values only (number of days)
    @AuraEnabled public String reminderValue;   // final: "1"-"7" or custom number
    @AuraEnabled public String daysBeforeExpires;

    public AccountWithFiles(Id accountId, String accountName, String email, Contract_Bid__c contr, List<FileWrapper> files, Boolean newClient) {
        this(accountId, accountName, email, contr, files, newClient, null, null);
    }

    public AccountWithFiles(Id accountId, String accountName, String email, Contract_Bid__c contr, List<FileWrapper> files, Boolean newClient,
            String reminderValue, String daysBeforeExpires) {
        this.accountId = accountId;
        this.accountName = accountName;
        this.email = email;
        this.contract = contr;
        this.files = files;
        this.newClient = newClient;
        this.reminderValue = reminderValue;
        this.daysBeforeExpires = daysBeforeExpires;
    }
}