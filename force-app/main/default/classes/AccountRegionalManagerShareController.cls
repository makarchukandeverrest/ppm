public with sharing class AccountRegionalManagerShareController {
    public static void setSharing(List<Account> accounts) {
        List<AccountShare> accountShares = new List<AccountShare>();
        for(Account account : accounts) {
            AccountShare accountShare = new AccountShare();
            accountShare.AccountId = account.Id;
            accountShare.UserOrGroupId = account.Regional_Manager__c;
            accountShare.AccountAccessLevel = 'Edit';
            accountShare.OpportunityAccessLevel = 'Edit';
            accountShare.CaseAccessLevel = 'Edit';
            accountShares.add(accountShare);
        }
        insert accountShares;
    }

    public static void removeSharing(List<Account> accounts) {
        List<AccountShare> accountShares = [SELECT Id FROM AccountShare WHERE AccountId IN :accounts AND RowCause = 'Manual'];

        if (!accountShares.isEmpty()) {
            delete accountShares;
        }
    }
}