trigger EmailMessageTrigger on EmailMessage(after insert, after update, after delete, after undelete) {
    TriggerHandler handler = new EmailMessageTriggerHandler();
    handler.run();
}