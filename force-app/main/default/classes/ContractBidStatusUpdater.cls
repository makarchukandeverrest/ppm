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

            StageReferenceSettings__mdt stageReference = StageReferenceSettings__mdt.getInstance('Send_Contract_Stages');
            List<String> validStages = stageReference.Stage_Names__c.split(',');
            
            List<Contract_Bid__c> bids = [
                SELECT Id, Name, Stage__c
                FROM Contract_Bid__c
                WHERE Customer__c = :link.LinkedEntityId
                  AND Stage__c IN : validStages
            ];
            for (Contract_Bid__c bid : bids) {

                if (status == 'Completed') {
                    bid.Stage__c = 'Closed - WON';
                } else if (status == 'Delivered') {
                    bid.Stage__c = 'Proposal/Review';
                }
                // NOT handling Declined or Voided statuses
                bidsToUpdate.add(bid);
            }
        }

        if (!bidsToUpdate.isEmpty()) {
            update bidsToUpdate;
        }
    }
}