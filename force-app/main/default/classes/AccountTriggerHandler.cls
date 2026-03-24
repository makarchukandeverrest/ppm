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
        List<Account> accountsWithChangedRegionalManager = new List<Account>();
        List<Account> accountsWithChangedContacts = new List<Account>();

        for (Account acc : newList) {
            Account oldAcc = oldMap.get(acc.Id);
            if (oldAcc == null) {
                continue;
            }

            if (acc.Regional_Manager__c != oldAcc.Regional_Manager__c) {
                accountsWithChangedRegionalManager.add(acc);
            }

            if (
                acc.Billing_Contact__c != oldAcc.Billing_Contact__c ||
                acc.Maintenance_Contact__c != oldAcc.Maintenance_Contact__c ||
                acc.Primary_Contact__c != oldAcc.Primary_Contact__c ||
                acc.Secondary_Contact__c != oldAcc.Secondary_Contact__c
            ) {
                accountsWithChangedContacts.add(acc);
            }
        }
        System.debug('accountsWithChangedRegionalManager '+accountsWithChangedRegionalManager);
        if(!accountsWithChangedRegionalManager.isEmpty()) {
            CustomerRegionalManagerService.assignOwnerByCustomer(accountsWithChangedRegionalManager);
        }

        if(!accountsWithChangedContacts.isEmpty()) {
            OpportunityContactSyncService.assignContacts(accountsWithChangedContacts);
        }
    }
}