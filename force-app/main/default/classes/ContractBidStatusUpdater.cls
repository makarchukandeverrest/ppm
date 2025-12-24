public with sharing class ContractBidStatusUpdater {
    public static void updateStatus(List<ContentVersion> newList) {
        Set<Id> contentDocIds = new Set<Id>();
        Map<Id, String> docIdToStatus = new Map<Id, String>();

        for (ContentVersion cv : newList) {
            if (cv.ContentDocumentId != null && cv.DocuSign_Envelope_Status__c != null) {
                contentDocIds.add(cv.ContentDocumentId);
                docIdToStatus.put(cv.ContentDocumentId, cv.DocuSign_Envelope_Status__c);
            }
        }

        if (contentDocIds.isEmpty()) return;

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :contentDocIds
        ];

        List<Contract_Bid__c> bidsToUpdate = new List<Contract_Bid__c>();

        for (ContentDocumentLink link : links) {
            if (!String.valueOf(link.LinkedEntityId).startsWith('001')) {
                continue;
            }

            String status = docIdToStatus.get(link.ContentDocumentId);
            if (status == null) continue;

            Schema.DescribeFieldResult fieldResult = Contract_Bid__c.Stage__c.getDescribe();
            List<Schema.PicklistEntry> picklistEntries = fieldResult.getPicklistValues();
            List<String> validStages = new List<String>();
            Integer startIdx = Math.max(0, picklistEntries.size() - 5);
            for (Integer i = startIdx; i < picklistEntries.size(); i++) {
                Schema.PicklistEntry entry = picklistEntries[i];
                if(entry.isActive()){
                    validStages.add(entry.getValue());
                }
            }
            
            List<Contract_Bid__c> bids = [
                SELECT Id, Name, Stage__c
                FROM Contract_Bid__c
                WHERE Customer__c = :link.LinkedEntityId
                  AND Stage__c IN : validStages
            ];
            for (Contract_Bid__c bid : bids) {

                if (status == 'Completed') {
                    bid.Stage__c = 'Closed - WON';
                } else if (status == 'Declined' || status == 'Voided') {
                    bid.Stage__c = 'Closed - LOST';
                } else if (status == 'Delivered') {
                    bid.Stage__c = 'Proposal/Review';
                }
                bidsToUpdate.add(bid);
            }
        }

        if (!bidsToUpdate.isEmpty()) {
            update bidsToUpdate;
        }
    }
}