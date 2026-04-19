public with sharing class WorkOrderLineItemCreator {
    /**
     * When Quick_Books_Line_Items__c changes: upsert rows by Quick_Books_Id__c, insert any lines
     * without an Id, delete rows no longer present (or all children if JSON was cleared).
     */
    public static void syncWorkOrderLineItems(List<WorkOrder> newWorkOrders, Map<Id, WorkOrder> oldMap) {
        if (oldMap == null || oldMap.isEmpty()) {
            return;
        }
        List<WorkOrder> lineItemsChanged = new List<WorkOrder>();
        for (WorkOrder wo : newWorkOrders) {
            WorkOrder oldWo = oldMap.get(wo.Id);
            if (oldWo != null && wo.Quick_Books_Line_Items__c != oldWo.Quick_Books_Line_Items__c) {
                lineItemsChanged.add(wo);
            }
        }
        if (lineItemsChanged.isEmpty()) {
            return;
        }

        Set<Id> woWithClearedJson = new Set<Id>();
        List<WorkOrder> woWithJson = new List<WorkOrder>();
        for (WorkOrder wo : lineItemsChanged) {
            if (String.isBlank(wo.Quick_Books_Line_Items__c)) {
                woWithClearedJson.add(wo.Id);
            } else {
                woWithJson.add(wo);
            }
        }

        if (!woWithClearedJson.isEmpty()) {
            delete [
                SELECT Id
                FROM Quick_Book_Work_Order_Line_Item__c
                WHERE Work_Order__c IN :woWithClearedJson
            ];
        }

        if (woWithJson.isEmpty()) {
            return;
        }

        Set<Id> woWithJsonIds = new Set<Id>();
        Map<Id, Set<String>> qbIdsByWo = new Map<Id, Set<String>>();
        List<Quick_Book_Work_Order_Line_Item__c> toUpsert = new List<Quick_Book_Work_Order_Line_Item__c>();
        List<Quick_Book_Work_Order_Line_Item__c> toInsertNoExtId = new List<Quick_Book_Work_Order_Line_Item__c>();

        for (WorkOrder wo : woWithJson) {
            woWithJsonIds.add(wo.Id);
            Set<String> qbIds = new Set<String>();
            qbIdsByWo.put(wo.Id, qbIds);

            for (QuickBooksWOLineIntem item : QuickBooksWOLineIntem.fromJson(wo.Quick_Books_Line_Items__c)) {
                if (String.isBlank(item.Description)) {
                    continue;
                }
                if (String.isNotBlank(item.Id)) {
                    qbIds.add(item.Id);
                    toUpsert.add(buildLineItem(item, wo.Id));
                } else {
                    toInsertNoExtId.add(buildLineItem(item, wo.Id));
                }
            }
        }

        List<Quick_Book_Work_Order_Line_Item__c> existing = [
            SELECT Id, Quick_Books_Id__c, Work_Order__c
            FROM Quick_Book_Work_Order_Line_Item__c
            WHERE Work_Order__c IN :woWithJsonIds
        ];

        List<Quick_Book_Work_Order_Line_Item__c> toDelete = new List<Quick_Book_Work_Order_Line_Item__c>();
        for (Quick_Book_Work_Order_Line_Item__c row : existing) {
            Set<String> keep = qbIdsByWo.get(row.Work_Order__c);
            if (keep == null) {
                continue;
            }
            if (String.isNotBlank(row.Quick_Books_Id__c)) {
                if (!keep.contains(row.Quick_Books_Id__c)) {
                    toDelete.add(row);
                }
            } else {
                // No external id — cannot upsert; remove so JSON no-id lines can be re-inserted without duplicating.
                toDelete.add(row);
            }
        }

        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!toUpsert.isEmpty()) {
            Database.upsert(toUpsert, Quick_Book_Work_Order_Line_Item__c.Quick_Books_Id__c);
        }
        if (!toInsertNoExtId.isEmpty()) {
            insert toInsertNoExtId;
        }
    }

    public static void createWorkOrderLineItems(List<WorkOrder> newWorkOrders) {
        Map<Id, List<QuickBooksWOLineIntem>> woLineItemsMap = new Map<Id, List<QuickBooksWOLineIntem>>();

        for (WorkOrder wo : newWorkOrders) {
            if (String.isNotBlank(wo.Quick_Books_Line_Items__c)) {
                woLineItemsMap.put(wo.Id, QuickBooksWOLineIntem.fromJson(wo.Quick_Books_Line_Items__c));
            }
        }
        List<Quick_Book_Work_Order_Line_Item__c> woLineItemsToInsert = new List<Quick_Book_Work_Order_Line_Item__c>();
        for (Id woId : woLineItemsMap.keySet()) {
            for (QuickBooksWOLineIntem item : woLineItemsMap.get(woId)) {
                if (String.isNotBlank(item.Description)) {
                    woLineItemsToInsert.add(buildLineItem(item, woId));
                }
            }
        }
        insert woLineItemsToInsert;
    }

    private static Quick_Book_Work_Order_Line_Item__c buildLineItem(QuickBooksWOLineIntem item, Id workOrderId) {
        Quick_Book_Work_Order_Line_Item__c woLineItem = new Quick_Book_Work_Order_Line_Item__c();
        woLineItem.Name = item.ItemName;
        woLineItem.Work_Order__c = workOrderId;
        woLineItem.Description__c = item.Description;
        woLineItem.Quantity__c = item.Quantity;
        woLineItem.Rate__c = item.Rate;
        woLineItem.Amount__c = item.Amount;
        woLineItem.Quick_Books_Id__c = item.Id;
        woLineItem.Short_Description__c = firstLineOnly(item.Description);
        return woLineItem;
    }

    private static String firstLineOnly(String text) {
        if (String.isBlank(text)) {
            return text;
        }
        String normalized = text.replace('\r\n', '\n').replace('\r', '\n');
        Integer nl = normalized.indexOf('\n');
        return (nl == -1 ? normalized : normalized.substring(0, nl)).trim();
    }
}
