trigger TaskTrigger on Task (before insert, after insert, after update, after delete, after undelete) {
    TriggerHandler handler = new TaskTriggerHandler();
    handler.run();
}
