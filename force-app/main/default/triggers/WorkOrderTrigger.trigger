trigger WorkOrderTrigger on WorkOrder (after insert, before insert) {
    TriggerHandler handler = new WorkOrderTriggerHandler();
    handler.run();
}