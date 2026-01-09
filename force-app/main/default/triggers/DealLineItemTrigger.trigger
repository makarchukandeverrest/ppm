trigger DealLineItemTrigger on Deal_Line_Item__c (after insert, after update, after delete, after undelete) {
    Set<Id> dealIds = new Set<Id>();

    if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
        for (Deal_Line_Item__c dli : Trigger.new) {
            if (dli.Deal__c != null) {
                dealIds.add(dli.Deal__c);
            }
        }
    }

    if (Trigger.isDelete) {
        for (Deal_Line_Item__c dli : Trigger.old) {
            if (dli.Deal__c != null) {
                dealIds.add(dli.Deal__c);
            }
        }
    }

    if (!dealIds.isEmpty()) {
        DealLineItemJSONBuilder.updateDealsWithJSON(dealIds);
    }
}