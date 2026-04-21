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
        CustomerRegionalManagerService.assignOwnerByCustomer(this.newList);
	}

    protected override void beforeInsert(){
        WorkOrderCustomerAssigner linker = new WorkOrderCustomerAssigner(this.newList);
    }

    protected override void afterUpdate(){
        WorkOrderLineItemCreator.syncWorkOrderLineItems(this.newList, this.oldMap);
    }

    protected override void beforeUpdate(){
        List<WorkOrder> workOrdersNeedingLookupAssignment = new List<WorkOrder>();

        for (WorkOrder w : this.newList) {
            Boolean needsAccount =
                w.AccountId == null &&
                String.isNotBlank(w.Quickbooks_Customer_Id__c);

            Boolean needsProposal =
                w.Proposal__c == null &&
                String.isNotBlank(w.Quickbooks_Memo__c);

            if (needsAccount || needsProposal) {
                workOrdersNeedingLookupAssignment.add(w);
            }
        }

        if (!workOrdersNeedingLookupAssignment.isEmpty()) {
            WorkOrderCustomerAssigner linker = new WorkOrderCustomerAssigner(workOrdersNeedingLookupAssignment);
        }
    }
}