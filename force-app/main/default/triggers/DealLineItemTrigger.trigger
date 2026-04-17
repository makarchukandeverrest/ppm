trigger DealLineItemTrigger on Deal_Line_Item__c (after insert, after update, after delete, after undelete) {
    TriggerHandler handler = new DealLineItemTriggerHandler();
    handler.run();
}