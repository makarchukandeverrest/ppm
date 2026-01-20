public with sharing class AccountTriggerHandler extends TriggerHandler{
    List<Account> newList;
    Map<Id,Account> oldMap;

    public AccountTriggerHandler(){
		this.newList = (List<Account>)Trigger.new;
        this.oldMap = (Map<Id,Account>)Trigger.oldMap;
	}

    protected override void beforeInsert(){
        QuickBooksAccountChecker.filterAccounts(newList);
	}

    protected override void afterUpdate(){
        List<Account> accountsToShare = new List<Account>();
        for(Account account : newList){
            Account oldAccount = oldMap.get(account.Id);
            if(account.Regional_Manager__c != oldAccount.Regional_Manager__c){
                accountsToShare.add(account);
            }
        }
        if(!accountsToShare.isEmpty()){
            AccountRegionalManagerShareController.setSharing(accountsToShare);
        }
    }

    protected override void afterInsert(){
        List<Account> accountsToShare = new List<Account>();
        for(Account account : newList){
            if(account.Regional_Manager__c != null){
                accountsToShare.add(account);
            }
        }
        if(!accountsToShare.isEmpty()){
            AccountRegionalManagerShareController.setSharing(accountsToShare);
        }
    }
}