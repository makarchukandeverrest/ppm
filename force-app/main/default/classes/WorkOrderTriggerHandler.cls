public with sharing class WorkOrderTriggerHandler extends TriggerHandler{
    List<WorkOrder> newList;
    Map<Id, WorkOrder> oldMap;

    public WorkOrderTriggerHandler(){
		this.newList = (List<WorkOrder>)Trigger.new;
        this.oldMap = (Map<Id, WorkOrder>)Trigger.oldMap;
	}

    protected override void afterInsert(){
        WorkOrderLineItemCreator.createWorkOrderLineItems(this.newList);
        ProposalStatusDefiner.updateStatus(this.newList);
	}

    protected override void afterUpdate(){
        WorkOrderLineItemCreator.syncWorkOrderLineItems(this.newList, this.oldMap);
    }

    protected override void beforeInsert(){
        WorkOrderCustomerAssigner linker = new WorkOrderCustomerAssigner(this.newList);
        CustomerRegionalManagerService.assignOwnerByCustomer(this.newList);
    }
}