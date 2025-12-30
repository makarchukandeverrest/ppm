public with sharing class WorkOrderLineItemCreator {
    public static void createWorkOrderLineItems(List<WorkOrder> newWorkOrders) {
        Map<Id, List<QuickBooksWOLineIntem>> woLineItemsMap = new Map<Id, List<QuickBooksWOLineIntem>>();

        for (WorkOrder wo : newWorkOrders) {
            if (String.isNotBlank(wo.Quick_Books_Line_Items__c)) {
                woLineItemsMap.put(wo.Id, QuickBooksWOLineIntem.fromJson(wo.Quick_Books_Line_Items__c));
            }
        }
        List<Quick_Book_Work_Order_Line_Item__c> woLineItemsToInsert = new List<Quick_Book_Work_Order_Line_Item__c>();
        for(Id woId :woLineItemsMap.keySet()){
            for(QuickBooksWOLineIntem item : woLineItemsMap.get(woId)){
                if(String.isNotBlank(item.Description)){
                    Quick_Book_Work_Order_Line_Item__c woLineItem = new Quick_Book_Work_Order_Line_Item__c();
                    woLineItem.Name = item.ItemName;
                    woLineItem.Work_Order__c = woId;
                    woLineItem.Description__c = item.Description;
                    woLineItem.Quantity__c = item.Quantity;
                    woLineItem.Rate__c = item.Rate;
                    woLineItem.Amount__c = item.Amount;
                    woLineItem.Quick_Books_Id__c = item.Id;
                    woLineItemsToInsert.add(woLineItem);
                }
            }
        }
        insert woLineItemsToInsert;
    }
}