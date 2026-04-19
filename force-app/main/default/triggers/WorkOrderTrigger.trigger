trigger WorkOrderTrigger on WorkOrder (after insert, before insert, after update) {
    TriggerHandler handler = new WorkOrderTriggerHandler();
    handler.run();
}