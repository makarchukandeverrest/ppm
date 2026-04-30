public without sharing class ProposalTriggerHandler extends TriggerHandler {
    List<Opportunity> newList;
    Map<Id, Opportunity> oldMap;

    public ProposalTriggerHandler() {
        this.newList = (List<Opportunity>) Trigger.new;
        this.oldMap  = (Map<Id, Opportunity>) Trigger.oldMap;
    }

    protected override void beforeInsert() {
        //ProposalStatusDefiner.updateStatus(this.newList);
        ProposalCustomerAssigner.assignCustomer(this.newList);
        CustomerRegionalManagerService.syncProposalRMFromCustomer(this.newList);
    }

    protected override void beforeUpdate() {
        List<Opportunity> oppsNeedingCustomerAssignment = new List<Opportunity>();

        for (Opportunity opp : newList) {
            if (String.isNotBlank(opp.Account_QuickBooks_Id__c) &&
                (
                    opp.AccountId == null ||
                    opp.Customer_Billing_Contact__c == null ||
                    opp.Customer_Maintenance_Contact__c == null ||
                    opp.Customer_Primary_Contact__c == null ||
                    opp.Customer_Secondary_Contact__c == null
                )) {

                oppsNeedingCustomerAssignment.add(opp);
            }
        }

        if (!oppsNeedingCustomerAssignment.isEmpty()) {
            ProposalCustomerAssigner.assignCustomer(oppsNeedingCustomerAssignment);
            CustomerRegionalManagerService.syncProposalRMFromCustomer(oppsNeedingCustomerAssignment);
        }

        List<Opportunity> oppsWithChangedAccount = new List<Opportunity>();
        for (Opportunity opp : newList) {
            if (opp.AccountId != oldMap.get(opp.Id).AccountId) {
                oppsWithChangedAccount.add(opp);
            }
        }

        if (!oppsWithChangedAccount.isEmpty()) {
            OpportunityContactSyncService.assignContacts(oppsWithChangedAccount);
            CustomerRegionalManagerService.syncProposalRMFromCustomer(oppsWithChangedAccount);
        }
        CustomerRegionalManagerService.preventProposalRMOverride(this.newList, this.oldMap);
        ProposalStatusDefiner.handleStatusChange(this.newList, this.oldMap);
    }
}