public class ContentVersionTriggerHandler extends TriggerHandler {
    List<ContentVersion> newList;
    Map<Id, ContentVersion> oldMap;

    public ContentVersionTriggerHandler(){
        this.newList = (List<ContentVersion>)Trigger.new;
        this.oldMap = (Map<Id, ContentVersion>)Trigger.oldMap;
    }

    protected override void afterUpdate(){
        // Filter records where specific fields have changed
        List<ContentVersion> docusignChangedVersions = new List<ContentVersion>();
        
        for(ContentVersion newCV : newList) {
            ContentVersion oldCV = oldMap.get(newCV.Id);
            
            // For DocuSign notifications - only when DocuSign status changes
            if(newCV.DocuSign_Envelope_Status__c != oldCV.DocuSign_Envelope_Status__c) {
                docusignChangedVersions.add(newCV);
            }
        }
        
        // Call services only for relevant records
        if(!docusignChangedVersions.isEmpty()) {
            DocuSignNotificationService.handleEnvelopeStatusChange(docusignChangedVersions);
            ContractBidStatusUpdater.updateStatus(docusignChangedVersions);
        }
    }
}