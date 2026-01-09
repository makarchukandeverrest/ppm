global class MapDealLineItemsBatch implements Database.Batchable<SObject>, Database.Stateful {

    global Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT Id, Line_Items__c
            FROM Opportunity
        ]);
    }

    global void execute(Database.BatchableContext BC, List<SObject> scope) {
        List<Opportunity> opps = (List<Opportunity>) scope;

        Map<String, Id> qbIdToOpportunityId = new Map<String, Id>();

        for (Opportunity opp : opps) {
            try {
                List<Object> lineItems = (List<Object>) JSON.deserializeUntyped(opp.Line_Items__c);
                for (Object item : lineItems) {
                    Map<String, Object> itemMap = (Map<String, Object>) item;
                    if (itemMap.containsKey('Id') && itemMap.get('Id') != null) {
                        String qbId = String.valueOf(itemMap.get('Id'));
                        qbIdToOpportunityId.put(qbId, opp.Id);
                    }
                }
            } catch (Exception ex) {
                System.debug('Failed to parse JSON for Opportunity Id: ' + opp.Id + ' - ' + ex.getMessage());
            }
        }

        if (qbIdToOpportunityId.isEmpty()) return;

        List<Deal_Line_Item__c> toUpdate = [
            SELECT Id, QuickBooks_Id__c, Deal__c
            FROM Deal_Line_Item__c
            WHERE QuickBooks_Id__c IN :qbIdToOpportunityId.keySet() AND Deal__c = null
        ];

        for (Deal_Line_Item__c item : toUpdate) {
            Id relatedOppId = qbIdToOpportunityId.get(item.QuickBooks_Id__c);
            if (relatedOppId != null && item.Deal__c != relatedOppId) {
                item.Deal__c = relatedOppId;
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    global void finish(Database.BatchableContext BC) {
        System.debug('Batch finished');
    }
}