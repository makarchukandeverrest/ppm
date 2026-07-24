trigger TaskTrigger on Task (after insert, after update) {
    TriggerHandler handler = new TaskTriggerHandler();
    handler.run();
}
