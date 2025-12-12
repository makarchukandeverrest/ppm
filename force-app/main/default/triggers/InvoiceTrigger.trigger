trigger InvoiceTrigger on Invoice__c (before insert, after insert, before update) {
    TriggerHandler handler = new InvoiceTriggerHandler();
    handler.run();
}