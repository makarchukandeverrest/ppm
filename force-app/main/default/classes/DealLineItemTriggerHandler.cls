public without sharing class DealLineItemTriggerHandler extends TriggerHandler {
    private List<Deal_Line_Item__c> newList;
    private List<Deal_Line_Item__c> oldList;

    public DealLineItemTriggerHandler() {
        this.newList = (List<Deal_Line_Item__c>) Trigger.new;
        this.oldList = (List<Deal_Line_Item__c>) Trigger.old;
    }

    protected override void afterInsert() {
        handleAfterChange(this.newList);
    }

    protected override void afterUpdate() {
        handleAfterChange(this.newList);
    }

    protected override void afterUndelete() {
        handleAfterChange(this.newList);
    }

    protected override void afterDelete() {
        handleAfterChange(this.oldList);
    }

    private static void handleAfterChange(List<Deal_Line_Item__c> records) {
        if (records == null || records.isEmpty()) {
            return;
        }

        Set<Id> dealIds = new Set<Id>();
        Set<String> dealQuickBooksIds = new Set<String>();

        for (Deal_Line_Item__c dli : records) {
            if (dli.Deal__c != null) {
                dealIds.add(dli.Deal__c);
            }
            if (dli.Deal__c == null && String.isNotBlank(dli.Deal_QuickBooks_Id__c)) {
                dealQuickBooksIds.add(dli.Deal_QuickBooks_Id__c.trim());
            }
        }

        if (!dealIds.isEmpty() || !dealQuickBooksIds.isEmpty()) {
            DealLineItemJSONBuilder.updateDealsWithJSON(dealIds, dealQuickBooksIds);
        }
    }
}