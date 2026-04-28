trigger QuickBookWorkOrderLineItemTrigger on Quick_Book_Work_Order_Line_Item__c (before insert, after insert, after update) {
    TriggerHandler handler = new QuickBookWorkOrderLineItemTriggerHandler();
    handler.run();
}
