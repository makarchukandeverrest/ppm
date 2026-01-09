public with sharing class AccountTriggerHandler extends TriggerHandler{
    List<Account> newList;

    public AccountTriggerHandler(){
		this.newList = (List<Account>)Trigger.new;
	}

    protected override void beforeInsert(){
        QuickBooksAccountChecker.filterAccounts(newList);
	}

}