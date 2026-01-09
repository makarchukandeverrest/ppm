trigger ContentVersionTrigger on ContentVersion (after update) {
    TriggerHandler handler = new ContentVersionTriggerHandler();
    handler.run();
}