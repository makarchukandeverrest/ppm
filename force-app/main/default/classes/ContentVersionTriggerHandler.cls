public class ContentVersionTriggerHandler extends TriggerHandler {
    List<ContentVersion> newList;
    Map<Id, ContentVersion> oldMap;

    // DocuSign statuses that should trigger task creation
    private static final Set<String> TASK_TRIGGER_STATUSES = new Set<String>{
        'Sent', 'Delivered', 'Completed'
    };

    public ContentVersionTriggerHandler(){
        this.newList = (List<ContentVersion>)Trigger.new;
        this.oldMap = (Map<Id, ContentVersion>)Trigger.oldMap;
    }

    protected override void afterInsert(){
        System.debug('=== ContentVersionTriggerHandler.afterInsert START ===');
        System.debug('Total ContentVersions inserted: ' + newList.size());
        
        if(newList == null || newList.isEmpty()){
            System.debug('No records to process');
            return;
        }

        // =====================================================
        // PART 1: Process DocuSign notifications for new records
        // =====================================================
        List<ContentVersion> docusignVersionsToProcess = new List<ContentVersion>();

        for(ContentVersion newCV : newList){
            String newStatus = newCV.DocuSign_Envelope_Status__c != null
                ? newCV.DocuSign_Envelope_Status__c.trim()
                : null;

            System.debug('Processing CV Id: ' + newCV.Id);
            System.debug('DocuSign Status: ' + newStatus);
            System.debug('To_Sent: ' + newCV.To_Sent__c);

            Boolean shouldProcess = false;

            // ✅ Case 1: New record has trigger-status
            if(newStatus != null && TASK_TRIGGER_STATUSES.contains(newStatus)){
                System.debug('✓ New record has trigger status: ' + newStatus);
                shouldProcess = true;
            }

            // ✅ Case 2: To_Sent is already true
            if(newCV.To_Sent__c == true){
                System.debug('✓ To_Sent is TRUE');
                shouldProcess = true;
            }

            if(shouldProcess){
                docusignVersionsToProcess.add(newCV);
                System.debug('→ Marked for processing');
            }
        }

        // Call notification services for DocuSign records
        if(!docusignVersionsToProcess.isEmpty()){
            System.debug('Calling notification services for ' + docusignVersionsToProcess.size() + ' records...');

            try {
                DocuSignNotificationService.handleEnvelopeStatusChange(docusignVersionsToProcess);
                System.debug('✓ DocuSignNotificationService completed');
            } catch(Exception e){
                System.debug('✗ ERROR in DocuSignNotificationService: ' + e.getMessage());
                System.debug(e.getStackTraceString());
            }

            try {
                ContractBidStatusUpdater.updateStatus(docusignVersionsToProcess);
                System.debug('✓ ContractBidStatusUpdater completed');
            } catch(Exception e){
                System.debug('✗ ERROR in ContractBidStatusUpdater: ' + e.getMessage());
                System.debug(e.getStackTraceString());
            }
        } else {
            System.debug('No DocuSign records to process');
        }

        // =====================================================
        // PART 2: Find and delete duplicates from Email_Platform (GOAT)
        // =====================================================
        List<ContentVersion> potentialDuplicates = new List<ContentVersion>();
        for(ContentVersion newCV : newList) {
            Boolean noEnvelopeId = String.isBlank(newCV.DocuSign_Envelope_Id__c);
            Boolean isFromEmailPlatform = (newCV.Origin == 'H' || newCV.Origin == null);
            Boolean hasFirstPublishLocation = (newCV.FirstPublishLocationId != null);
            Boolean isUserOrAccountId = false;
            if(hasFirstPublishLocation) {
                String prefix = String.valueOf(newCV.FirstPublishLocationId).substring(0, 3);
                isUserOrAccountId = (prefix == '005' || prefix == '001');
            }
            
            if(noEnvelopeId && isFromEmailPlatform && hasFirstPublishLocation && isUserOrAccountId) {
                potentialDuplicates.add(newCV);
            }
        }
        
        if(!potentialDuplicates.isEmpty()) {
            System.debug('Found ' + potentialDuplicates.size() + ' potential duplicates from Email_Platform');
            processDuplicates(potentialDuplicates);
        } else {
            System.debug('No potential duplicates from Email_Platform found');
        }
        
        System.debug('=== ContentVersionTriggerHandler.afterInsert END ===');
    }

    protected override void afterUpdate(){
        System.debug('=== ContentVersionTriggerHandler.afterUpdate START ===');
        System.debug('Total ContentVersions updated: ' + newList.size());
        
        if(newList == null || newList.isEmpty()){
            System.debug('No records to process');
            return;
        }

        // Check for duplicates from Email_Platform (GOAT)
        checkForDuplicatesInUpdate();
        
        // Filter records where specific fields have changed
        List<ContentVersion> docusignChangedVersions = new List<ContentVersion>();
        
        for(ContentVersion newCV : newList) {
            ContentVersion oldCV = oldMap.get(newCV.Id);
            
            System.debug('--- Analyzing ContentVersion: ' + newCV.Id + ' ---');
            System.debug('Title: ' + newCV.Title);
            System.debug('DocuSign_Envelope_Id__c: ' + newCV.DocuSign_Envelope_Id__c);
            
            // Check VersionNumber change
            if(newCV.VersionNumber != oldCV.VersionNumber) {
                System.debug('⚠️ VERSION NUMBER CHANGED: ' + oldCV.VersionNumber + ' → ' + newCV.VersionNumber);
            }
            
            // Check ContentDocumentId change
            if(newCV.ContentDocumentId != oldCV.ContentDocumentId) {
                System.debug('⚠️ CONTENT DOCUMENT ID CHANGED: ' + oldCV.ContentDocumentId + ' → ' + newCV.ContentDocumentId);
            }
            
            // Check FirstPublishLocationId change
            if(newCV.FirstPublishLocationId != oldCV.FirstPublishLocationId) {
                System.debug('⚠️ FIRST PUBLISH LOCATION ID CHANGED: ' + oldCV.FirstPublishLocationId + ' → ' + newCV.FirstPublishLocationId);
            }
            
            // For DocuSign notifications - only when DocuSign status changes
            if(newCV.DocuSign_Envelope_Status__c != oldCV.DocuSign_Envelope_Status__c) {
                System.debug('✅ DocuSign Status CHANGED: ' + oldCV.DocuSign_Envelope_Status__c + ' → ' + newCV.DocuSign_Envelope_Status__c);
                docusignChangedVersions.add(newCV);
            }
            
            // Also check To_Sent change
            Boolean newToSent = newCV.To_Sent__c == true;
            Boolean oldToSent = oldCV.To_Sent__c == true;
            if(newToSent && !oldToSent) {
                System.debug('✅ To_Sent CHANGED to TRUE');
                if(!docusignChangedVersions.contains(newCV)) {
                    docusignChangedVersions.add(newCV);
                }
            }
        }
        
        System.debug('ContentVersions with changes: ' + docusignChangedVersions.size());
        
        // Call services only for relevant records
        if(!docusignChangedVersions.isEmpty()) {
            System.debug('Calling notification services...');
            
            try {
                DocuSignNotificationService.handleEnvelopeStatusChange(docusignChangedVersions);
                System.debug('✓ DocuSignNotificationService completed');
            } catch(Exception e){
                System.debug('✗ ERROR in DocuSignNotificationService: ' + e.getMessage());
                System.debug(e.getStackTraceString());
            }

            try {
                ContractBidStatusUpdater.updateStatus(docusignChangedVersions);
                System.debug('✓ ContractBidStatusUpdater completed');
            } catch(Exception e){
                System.debug('✗ ERROR in ContractBidStatusUpdater: ' + e.getMessage());
                System.debug(e.getStackTraceString());
            }
        } else {
            System.debug('No changes detected, skipping service calls');
        }
        
        System.debug('=== ContentVersionTriggerHandler.afterUpdate END ===');
    }
    
    /**
     * Check for duplicates in afterUpdate context
     */
    private void checkForDuplicatesInUpdate() {
        System.debug('=== Checking for duplicates in afterUpdate ===');
        
        DateTime last5Seconds = DateTime.now().addSeconds(-5);
        
        List<ContentVersion> potentialDuplicates = new List<ContentVersion>();
        for(ContentVersion newCV : newList) {
            ContentVersion oldCV = oldMap.get(newCV.Id);
            
            Boolean noEnvelopeId = String.isBlank(newCV.DocuSign_Envelope_Id__c);
            Boolean isFromEmailPlatform = (newCV.Origin == 'H' || newCV.Origin == null);
            Boolean hasFirstPublishLocation = (newCV.FirstPublishLocationId != null);
            Boolean isUserOrAccountId = false;
            if(hasFirstPublishLocation) {
                String prefix = String.valueOf(newCV.FirstPublishLocationId).substring(0, 3);
                isUserOrAccountId = (prefix == '005' || prefix == '001');
            }
            Boolean justCreated = (newCV.CreatedDate >= last5Seconds);
            Boolean publishStatusChanged = (oldCV.PublishStatus == 'R' && newCV.PublishStatus == 'P');
            
            if(noEnvelopeId && isFromEmailPlatform && hasFirstPublishLocation && isUserOrAccountId && 
               (justCreated || publishStatusChanged)) {
                potentialDuplicates.add(newCV);
            }
        }
        
        if(!potentialDuplicates.isEmpty()) {
            System.debug('Found ' + potentialDuplicates.size() + ' potential duplicates in afterUpdate');
            processDuplicates(potentialDuplicates);
        } else {
            System.debug('No potential duplicates found in afterUpdate');
        }
    }
    
    /**
     * Shared method to process and delete duplicates
     */
    private void processDuplicates(List<ContentVersion> potentialDuplicates) {
        Set<Id> potentialDuplicateIds = new Set<Id>();
        for(ContentVersion cv : potentialDuplicates) {
            potentialDuplicateIds.add(cv.Id);
        }
        
        List<ContentVersion> duplicatesWithFields = [
            SELECT Id, Title, ContentSize, CreatedDate, ContentDocumentId, Origin, FirstPublishLocationId
            FROM ContentVersion
            WHERE Id IN :potentialDuplicateIds
        ];
        
        DateTime last24Hours = DateTime.now().addHours(-24);
        
        Set<String> titles = new Set<String>();
        Map<String, Integer> titleToSize = new Map<String, Integer>();
        for(ContentVersion cv : duplicatesWithFields) {
            if(String.isNotBlank(cv.Title) && cv.ContentSize != null) {
                titles.add(cv.Title);
                titleToSize.put(cv.Title, Integer.valueOf(cv.ContentSize));
            }
        }
        
        if(titles.isEmpty()) {
            System.debug('Cannot match duplicates - missing Title or ContentSize');
            return;
        }
        
        List<ContentVersion> originalVersions = [
            SELECT Id, Title, ContentSize, ContentDocumentId, DocuSign_Envelope_Id__c, CreatedDate
            FROM ContentVersion
            WHERE DocuSign_Envelope_Id__c != null
            AND Title IN :titles
            AND CreatedDate >= :last24Hours
            AND Id NOT IN :potentialDuplicateIds
            ORDER BY CreatedDate ASC
        ];
        
        List<ContentVersion> filteredOriginals = new List<ContentVersion>();
        for(ContentVersion orig : originalVersions) {
            Integer expectedSize = titleToSize.get(orig.Title);
            if(expectedSize != null && orig.ContentSize != null && Integer.valueOf(orig.ContentSize) == expectedSize) {
                filteredOriginals.add(orig);
            }
        }
        originalVersions = filteredOriginals;
        
        System.debug('Found ' + originalVersions.size() + ' potential original ContentVersions with EnvelopeId');
        
        Map<String, ContentVersion> titleSizeToOriginal = new Map<String, ContentVersion>();
        for(ContentVersion orig : originalVersions) {
            String key = orig.Title + '|' + Integer.valueOf(orig.ContentSize);
            if(!titleSizeToOriginal.containsKey(key)) {
                titleSizeToOriginal.put(key, orig);
            }
        }
        
        List<ContentVersion> duplicatesToDelete = new List<ContentVersion>();
        for(ContentVersion duplicate : duplicatesWithFields) {
            String key = duplicate.Title + '|' + Integer.valueOf(duplicate.ContentSize);
            ContentVersion original = titleSizeToOriginal.get(key);
            
            if(original != null) {
                Long timeDiff = Math.abs(duplicate.CreatedDate.getTime() - original.CreatedDate.getTime());
                Long oneHourInMs = 3600000;
                
                if(timeDiff <= oneHourInMs) {
                    System.debug('⚠️ DUPLICATE DETECTED:');
                    System.debug('   Duplicate CV: ' + duplicate.Id);
                    System.debug('   Original CV: ' + original.Id);
                    duplicatesToDelete.add(duplicate);
                }
            }
        }
        
        if(!duplicatesToDelete.isEmpty()) {
            System.debug('Deleting ' + duplicatesToDelete.size() + ' duplicate ContentVersions');
            
            Set<Id> duplicateIds = new Set<Id>();
            for(ContentVersion cv : duplicatesToDelete) {
                duplicateIds.add(cv.Id);
            }
            
            List<ContentVersion> duplicatesWithDocIds = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id IN :duplicateIds
            ];
            
            Set<Id> contentDocIds = new Set<Id>();
            for(ContentVersion cv : duplicatesWithDocIds) {
                if(cv.ContentDocumentId != null) {
                    contentDocIds.add(cv.ContentDocumentId);
                }
            }
            
            if(!contentDocIds.isEmpty()) {
                List<ContentDocumentLink> linksToDelete = [
                    SELECT Id
                    FROM ContentDocumentLink
                    WHERE ContentDocumentId IN :contentDocIds
                ];
                
                if(!linksToDelete.isEmpty()) {
                    delete linksToDelete;
                }
                
                List<ContentDocument> docsToCheck = [
                    SELECT Id, (
                        SELECT Id 
                        FROM ContentVersions 
                        WHERE Id NOT IN :duplicateIds
                    )
                    FROM ContentDocument
                    WHERE Id IN :contentDocIds
                ];
                
                List<ContentDocument> docsToDelete = new List<ContentDocument>();
                for(ContentDocument doc : docsToCheck) {
                    if(doc.ContentVersions == null || doc.ContentVersions.isEmpty()) {
                        docsToDelete.add(doc);
                    }
                }
                
                if(!docsToDelete.isEmpty()) {
                    delete docsToDelete;
                    System.debug('✅ Deleted ' + docsToDelete.size() + ' duplicate ContentDocuments');
                }
            }
        } else {
            System.debug('No duplicates found');
        }
    }
}