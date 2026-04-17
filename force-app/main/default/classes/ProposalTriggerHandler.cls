public without sharing class ProposalTriggerHandler extends TriggerHandler{
    List<Opportunity> newList;
    Map<Id,Opportunity> oldMap;

    public ProposalTriggerHandler(){
		this.newList = (List<Opportunity>)Trigger.new;
        this.oldMap = (Map<Id,Opportunity>)Trigger.oldMap;
	}

    protected override void beforeInsert(){
        ProposalStatusDefiner.updateStatus(this.newList);
        ProposalCustomerAssigner.assignCustomer(this.newList);
        ProposalRegionalManagerAssigner.assignManagers(this.newList);
	}

    protected override void beforeUpdate(){
        List<Opportunity> oppsWithChangedAccount = new List<Opportunity>();
        for(Opportunity opp : newList){
            if(opp.AccountId != oldMap.get(opp.Id).AccountId){
                oppsWithChangedAccount.add(opp);
            }
        }
        if(!oppsWithChangedAccount.isEmpty()){
            OpportunityContactSyncService.assignContacts(oppsWithChangedAccount);
        }

        ProposalStatusDefiner.handleStatusChange(newList, oldMap);
    }
}