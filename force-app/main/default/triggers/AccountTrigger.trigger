trigger AccountTrigger on Account (before insert, before update, after update) {
    TriggerHandler handler = new AccountTriggerHandler();
    handler.run();
}