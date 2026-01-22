trigger EmailThreadTrigger on Email_Platform__Email_Thread__c (after insert) {
    TriggerHandler handler = new EmailThreadTriggerHandler();
    handler.run();
}