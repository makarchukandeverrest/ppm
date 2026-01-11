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
        // Filter ContentVersions that might be duplicates from Email_Platform
        List<ContentVersion> potentialDuplicates = new List<ContentVersion>();
        for(ContentVersion newCV : newList) {
            // Check if this looks like a duplicate from Email_Platform:
            // - No EnvelopeId (duplicates don't have it)
            // - Origin = 'H' or null (Email_Platform)
            // - FirstPublishLocationId = User ID (005) or Account ID (001) - both can be from Email_Platform
            Boolean noEnvelopeId = String.isBlank(newCV.DocuSign_Envelope_Id__c);
            Boolean isFromEmailPlatform = (newCV.Origin == 'H' || newCV.Origin == null);
            Boolean hasFirstPublishLocation = (newCV.FirstPublishLocationId != null);
            Boolean isUserOrAccountId = false;
            if(hasFirstPublishLocation) {
                String prefix = String.valueOf(newCV.FirstPublishLocationId).substring(0, 3);
                isUserOrAccountId = (prefix == '005' || prefix == '001'); // User ID or Account ID
            }
            
            if(noEnvelopeId && isFromEmailPlatform && hasFirstPublishLocation && isUserOrAccountId) {
                potentialDuplicates.add(newCV);
            }
        }
        
        if(potentialDuplicates.isEmpty()) {
            System.debug('No potential duplicates from Email_Platform found');
            System.debug('=== ContentVersionTriggerHandler.afterInsert END ===');
            return;
        }
        
        System.debug('Found ' + potentialDuplicates.size() + ' potential duplicates from Email_Platform');
        processDuplicates(potentialDuplicates);
        
        System.debug('=== ContentVersionTriggerHandler.afterInsert END ===');
    }

    protected override void afterUpdate(){
        System.debug('=== ContentVersionTriggerHandler.afterUpdate START ===');
        System.debug('Total ContentVersions updated: ' + newList.size());
        
<<<<<<< HEAD
        if(newList == null || newList.isEmpty()){
            System.debug('No records to process');
            return;
        }

        // Check for duplicates from Email_Platform (GOAT) that were just created
        // GOAT creates ContentVersion and immediately updates PublishStatus from 'R' to 'P',
        // so we need to check for duplicates in afterUpdate as well
        checkForDuplicatesInUpdate();
        
        // Filter records where specific fields have changed
        List<ContentVersion> docusignChangedVersions = new List<ContentVersion>();
        
        for(ContentVersion newCV : newList) {
            ContentVersion oldCV = oldMap.get(newCV.Id);
            
            System.debug('--- Analyzing ContentVersion: ' + newCV.Id + ' ---');
            System.debug('Title: ' + newCV.Title);
            System.debug('DocuSign_Envelope_Id__c: ' + newCV.DocuSign_Envelope_Id__c);
            
            // 🔍 CHECK 1: VersionNumber change (new ContentVersion created?)
            if(newCV.VersionNumber != oldCV.VersionNumber) {
                System.debug('⚠️ VERSION NUMBER CHANGED: ' + oldCV.VersionNumber + ' → ' + newCV.VersionNumber);
                System.debug('⚠️ NEW ContentVersion CREATED by DocuSign!');
            } else {
                System.debug('✅ VersionNumber unchanged: ' + newCV.VersionNumber);
            }
            
            // 🔍 CHECK 2: ContentDocumentId change (new ContentDocument created?)
            if(newCV.ContentDocumentId != oldCV.ContentDocumentId) {
                System.debug('⚠️ CONTENT DOCUMENT ID CHANGED: ' + oldCV.ContentDocumentId + ' → ' + newCV.ContentDocumentId);
                System.debug('⚠️ NEW ContentDocument CREATED!');
            } else {
                System.debug('✅ ContentDocumentId unchanged: ' + newCV.ContentDocumentId);
            }
            
            // 🔍 CHECK 3: FirstPublishLocationId change
            if(newCV.FirstPublishLocationId != oldCV.FirstPublishLocationId) {
                System.debug('⚠️ FIRST PUBLISH LOCATION ID CHANGED:');
                System.debug('   Old: ' + oldCV.FirstPublishLocationId);
                System.debug('   New: ' + newCV.FirstPublishLocationId);
                
                // Determine entity type
                if(newCV.FirstPublishLocationId != null) {
                    String prefix = String.valueOf(newCV.FirstPublishLocationId).substring(0, 3);
                    if(prefix == '005') {
                        System.debug('   ⚠️ FirstPublishLocationId set to USER ID');
                    } else if(prefix == '02s') {
                        System.debug('   ⚠️ FirstPublishLocationId set to EMAILMESSAGE ID');
                    } else if(prefix == '001') {
                        System.debug('   ✅ FirstPublishLocationId set to ACCOUNT ID');
                    }
                }
            } else {
                System.debug('✅ FirstPublishLocationId unchanged: ' + newCV.FirstPublishLocationId);
                if(newCV.FirstPublishLocationId != null) {
                    String prefix = String.valueOf(newCV.FirstPublishLocationId).substring(0, 3);
                    if(prefix == '005') {
                        System.debug('   ⚠️ FirstPublishLocationId is USER ID (may cause issues)');
                    } else if(prefix == '02s') {
                        System.debug('   ⚠️ FirstPublishLocationId is EMAILMESSAGE ID (may cause issues)');
                    }
                }
            }
            
            // 🔍 CHECK 4: ContentDocumentLinks for this ContentDocument
            if(newCV.ContentDocumentId != null) {
                List<ContentDocumentLink> allLinks = [
                    SELECT Id, LinkedEntityId, ShareType, Visibility
                    FROM ContentDocumentLink
                    WHERE ContentDocumentId = :newCV.ContentDocumentId
                ];
                
                System.debug('📎 ContentDocumentLinks for ContentDocument ' + newCV.ContentDocumentId + ': ' + allLinks.size());
                
                List<Id> accountLinks = new List<Id>();
                List<Id> userLinks = new List<Id>();
                List<Id> emailLinks = new List<Id>();
                
                for(ContentDocumentLink link : allLinks) {
                    String prefix = String.valueOf(link.LinkedEntityId).substring(0, 3);
                    if(prefix == '001') {
                        accountLinks.add(link.LinkedEntityId);
                    } else if(prefix == '005') {
                        userLinks.add(link.LinkedEntityId);
                    } else if(prefix == '02s') {
                        emailLinks.add(link.LinkedEntityId);
                    }
                }
                
                System.debug('   Account links: ' + accountLinks.size() + ' - ' + accountLinks);
                System.debug('   User links: ' + userLinks.size() + ' - ' + userLinks);
                System.debug('   EmailMessage links: ' + emailLinks.size() + ' - ' + emailLinks);
                
                if(accountLinks.isEmpty()) {
                    System.debug('   ⚠️ NO ACCOUNT LINK FOUND! This may cause issues.');
                } else {
                    System.debug('   ✅ Account link exists');
                }
            }
            
            // For DocuSign notifications - only when DocuSign status changes
            if(newCV.DocuSign_Envelope_Status__c != oldCV.DocuSign_Envelope_Status__c) {
                System.debug('✅ DocuSign Status CHANGED: ' + oldCV.DocuSign_Envelope_Status__c + ' → ' + newCV.DocuSign_Envelope_Status__c);
                docusignChangedVersions.add(newCV);
            } else {
                System.debug('ℹ️ DocuSign Status unchanged: ' + newCV.DocuSign_Envelope_Status__c);
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
            
            System.debug('--- End Analysis for ContentVersion: ' + newCV.Id + ' ---');
        }
        
        System.debug('ContentVersions with DocuSign status change: ' + docusignChangedVersions.size());
        
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
            System.debug('No DocuSign status changes detected, skipping service calls');
        }
        
        System.debug('=== ContentVersionTriggerHandler.afterUpdate END ===');
    }
    
    /**
     * Check for duplicates in afterUpdate context
     * This handles cases where GOAT creates ContentVersion and immediately updates it
     */
    private void checkForDuplicatesInUpdate() {
        System.debug('=== Checking for duplicates in afterUpdate ===');
        
        // Find ContentVersions that look like they were just created by GOAT
        // Criteria: CreatedDate is very recent (within last 5 seconds), Origin = 'H', 
        // FirstPublishLocationId = User/Account ID, DocuSign_Envelope_Id__c = null
        DateTime last5Seconds = DateTime.now().addSeconds(-5);
        
        List<ContentVersion> potentialDuplicates = new List<ContentVersion>();
        for(ContentVersion newCV : newList) {
            ContentVersion oldCV = oldMap.get(newCV.Id);
            
            // Check if this looks like a duplicate from Email_Platform:
            Boolean noEnvelopeId = String.isBlank(newCV.DocuSign_Envelope_Id__c);
            Boolean isFromEmailPlatform = (newCV.Origin == 'H' || newCV.Origin == null);
            Boolean hasFirstPublishLocation = (newCV.FirstPublishLocationId != null);
            Boolean isUserOrAccountId = false;
            if(hasFirstPublishLocation) {
                String prefix = String.valueOf(newCV.FirstPublishLocationId).substring(0, 3);
                isUserOrAccountId = (prefix == '005' || prefix == '001'); // User ID or Account ID
            }
            Boolean justCreated = (newCV.CreatedDate >= last5Seconds);
            // Check if PublishStatus changed from 'R' to 'P' (GOAT publishes the document)
            Boolean publishStatusChanged = (oldCV.PublishStatus == 'R' && newCV.PublishStatus == 'P');
            
            if(noEnvelopeId && isFromEmailPlatform && hasFirstPublishLocation && isUserOrAccountId && 
               (justCreated || publishStatusChanged)) {
                System.debug('⚠️ Potential duplicate detected in afterUpdate: ' + newCV.Id);
                System.debug('   Title: ' + newCV.Title);
                System.debug('   CreatedDate: ' + newCV.CreatedDate);
                System.debug('   PublishStatus: ' + oldCV.PublishStatus + ' → ' + newCV.PublishStatus);
                potentialDuplicates.add(newCV);
            }
        }
        
        if(potentialDuplicates.isEmpty()) {
            System.debug('No potential duplicates found in afterUpdate');
            return;
        }
        
        System.debug('Found ' + potentialDuplicates.size() + ' potential duplicates in afterUpdate');
        
        // Use the same duplicate detection logic as afterInsert
        processDuplicates(potentialDuplicates);
    }
    
    /**
     * Shared method to process and delete duplicates
     */
    private void processDuplicates(List<ContentVersion> potentialDuplicates) {
        Set<Id> potentialDuplicateIds = new Set<Id>();
        for(ContentVersion cv : potentialDuplicates) {
            potentialDuplicateIds.add(cv.Id);
        }
        
        // Re-query to get all fields needed for comparison
        List<ContentVersion> duplicatesWithFields = [
            SELECT Id, Title, ContentSize, CreatedDate, ContentDocumentId, Origin, FirstPublishLocationId
            FROM ContentVersion
            WHERE Id IN :potentialDuplicateIds
        ];
        
        // Find original ContentVersions with EnvelopeId that match by Title and ContentSize
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
        
        // Find original ContentVersions with EnvelopeId
        List<ContentVersion> originalVersions = [
            SELECT Id, Title, ContentSize, ContentDocumentId, DocuSign_Envelope_Id__c, CreatedDate
            FROM ContentVersion
            WHERE DocuSign_Envelope_Id__c != null
            AND Title IN :titles
            AND CreatedDate >= :last24Hours
            AND Id NOT IN :potentialDuplicateIds
            ORDER BY CreatedDate ASC
        ];
        
        // Filter by ContentSize in Apex
        List<ContentVersion> filteredOriginals = new List<ContentVersion>();
        for(ContentVersion orig : originalVersions) {
            Integer expectedSize = titleToSize.get(orig.Title);
            if(expectedSize != null && orig.ContentSize != null && Integer.valueOf(orig.ContentSize) == expectedSize) {
                filteredOriginals.add(orig);
            }
        }
        originalVersions = filteredOriginals;
        
        System.debug('Found ' + originalVersions.size() + ' potential original ContentVersions with EnvelopeId');
        
        // Create map for quick lookup: Title + ContentSize -> Original ContentVersion
        Map<String, ContentVersion> titleSizeToOriginal = new Map<String, ContentVersion>();
        for(ContentVersion orig : originalVersions) {
            String key = orig.Title + '|' + Integer.valueOf(orig.ContentSize);
            if(!titleSizeToOriginal.containsKey(key)) {
                titleSizeToOriginal.put(key, orig);
            }
        }
        
        // Identify duplicates
        List<ContentVersion> duplicatesToDelete = new List<ContentVersion>();
        for(ContentVersion duplicate : duplicatesWithFields) {
            String key = duplicate.Title + '|' + Integer.valueOf(duplicate.ContentSize);
            ContentVersion original = titleSizeToOriginal.get(key);
            
            if(original != null) {
                // Additional check: CreatedDate should be close (within 1 hour of original)
                Long timeDiff = Math.abs(duplicate.CreatedDate.getTime() - original.CreatedDate.getTime());
                Long oneHourInMs = 3600000; // 1 hour in milliseconds
                
                if(timeDiff <= oneHourInMs) {
                    System.debug('⚠️ DUPLICATE DETECTED:');
                    System.debug('   Duplicate CV: ' + duplicate.Id + ' (Origin: ' + duplicate.Origin + ')');
                    System.debug('   Original CV: ' + original.Id + ' (Created: ' + original.CreatedDate + ')');
                    System.debug('   EnvelopeId: ' + original.DocuSign_Envelope_Id__c);
                    System.debug('   Title: ' + duplicate.Title);
                    System.debug('   ContentSize: ' + duplicate.ContentSize);
                    
                    duplicatesToDelete.add(duplicate);
                }
            }
        }
        
        // Delete duplicates
        if(!duplicatesToDelete.isEmpty()) {
            System.debug('Deleting ' + duplicatesToDelete.size() + ' duplicate ContentVersions from Email_Platform');
            
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
                // Delete ContentDocumentLinks first
                List<ContentDocumentLink> linksToDelete = [
                    SELECT Id
                    FROM ContentDocumentLink
                    WHERE ContentDocumentId IN :contentDocIds
                ];
                
                if(!linksToDelete.isEmpty()) {
                    System.debug('Deleting ' + linksToDelete.size() + ' ContentDocumentLinks');
                    delete linksToDelete;
                }
                
                // Check if ContentDocuments have other ContentVersions
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
                    System.debug('Deleting ' + docsToDelete.size() + ' ContentDocuments (this will also delete ContentVersions)');
                    delete docsToDelete;
                    System.debug('✅ Successfully deleted ' + docsToDelete.size() + ' duplicate ContentDocuments and their ContentVersions');
                } else {
                    System.debug('⚠️ Cannot delete ContentDocuments - they have other ContentVersions');
                    System.debug('⚠️ ContentVersions will remain, but ContentDocumentLinks have been deleted');
                }
            }
        } else {
            System.debug('No duplicates found');
        }
    }
}