trigger EmailMessageTrigger on EmailMessage(after update, after insert) {
    TriggerHandler handler = new EmailMessageTriggerHandler();
    handler.run();
}