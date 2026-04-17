public class DealLineItemJSONBuilder {
    public static void updateDealsWithJSON(Set<Id> dealIds, Set<String> dealQuickBooksIds) {
        Set<Id> allDealIds = new Set<Id>();
        if (dealIds != null) {
            allDealIds.addAll(dealIds);
        }

        Set<String> normalizedDealQuickBooksIds = new Set<String>();
        if (dealQuickBooksIds != null) {
            for (String qbId : dealQuickBooksIds) {
                if (String.isNotBlank(qbId)) {
                    normalizedDealQuickBooksIds.add(qbId.trim());
                }
            }
        }

        Map<String, Id> dealQuickBooksIdToDealId = new Map<String, Id>();
        if (!normalizedDealQuickBooksIds.isEmpty()) {
            for (Opportunity o : [
                SELECT Id, QuickBooks_Id__c
                FROM Opportunity
                WHERE QuickBooks_Id__c IN :normalizedDealQuickBooksIds
            ]) {
                dealQuickBooksIdToDealId.put(o.QuickBooks_Id__c, o.Id);
                allDealIds.add(o.Id);
            }
        }

        if (allDealIds.isEmpty()) {
            return;
        }

        Map<Id, List<Deal_Line_Item__c>> dealIdToItems = new Map<Id, List<Deal_Line_Item__c>>();
        List<Deal_Line_Item__c> lineItemsToAssign = new List<Deal_Line_Item__c>();

        for (Deal_Line_Item__c item : [
            SELECT Id, QuickBooks_Id__c, Name, Description__c, Quantity__c, Unit_Cost__c, Deal__c, Deal_QuickBooks_Id__c
            FROM Deal_Line_Item__c
            WHERE (Deal__c IN :allDealIds OR Deal_QuickBooks_Id__c IN :normalizedDealQuickBooksIds)
                AND QuickBooks_Id__c != null
        ]) {
            Id resolvedDealId = item.Deal__c;
            if (resolvedDealId == null && String.isNotBlank(item.Deal_QuickBooks_Id__c)) {
                resolvedDealId = dealQuickBooksIdToDealId.get(item.Deal_QuickBooks_Id__c.trim());
            }

            if (resolvedDealId == null) {
                continue;
            }

            // Persist the resolved Deal__c when it was missing, using the same resolution
            // logic as the JSON builder. This is applied in the single DML at the end.
            if (item.Deal__c == null) {
                lineItemsToAssign.add(new Deal_Line_Item__c(
                    Id      = item.Id,
                    Deal__c = resolvedDealId
                ));
            }

            if (!dealIdToItems.containsKey(resolvedDealId)) {
                dealIdToItems.put(resolvedDealId, new List<Deal_Line_Item__c>());
            }
            dealIdToItems.get(resolvedDealId).add(item);
        }

        List<Opportunity> dealsToUpdate = new List<Opportunity>();

        for (Id dealId : allDealIds) {
            List<Deal_Line_Item__c> items = dealIdToItems.containsKey(dealId)
                ? dealIdToItems.get(dealId)
                : new List<Deal_Line_Item__c>();

            List<Map<String, Object>> itemList = new List<Map<String, Object>>();

            for (Deal_Line_Item__c item : items) {
                Map<String, Object> m = new Map<String, Object>();
                m.put('Id', item.QuickBooks_Id__c);
                m.put('ItemName', item.Name);
                m.put('Desc', item.Description__c);
                m.put('Quantity', item.Quantity__c);
                m.put('Rate', item.Unit_Cost__c);
                itemList.add(m);
            }

            Opportunity deal = new Opportunity(Id = dealId);
            deal.Line_Items__c = JSON.serialize(itemList);
            dealsToUpdate.add(deal);
        }

        List<SObject> recordsToUpdate = new List<SObject>();
        recordsToUpdate.addAll(lineItemsToAssign);
        recordsToUpdate.addAll(dealsToUpdate);
        if (!recordsToUpdate.isEmpty()) {
            Database.update(recordsToUpdate);
        }
    }
}