public with sharing class WorkOrderTriggerHandler extends TriggerHandler{
    List<WorkOrder> newList;

    public WorkOrderTriggerHandler(){
		this.newList = (List<WorkOrder>)Trigger.new;
	}

    protected override void afterInsert(){
        WorkOrderLineItemCreator.createWorkOrderLineItems(this.newList);
        ProposalStatusDefiner.updateStatus(this.newList);
	}

    protected override void beforeInsert(){
        WorkOrderCustomerAssigner linker = new WorkOrderCustomerAssigner(this.newList);
    }
}