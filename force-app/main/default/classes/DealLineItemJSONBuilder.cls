public class DealLineItemJSONBuilder {
    public static void updateDealsWithJSON(Set<Id> dealIds) {
        Map<Id, List<Deal_Line_Item__c>> dealIdToItems = new Map<Id, List<Deal_Line_Item__c>>();

        for (Deal_Line_Item__c item : [
            SELECT QuickBooks_Id__c, Name, Description__c, Quantity__c, Unit_Cost__c, Deal__c
            FROM Deal_Line_Item__c
            WHERE Deal__c IN :dealIds AND QuickBooks_Id__c != null
        ]) {
            if (!dealIdToItems.containsKey(item.Deal__c)) {
                dealIdToItems.put(item.Deal__c, new List<Deal_Line_Item__c>());
            }
            dealIdToItems.get(item.Deal__c).add(item);
        }

        List<Opportunity> dealsToUpdate = new List<Opportunity>();

        for (Id dealId : dealIdToItems.keySet()) {
            List<Deal_Line_Item__c> items = dealIdToItems.get(dealId);

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

        if (!dealsToUpdate.isEmpty()) {
            Database.update(dealsToUpdate);
        }
    }
}