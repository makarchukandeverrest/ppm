public class SharePointProxyContentVersionService implements Queueable, Database.AllowsCallouts {
    public String year;
    public Integer offset;
    public Integer batchSize;
    public Set<String> existingProxies;
    public ExternalDataSource source;
    public String sharePointURL;
    public Integer totalProcessed;
    
    // Static variables to cache data across queueable executions
    private static ExternalDataSource cachedSource;
    private static String cachedSharePointURL;
    private static Set<String> cachedExistingProxies;
    
    // Конструктор с параметрами
    public SharePointProxyContentVersionService(String year) {
        this(year, 0, 200);
    }
    
    public SharePointProxyContentVersionService(String year, Integer offset, Integer batchSize) {
        this.year = year;
        this.offset = offset;
        this.batchSize = batchSize;
        this.totalProcessed = 0;
        
        initializeSharedData();
    }
    
    // Initialize shared data only once using static caching
    private void initializeSharedData() {
        // Initialize source and sharePointURL only once
        if (cachedSource == null) {
            cachedSource = [SELECT Id, CustomConfiguration FROM ExternalDataSource WHERE MasterLabel = 'Share Point' LIMIT 1];
            Map<String, Object> parsedConfig = (Map<String, Object>)JSON.deserializeUntyped(cachedSource.CustomConfiguration);
            cachedSharePointURL = (String)parsedConfig.get('sharepointConnectorUrl');
        }
        
        this.source = cachedSource;
        this.sharePointURL = cachedSharePointURL;
        
        // Initialize existingProxies only for the first batch
        if (cachedExistingProxies == null && this.offset == 0) {
            cachedExistingProxies = new Set<String>();
            String trimmedId = String.valueOf(this.source.Id).substring(0, String.valueOf(this.source.Id).length() - 3);
            
            // Use a more efficient query - only get what we need
            for (ContentVersion cv : [
                SELECT ExternalDocumentInfo2
                FROM ContentVersion
                WHERE ContentLocation = 'E' AND ExternalDataSourceId = :this.source.Id
                LIMIT 10000
            ]) {
                cachedExistingProxies.add(trimmedId + ':' + cv.ExternalDocumentInfo2);
            }
            System.debug('Existing proxies: ' + cachedExistingProxies.size());
        }
        
        this.existingProxies = cachedExistingProxies != null ? cachedExistingProxies : new Set<String>();
    }
    
    public void execute(QueueableContext context) {
        try {
            System.debug('Processing batch with offset: ' + offset + ', batchSize: ' + batchSize);
            
            // Get SharePoint items
            List<Items_SharePoint__x> items = getSharePointItems();
            System.debug('Fetched ' + items.size() + ' items from SharePoint.');
            
            if (items.isEmpty()) {
                System.debug('No more items to process. Total processed: ' + totalProcessed);
                // Clear cache when done
                clearCache();
                return;
            }
            
            // Process items
            processItems(items);
            
            totalProcessed += items.size();
            System.debug('Successfully processed batch. Total processed so far: ' + totalProcessed);
            
            // Queue next batch if needed
            if (items.size() == batchSize && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                Integer nextOffset = offset + batchSize;
                System.debug('Enqueuing next batch with offset: ' + nextOffset);
                
                // Pass the cached data to next batch
                SharePointProxyContentVersionService nextBatch = new SharePointProxyContentVersionService(year, nextOffset, batchSize);
                System.enqueueJob(nextBatch);
            } else {
                System.debug('Processing completed. Total records processed: ' + totalProcessed);
                clearCache();
            }
            
        } catch (Exception e) {
            System.debug('Error in SharePointProxyContentVersionService: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            clearCache();
        }
    }
    
    // Clear cache when processing is complete
    private void clearCache() {
        if (this.offset == 0) {
            cachedSource = null;
            cachedSharePointURL = null;
            cachedExistingProxies = null;
        }
    }
    
    private List<Items_SharePoint__x> getSharePointItems() {
        String likePattern1 = sharePointURL + '/Commercial Bids/' + year + '%';
        String likePattern2 = sharePointURL + '/Company Folder/' + year + '%';
        
        return [
            SELECT Id, Name__c, ExternalId, Path__c
            FROM Items_SharePoint__x
            WHERE ExternalId != null
                AND IsFolder__c = false
                AND (Path__c LIKE :likePattern1 OR Path__c LIKE :likePattern2)
            ORDER BY ExternalId
            LIMIT :batchSize
            OFFSET :offset 
        ];
    }
    
    private void processItems(List<Items_SharePoint__x> items) {
        List<ContentVersion> toInsert = new List<ContentVersion>();
        Set<String> processedExternalIds = new Set<String>();
        
        // Collect data for insertion
        for (Items_SharePoint__x item : items) {
            if (!existingProxies.contains(item.ExternalId) && !processedExternalIds.contains(item.ExternalId)) {
                ContentVersion cv = createContentVersion(item);
                toInsert.add(cv);
                processedExternalIds.add(item.ExternalId);
            }
        }
        
        System.debug('Preparing to insert ' + toInsert.size() + ' ContentVersion records.');
        
        if (!toInsert.isEmpty()) {
            // Insert ContentVersion
            insert toInsert;
            
            // Process ContentDocumentLinks - optimized to reduce SOQL
            processContentDocumentLinks(toInsert);

            if(!toInsert.isEmpty()) {
                deleteOldContentVersions(toInsert);
            }

            // Update existingProxies cache
            String trimmedId = String.valueOf(source.Id).substring(0, String.valueOf(source.Id).length() - 3);
            for (ContentVersion cv : toInsert) {
                if (cachedExistingProxies != null) {
                    cachedExistingProxies.add(trimmedId + ':' + cv.ExternalDocumentInfo2);
                }
                existingProxies.add(trimmedId + ':' + cv.ExternalDocumentInfo2);
            }
        }
    }
    
    private ContentVersion createContentVersion(Items_SharePoint__x item) {
        ContentVersion cv = new ContentVersion();
        cv.Title = item.Name__c;
        cv.PathOnClient = item.Name__c;
        cv.ContentLocation = 'E';
        cv.Origin = 'H';
        cv.ExternalDataSourceId = source.Id;
        cv.ExternalDocumentInfo1 = item.Path__c;
        cv.ExternalDocumentInfo2 = item.ExternalId;
        return cv;
    }
    
    private void processContentDocumentLinks(List<ContentVersion> contentVersions) {
        // Optimized version - combine operations where possible
        Map<Id, ContentVersion> versionIdToVersion = new Map<Id, ContentVersion>();
        Set<String> customerNames = new Set<String>();
        
        for (ContentVersion cv : contentVersions) {
            versionIdToVersion.put(cv.Id, cv);
            String customerName = extractCustomerNameFromPath(cv.ExternalDocumentInfo1);
            if (String.isNotBlank(customerName)) {
                customerNames.add(customerName);
            }
        }
        
        // Get ContentDocumentIds in one query
        Map<Id, Id> versionIdToDocId = new Map<Id, Id>();
        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId 
            FROM ContentVersion 
            WHERE Id IN :versionIdToVersion.keySet()
        ]) {
            versionIdToDocId.put(cv.Id, cv.ContentDocumentId);
        }
        
        // Get Account Ids
        Map<String, Id> customerNameToAccountId = new Map<String, Id>();
        for (Account acc : [SELECT Id, Name FROM Account WHERE Name IN :customerNames]) {
            customerNameToAccountId.put(acc.Name, acc.Id);
        }
        
        // Create ContentDocumentLink
        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (ContentVersion cv : contentVersions) {
            Id docId = versionIdToDocId.get(cv.Id);
            if (docId == null) continue;
            
            String customerName = extractCustomerNameFromPath(cv.ExternalDocumentInfo1);
            Id accountId = customerNameToAccountId.get(customerName);
            
            if (accountId != null) {
                ContentDocumentLink link = new ContentDocumentLink();
                link.ContentDocumentId = docId;
                link.LinkedEntityId = accountId;
                link.ShareType = 'V';
                link.Visibility = 'AllUsers';
                linksToInsert.add(link);
            }
        }
        
        if (!linksToInsert.isEmpty()) {
            insert linksToInsert;
            System.debug('Inserted ' + linksToInsert.size() + ' ContentDocumentLinks');
        }
    }

    private void deleteOldContentVersions(List<ContentVersion> contentVersions) {
        Set<String> contentVersionNames = new Set<String>();
        for (ContentVersion cv : contentVersions) {
            contentVersionNames.add(cv.Title);
        }
        
        List<ContentVersion> oldVersions = [
            SELECT Id, ContentDocumentId 
            FROM ContentVersion 
            WHERE Title IN :contentVersionNames 
            AND ContentLocation = 'S' AND Origin = 'C'
        ];
        
        Set<Id> docToDeleteIds = new Set<Id>();
        for (ContentVersion v : oldVersions) {
            docToDeleteIds.add(v.ContentDocumentId);
        }

        List<ContentDocument> docsToDelete = [
            SELECT Id 
            FROM ContentDocument 
            WHERE Id IN :docToDeleteIds
        ];

        delete docsToDelete;
    }
    
    private String extractCustomerNameFromPath(String path) {
        if (String.isBlank(path)) return null;
        
        List<String> parts = path.split('/');
        Integer indexCompany = parts.indexOf('Company Folder');
        Integer indexCommercial = parts.indexOf('Commercial Bids');
        
        if (indexCompany != -1 && indexCompany + 1 < parts.size()) {
            return parts[indexCompany + 1];
        } else if (indexCommercial != -1 && indexCommercial + 2 < parts.size()) {
            return parts[indexCommercial + 2];
        }
        
        return null;
    }
    
    // Static methods remain the same...
    public static void startProcessing(String year) {
        System.enqueueJob(new SharePointProxyContentVersionService(year));
    }
    
    public static void startProcessing(String year, Integer batchSize) {
        System.enqueueJob(new SharePointProxyContentVersionService(year, 0, batchSize));
    }
}