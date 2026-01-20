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
}