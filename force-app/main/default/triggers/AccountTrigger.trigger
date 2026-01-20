trigger AccountTrigger on Account (before insert) {
    TriggerHandler handler = new AccountTriggerHandler();
    handler.run();
}