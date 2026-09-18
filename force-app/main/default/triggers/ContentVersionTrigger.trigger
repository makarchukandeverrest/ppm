trigger ContentVersionTrigger on ContentVersion (after insert, after update) {
    TriggerHandler handler = new ContentVersionTriggerHandler();
    handler.run();
}