trigger EventTrigger on Event (after insert, after update, after delete, after undelete) {
    TriggerHandler handler = new EventTriggerHandler();
    handler.run();
}
