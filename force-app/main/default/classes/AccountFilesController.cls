public with sharing class AccountFilesController {
    
    @AuraEnabled(cacheable=true)
    public static List<AccountWithFiles> getAccountsWithFiles(String recordId) {
        List<AccountWithFiles> result = new List<AccountWithFiles>();
        
        // 1. Get active stages for Contract_Bid__c
        Schema.DescribeFieldResult fieldResult = Contract_Bid__c.Stage__c.getDescribe();
        List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
        StageReferenceSettings__mdt stageReference = StageReferenceSettings__mdt.getInstance('Active_Stages');
        List<String> activeStages = stageReference.Stage_Names__c.split(',');

        // 2. Build dynamic SOQL query based on recordId
        String soqlQuery = 'SELECT Id, Name, Customer__c, Stage__c, Customer__r.Name, Customer__r.Email__c, Renewal_Client__c ' +
                          'FROM Contract_Bid__c ' +
                          'WHERE Stage__c IN :activeStages';
        
        // Add filter if recordId is provided
        if (String.isNotBlank(recordId)) {
            soqlQuery += ' AND Id = :recordId';
        }

        Map<Id, Contract_Bid__c> contractMap = new Map<Id, Contract_Bid__c>((List<Contract_Bid__c>)Database.query(soqlQuery));

        // 3. Map AccountId -> Contract_Bid__c
        Map<Id, Contract_Bid__c> contractsByAccount = new Map<Id, Contract_Bid__c>();
        for (Contract_Bid__c contract : contractMap.values()) {
            contractsByAccount.put(contract.Customer__c, contract);
        }

        // 4. Check if there are accounts to process
        if (contractsByAccount.isEmpty()) {
            // Return empty list instead of throwing an error
            return new List<AccountWithFiles>();
        }

        // 5. Get document links for the contracts’ Accounts
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :contractsByAccount.keySet()
        ];

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            docIds.add(link.ContentDocumentId);
        }

        // 6. Get ContentDocument details
        Map<Id, ContentDocument> docMap = new Map<Id, ContentDocument>([
            SELECT Id, Title, LatestPublishedVersionId 
            FROM ContentDocument 
            WHERE Id IN :docIds
        ]);

        // 7. Map DocumentId -> AccountId
        Map<Id, Id> docIdToAccountIdMap = new Map<Id, Id>();
        for (ContentDocumentLink link : links) {
            Id accountId = link.LinkedEntityId;
            Id docId = link.ContentDocumentId;
            docIdToAccountIdMap.put(docId, accountId);
        }

        // 8. Get ContentVersions for the documents
        List<ContentVersion> versions = [
            SELECT Id, Title, VersionData, ContentDocumentId, FileExtension, To_Sent__c
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds 
                AND (NOT(Title LIKE '%Welcome Letter%'))
                AND FileType != 'SNOTE'
        ];

        // 9. Map DocumentId -> ContentVersion
        Map<Id, ContentVersion> docIdToVersion = new Map<Id, ContentVersion>();
        for (ContentVersion ver : versions) {
            docIdToVersion.put(ver.ContentDocumentId, ver);
        }

        // 10. Group files by Account
        Map<Id, List<ContentVersion>> accountIdToFiles = new Map<Id, List<ContentVersion>>();
        for (Id docId : docIdToVersion.keySet()) {
            Id accountId = docIdToAccountIdMap.get(docId);
            
            if (accountId != null && contractsByAccount.containsKey(accountId)) {
                if (!accountIdToFiles.containsKey(accountId)) {
                    accountIdToFiles.put(accountId, new List<ContentVersion>());
                }
                accountIdToFiles.get(accountId).add(docIdToVersion.get(docId));
            }
        }

        // 11. Build the result
        for (Id accountId : accountIdToFiles.keySet()) {
            Contract_Bid__c contract = contractsByAccount.get(accountId);
            List<FileWrapper> fileWrappers = new List<FileWrapper>();

            for (ContentVersion cv : accountIdToFiles.get(accountId)) {
                if(cv.VersionData != null){ //check if real file - not SharePoint link
                    fileWrappers.add(new FileWrapper(cv));
                }
            }
            if(!fileWrappers.isEmpty()){ // if files exist for the account
                result.add(new AccountWithFiles(
                    accountId,
                    contract.Customer__r.Name,
                    contract.Customer__r.Email__c,
                    contract,
                    fileWrappers,
                    false //as deafult New Client checkbox on Contract Sender should be unchecked
                ));
            }
        }

        return result;
    }
}