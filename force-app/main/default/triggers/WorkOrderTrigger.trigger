trigger WorkOrderTrigger on WorkOrder (after insert, before insert, before update) {
    TriggerHandler handler = new WorkOrderTriggerHandler();
    handler.run();
}