public with sharing class ProposalTriggerHandler extends TriggerHandler{
    List<Opportunity> newList;
    Map<Id,Opportunity> oldMap;

    public ProposalTriggerHandler(){
		this.newList = (List<Opportunity>)Trigger.new;
        this.oldMap = (Map<Id,Opportunity>)Trigger.oldMap;
	}

    protected override void beforeInsert(){
        ProposalStatusDefiner.updateStatus(this.newList);
        ProposalCustomerAssigner.assignCustomer(this.newList);
	}

    protected override void beforeUpdate(){
        ProposalStatusDefiner.handleStatusChange(newList, oldMap);
    }
}