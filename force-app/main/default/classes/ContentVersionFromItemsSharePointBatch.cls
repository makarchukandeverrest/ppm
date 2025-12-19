public class ContentVersionFromItemsSharePointBatch implements Database.Batchable<Items_SharePoint__x>, Database.AllowsCallouts {

    private DateTime cutoff;

    public ContentVersionFromItemsSharePointBatch() {
        this.cutoff = System.now().addMinutes(-20); //addMinutes(-6)
    }

    public Iterable<Items_SharePoint__x> start(Database.BatchableContext bc) {
        return [
            SELECT Id, Name__c, MimeType__c, IsFolder__c, CreationDate__c,UniqueId__c, Path__c
            FROM Items_SharePoint__x
            WHERE CreationDate__c >= :cutoff
            AND IsFolder__c = false AND MimeType__c = 'application/pdf'
        ];
    }

    public void execute(Database.BatchableContext bc, List<Items_SharePoint__x> scope) {
        if (scope.isEmpty()) return;

        // Map accounts to items (if any). Missing mappings are allowed so that
        // ContentVersions are still created even when no Account is found.
        Map<Id, List<Items_SharePoint__x>> recordsToItemsMap = buildAccountMapping(scope);
        Map<Id, Id> itemToAccount = new Map<Id, Id>();
        for (Id accId : recordsToItemsMap.keySet()) {
            for (Items_SharePoint__x item : recordsToItemsMap.get(accId)) {
                // Use the first matched account for linking
                if (!itemToAccount.containsKey(item.Id)) {
                    itemToAccount.put(item.Id, accId);
                }
            }
        }

        List<Id> cvsToInsert = new List<Id>();
        Map<Id, Id> cvToAccount = new Map<Id, Id>();
        
        // Download & prepare ContentVersions for all items (even without account match)
        for (Items_SharePoint__x item : scope) {
            try {
                Blob fileBody = downloadFile(EncodingUtil.urlEncode(item.UniqueId__c, 'UTF-8'));
                String fileName = getFileName(item.Name__c, item.MimeType__c);

                ContentVersion cv = new ContentVersion(
                    Title = fileName,
                    PathOnClient = '/' + fileName,
                    VersionData = fileBody,
                    To_Sent__c = true,
                    DocuSign_Envelope_Status__c = 'Start',
                    SharePoint_External_Id__c = item.UniqueId__c
                );

                insert cv;
                fileBody = null; // Clear Blob to free memory
                cvsToInsert.add(cv.Id);

                Id linkedAccountId = itemToAccount.get(item.Id);
                if (linkedAccountId != null) {
                    cvToAccount.put(cv.Id, linkedAccountId);
                }

            } catch (Exception e) {
                System.debug('Error downloading item ' + item.Id + ': ' + e.getMessage());
            }
        }

        if (!cvsToInsert.isEmpty()) {

            // Retrieve ContentDocumentIds
            Map<Id, ContentVersion> cvMap = new Map<Id, ContentVersion>(
                [SELECT Id, Title, ContentDocumentId FROM ContentVersion WHERE Id IN :cvsToInsert]
            );

            List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
            for (ContentVersion cv : cvMap.values()) {
                Id accId = cvToAccount.get(cv.Id);
                if (accId != null) {
                    linksToInsert.add(new ContentDocumentLink(
                        ContentDocumentId = cv.ContentDocumentId,
                        LinkedEntityId = accId,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    ));
                }
            }

            if (!linksToInsert.isEmpty()) {
                insert linksToInsert;
            }
        }

        // Mark processed
        List<Processed_SharePoint_Item__c> processed = new List<Processed_SharePoint_Item__c>();
        for (Items_SharePoint__x item : scope) {
            processed.add(new Processed_SharePoint_Item__c(
                External_Item_Id__c = item.Id
            ));
        }
        upsert processed External_Item_Id__c;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Batch processing complete.');
    }

    // === Helper Methods ===
    private static Map<Id, List<Items_SharePoint__x>> buildAccountMapping(List<Items_SharePoint__x> items) {
        Set<String> cleanNames = new Set<String>();
        for (Items_SharePoint__x item : items) {
            if (String.isNotBlank(item.Path__c) 
                && String.isNotBlank(item.Path__c.split('/')[item.Path__c.split('/').size() - 2])) {
                cleanNames.add(item.Path__c.split('/')[item.Path__c.split('/').size() - 2]);
            }
        }

        if (cleanNames.isEmpty()) return new Map<Id, List<Items_SharePoint__x>>();

        List<String> likeConditions = new List<String>();
        for (String name : cleanNames) {
            likeConditions.add('Name LIKE \'%' + String.escapeSingleQuotes(name) + '%\'');
        }

        String query = 'SELECT Id, Name FROM Account';
        if (!likeConditions.isEmpty()) {
            query += ' WHERE ' + String.join(likeConditions, ' OR ');
        }
        System.debug(query);
        List<Account> matchedAccounts = Database.query(query);
        Map<String, List<Account>> accountsByName = new Map<String, List<Account>>();
        for (Account acc : matchedAccounts) {
            if (!accountsByName.containsKey(acc.Name)) {
                accountsByName.put(acc.Name, new List<Account>());
            }
            accountsByName.get(acc.Name).add(acc);
        }

        Map<Id, List<Items_SharePoint__x>> result = new Map<Id, List<Items_SharePoint__x>>();
        for (Items_SharePoint__x item : items) {
            String url = item.Path__c;
            List<String> parts = url.split('/');
            String folderName = parts[parts.size() - 2];
            String normalizedFolderName = normalizeString(folderName);

            for (String accountKey : accountsByName.keySet()) {
                String normalizedKey = normalizeString(accountKey);
                if (normalizedKey.contains(normalizedFolderName) ||
                    normalizedFolderName.contains(normalizedKey)) {
                    for (Account acc : accountsByName.get(accountKey)) {
                        if (!result.containsKey(acc.Id)) {
                            result.put(acc.Id, new List<Items_SharePoint__x>());
                        }
                        result.get(acc.Id).add(item);
                    }
                }
            }
        }
        return result;
    }

    private static String getFileName(String baseName, String mimeType) {
        String ext = getExtensionFromMimeType(mimeType);
        return (!String.isEmpty(ext) && !baseName.toLowerCase().endsWith(ext)) 
            ? baseName + ext 
            : baseName;
    }

    private static Blob downloadFile(String fileGUID) {
        Http http = new Http();
        String endpoint = 'callout:SP_Credential/sites/Salesforce/_api/web/GetFileById(\'' + fileGUID + '\')/$value';
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json;odata=verbose');
        HttpResponse res1 = http.send(req);

        if (res1.getStatusCode() != 200) {
            throw new CalloutException('Request failed: ' + res1.getStatusCode());
        }
        return res1.getBodyAsBlob();
    }

    public static String getExtensionFromMimeType(String mimeType) {
        if (mimeType == null) return '';
        Map<String, String> mimeToExt = new Map<String, String>{
            'application/pdf' => '.pdf',
            'text/plain' => '.txt',
            'application/msword' => '.doc',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => '.docx',
            'image/jpeg' => '.jpg',
            'image/png' => '.png',
            'application/octet-stream' => ''
        };
        String ext = mimeToExt.get(mimeType != null ? mimeType.toLowerCase() : null);
        return ext != null ? ext : '';
    }

    private static String normalizeString(String input) {
        if (input == null) return '';
        
        return input.toLowerCase()
                   .replaceAll('[^a-z0-9]', '')  // Remove non-alphanumeric
                   .trim();
    }
}