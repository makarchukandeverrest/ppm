public class ContentVersionTriggerHandler extends TriggerHandler {

    private List<ContentVersion> newList;
    private Map<Id, ContentVersion> oldMap;

    // DocuSign statuses that should trigger task creation
    private static final Set<String> TASK_TRIGGER_STATUSES = new Set<String>{
        'Sent', 'Delivered', 'Completed'
    };

    public ContentVersionTriggerHandler(){
        newList = (List<ContentVersion>) Trigger.new;
        oldMap = (Map<Id, ContentVersion>) Trigger.oldMap;
    }

    protected override void afterUpdate(){

        System.debug('=== ContentVersion Trigger Handler Started ===');
        System.debug('Total records: ' + newList.size());

        if(newList == null || newList.isEmpty()){
            System.debug('No records to process');
            return;
        }

        List<ContentVersion> docusignChangedVersions = new List<ContentVersion>();

        for(ContentVersion newCV : newList){

            ContentVersion oldCV = oldMap != null ? oldMap.get(newCV.Id) : null;

            System.debug('--------------------------------');
            System.debug('Processing CV Id: ' + newCV.Id);

            String newStatus = newCV.DocuSign_Envelope_Status__c != null
                ? newCV.DocuSign_Envelope_Status__c.trim()
                : null;

            String oldStatus = oldCV != null && oldCV.DocuSign_Envelope_Status__c != null
                ? oldCV.DocuSign_Envelope_Status__c.trim()
                : null;

            Boolean newToSent = newCV.To_Sent__c == true;
            Boolean oldToSent = oldCV != null && oldCV.To_Sent__c == true;

            System.debug('New DocuSign Status: ' + newStatus);
            System.debug('Old DocuSign Status: ' + oldStatus);
            System.debug('New To_Sent: ' + newToSent);
            System.debug('Old To_Sent: ' + oldToSent);

            Boolean shouldCreateTask = false;

            // ✅ Case 1: DocuSign status changed into trigger-status
            if(
                newStatus != null &&
                newStatus != oldStatus &&
                TASK_TRIGGER_STATUSES.contains(newStatus)
            ){
                System.debug('✓ Status changed into trigger status: ' + newStatus);
                shouldCreateTask = true;
            }

            // ✅ Case 2: To_Sent flag switched false -> true
            if(newToSent && !oldToSent){
                System.debug('✓ To_Sent changed to TRUE');
                shouldCreateTask = true;
            }

            if(shouldCreateTask){
                docusignChangedVersions.add(newCV);
                System.debug('→ Marked for processing');
            } else {
                System.debug('✗ No task-triggering changes detected');
            }
        }

        System.debug('--------------------------------');
        System.debug('Total versions to process: ' + docusignChangedVersions.size());
        System.debug('docusignChangedVersions: ' + docusignChangedVersions);

        if(docusignChangedVersions.isEmpty()){
            System.debug('No versions to process — skipping services');
            System.debug('=== Handler Completed ===');
            return;
        }

        System.debug('Calling notification services...');

        try {
            DocuSignNotificationService.handleEnvelopeStatusChange(docusignChangedVersions);
            System.debug('✓ DocuSignNotificationService completed');
        } catch(Exception e){
            System.debug('✗ ERROR in DocuSignNotificationService: ' + e.getMessage());
            System.debug(e.getStackTraceString());
        }

        try{
            ContractBidStatusUpdater.updateStatus(docusignChangedVersions);
            System.debug('✓ ContractBidStatusUpdater completed');
        } catch(Exception e){
            System.debug('✗ ERROR in ContractBidStatusUpdater: ' + e.getMessage());
            System.debug(e.getStackTraceString());
        }

        System.debug('=== Handler Completed ===');
    }
}