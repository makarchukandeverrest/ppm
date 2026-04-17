trigger AccountTrigger on Account (before insert, after update) {
    TriggerHandler handler = new AccountTriggerHandler();
    handler.run();
}