public with sharing class QuickBookWorkOrderLineItemTriggerHandler extends TriggerHandler{
    List<Quick_Book_Work_Order_Line_Item__c> newList;
    Map<Id,Quick_Book_Work_Order_Line_Item__c> oldMap;

    public QuickBookWorkOrderLineItemTriggerHandler(){
        this.newList = (List<Quick_Book_Work_Order_Line_Item__c>)Trigger.new;
        this.oldMap = (Map<Id,Quick_Book_Work_Order_Line_Item__c>)Trigger.oldMap;
    }

    protected override void afterInsert() {
        QuickBookWorkOrderTechnicianHandler.handleQuickBookWorkOrderTechnician(newList);
    }

    protected override void afterUpdate() {
        List<Quick_Book_Work_Order_Line_Item__c> stmChanged = new List<Quick_Book_Work_Order_Line_Item__c>();
        for (Quick_Book_Work_Order_Line_Item__c row : newList) {
            Quick_Book_Work_Order_Line_Item__c oldRow = oldMap.get(row.Id);
            if (oldRow != null && row.Service_Team_Member__c != oldRow.Service_Team_Member__c) {
                stmChanged.add(row);
            }
        }
        if (!stmChanged.isEmpty()) {
            QuickBookWorkOrderTechnicianHandler.handleQuickBookWorkOrderTechnician(stmChanged);
        }
    }
}
