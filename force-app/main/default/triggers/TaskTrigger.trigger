trigger TaskTrigger on Task (before insert, after insert, after update) {
    TriggerHandler handler = new TaskTriggerHandler();
    handler.run();
}
