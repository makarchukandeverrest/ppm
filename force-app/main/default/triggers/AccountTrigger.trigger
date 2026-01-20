trigger AccountTrigger on Account (before insert, after update, after insert) {
    TriggerHandler handler = new AccountTriggerHandler();
    handler.run();
}