public with sharing class AccountFilesController {
    
    // DTO for filter options
    public class FilterOptions {
        @AuraEnabled public List<PicklistOption> regionalManagers;
        @AuraEnabled public List<PicklistOption> counties;
        @AuraEnabled public List<PicklistOption> supervisors;
    }
    
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions() {
        FilterOptions options = new FilterOptions();
        options.regionalManagers = new List<PicklistOption>();
        options.counties = new List<PicklistOption>();
        options.supervisors = new List<PicklistOption>();
        
        // Get active stages
        StageReferenceSettings__mdt stageReference = StageReferenceSettings__mdt.getInstance('Active_Stages');
        List<String> activeStages = stageReference.Stage_Names__c.split(',');
        
        // First get all customer IDs from active Contract_Bid__c
        Set<Id> customerIds = new Set<Id>();
        
        for (Contract_Bid__c cb : [
            SELECT Customer__c 
            FROM Contract_Bid__c 
            WHERE Stage__c IN :activeStages
            AND Customer__c != null
        ]) {
            customerIds.add(cb.Customer__c);
        }
        
        // Get unique Regional Managers, Counties, and Supervisors from Customers (Accounts)
        Set<Id> regionalManagerIds = new Set<Id>();
        Set<Id> supervisorIds = new Set<Id>();
        Set<String> countyValues = new Set<String>();
        
        for (Account acc : [
            SELECT Id, BillingCountry, Regional_Manager__c, Supervisor_Lookup__c, County__c 
            FROM Account 
            WHERE Id IN :customerIds
        ]) {
            // Regional Manager from Account
            if (acc.Regional_Manager__c != null) {
                regionalManagerIds.add(acc.Regional_Manager__c);
            }
            // Supervisor from Account
            if (acc.Supervisor_Lookup__c != null) {
                supervisorIds.add(acc.Supervisor_Lookup__c);
            }
            // County__c from Account
            if (String.isNotBlank(acc.County__c)) {
                countyValues.add(acc.County__c);
            }
        }
        
        // Get Regional Manager names
        for (User u : [
            SELECT Id, Name 
            FROM User 
            WHERE Id IN :regionalManagerIds 
            ORDER BY Name
        ]) {
            options.regionalManagers.add(new PicklistOption(u.Name, u.Id));
        }
        
        // Get Supervisor names
        for (Supervisor__c sup : [
            SELECT Id, Name, Last_Name__c
            FROM Supervisor__c
            WHERE Id IN :supervisorIds
            ORDER BY Name
        ]) {
            String label = sup.Name;
            if (String.isNotBlank(sup.Last_Name__c)) {
                label += ' ' + sup.Last_Name__c;
            }
            options.supervisors.add(new PicklistOption(label, sup.Id));
        }
        
        // Build County options (label = value)
        for (String c : countyValues) {
            options.counties.add(new PicklistOption(c, c));
        }
        
        return options;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<AccountWithFiles> getAccountsWithFiles(
        String recordId,
        String regionalManagerId,
        String county,
        String customerName,
        String supervisorId,
        String contractYear
    ) {
        List<AccountWithFiles> result = new List<AccountWithFiles>();
        
        // 1. Get active stages for Contract_Bid__c
        Schema.DescribeFieldResult fieldResult = Contract_Bid__c.Stage__c.getDescribe();
        List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
        StageReferenceSettings__mdt stageReference = StageReferenceSettings__mdt.getInstance('Active_Stages');
        List<String> activeStages = stageReference.Stage_Names__c.split(',');

        // 2. Build dynamic SOQL query - include all Account filter fields and EBD due date
        String soqlQuery = 'SELECT Id, Name, Customer__c, Stage__c, ' +
                           'Customer__r.Name, Customer__r.Email__c, ' +
                           'Customer__r.BillingCountry, ' +
                           'Customer__r.Supervisor_Lookup__c, Customer__r.Supervisor_Lookup__r.Name, ' +
                           'Customer__r.Regional_Manager__c, Customer__r.Regional_Manager__r.Name, ' +
                           'Customer__r.County__c, EBD_Due_Date__c, ' +
                           'Renewal_Client__c ' +
                           'FROM Contract_Bid__c ' +
                           'WHERE Stage__c IN :activeStages';
        
        // Add filter if recordId is provided
        if (String.isNotBlank(recordId)) {
            soqlQuery += ' AND Id = :recordId';
        }
        
        // Customer Name filter (partial match on Account Name)
        String customerNameLike = null;
        if (String.isNotBlank(customerName)) {
            customerNameLike = '%' + String.escapeSingleQuotes(customerName) + '%';
            soqlQuery += ' AND Customer__r.Name LIKE :customerNameLike';
        }
        
        System.debug('SOQL Query: ' + soqlQuery);
        Map<Id, Contract_Bid__c> contractMap = new Map<Id, Contract_Bid__c>(
            (List<Contract_Bid__c>)Database.query(soqlQuery)
        );

        // 3. Map AccountId -> Contract_Bid__c and filter by Account-level fields
        Map<Id, Contract_Bid__c> contractsByAccount = new Map<Id, Contract_Bid__c>();
        for (Contract_Bid__c contract : contractMap.values()) {
            // Apply Regional Manager filter (from Account)
            if (String.isNotBlank(regionalManagerId)) {
                if (contract.Customer__r.Regional_Manager__c != regionalManagerId) {
                    continue;
                }
            }
            
            // Apply County filter (County__c on Account)
            if (String.isNotBlank(county)) {
                if (contract.Customer__r.County__c != county) {
                    continue;
                }
            }
            
            // Apply Supervisor filter (from Account)
            if (String.isNotBlank(supervisorId)) {
                if (contract.Customer__r.Supervisor_Lookup__c != supervisorId) {
                    continue;
                }
            }
            
            contractsByAccount.put(contract.Customer__c, contract);
        }

        // 4. Check if there are accounts to process
        if (contractsByAccount.isEmpty()) {
            // Return empty list instead of throwing an error
            return new List<AccountWithFiles>();
        }

        // 5. Get document links for the contracts' Accounts
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
        Set<Id> latestVersionIds = new Set<Id>();
        for (ContentDocument doc : docMap.values()) {
            if (doc.LatestPublishedVersionId != null) {
                latestVersionIds.add(doc.LatestPublishedVersionId);
            }
        }

        String contractYearFilter = String.isNotBlank(contractYear)
            ? contractYear.trim()
            : String.valueOf(Date.today().year());
        String contractYearLike = '%' + String.escapeSingleQuotes(contractYearFilter) + '%';

        List<ContentVersion> versions = latestVersionIds.isEmpty()
            ? new List<ContentVersion>()
            : [
                SELECT Id, Title, ContentDocumentId, FileExtension, To_Sent__c
                FROM ContentVersion
                WHERE Id IN :latestVersionIds
                    AND FileExtension IN ('pdf', 'doc', 'docx')
                    AND Title LIKE '%Contract%'
                    AND Title LIKE :contractYearLike
                    AND (NOT Title LIKE '%Signed Contract%')
                    AND (NOT Title LIKE '%Completed%')
              ];

        List<ContentVersion> filteredVersions = new List<ContentVersion>();

        for (ContentVersion cv : versions) {
            if (
                cv.Title != null &&
                cv.Title.contains(contractYearFilter) &&
                !cv.Title.contains('Welcome Letter') 
                && !cv.Title.contains('Bid Worksheet') 
                && !cv.Title.contains('Signed Contract') 
                && !cv.Title.contains('Completed')
            ) {
                filteredVersions.add(cv);
            }
        }
        

        versions = filteredVersions;

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

        // 11. Build the result with filter info from Account
        for (Id accountId : accountIdToFiles.keySet()) {
            Contract_Bid__c contract = contractsByAccount.get(accountId);
            List<FileWrapper> fileWrappers = new List<FileWrapper>();

            for (ContentVersion cv : accountIdToFiles.get(accountId)) {
                fileWrappers.add(new FileWrapper(cv));
            }

            if (!fileWrappers.isEmpty()) {
                AccountWithFiles awf = new AccountWithFiles(
                    accountId,
                    contract.Customer__r.Name,
                    contract.Customer__r.Email__c,
                    contract,
                    fileWrappers,
                    false,
                    String.valueOf(contract.EBD_Due_Date__c)
                );
                // Add filter-related fields from Account
                awf.regionalManagerName = contract.Customer__r.Regional_Manager__r != null 
                    ? contract.Customer__r.Regional_Manager__r.Name 
                    : null;
                awf.countyName = contract.Customer__r.County__c;
                awf.supervisorName = contract.Customer__r.Supervisor_Lookup__r != null 
                    ? contract.Customer__r.Supervisor_Lookup__r.Name 
                    : null;
                
                result.add(awf);
            }
        }

        return result;
    }
}