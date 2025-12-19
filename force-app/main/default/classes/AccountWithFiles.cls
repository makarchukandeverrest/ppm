public class AccountWithFiles {
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public String email;
    @AuraEnabled public Contract_Bid__c contract;
    @AuraEnabled public List<FileWrapper> files;
    @AuraEnabled public Boolean newClient;

    public AccountWithFiles(Id accountId, String accountName, String email, Contract_Bid__c contr, List<FileWrapper> files,Boolean newClient) {
        this.accountId = accountId;
        this.accountName = accountName;
        this.email = email;
        this.contract = contr;
        this.files = files;
        this.newClient = newClient;
    }
}