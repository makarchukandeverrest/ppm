public with sharing class AccountFilesController {
    
    // DTO for filter options
    public class FilterOptions {
        @AuraEnabled public List<PicklistOption> regionalManagers;
        @AuraEnabled public List<PicklistOption> managementCompanies;
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
        options.managementCompanies = new List<PicklistOption>();
        
        // Get active stages
        StageReferenceSettings__mdt stageReference = StageReferenceSettings__mdt.getInstance('Active_Stages');
        List<String> activeStages = stageReference.Stage_Names__c.split(',');
        
        // First get all customer IDs and Management Companies from active Contract_Bid__c
        Set<Id> customerIds = new Set<Id>();
        Set<Id> managementCompanyIds = new Set<Id>();
        
        for (Contract_Bid__c cb : [
            SELECT Customer__c, Management_Company__c
            FROM Contract_Bid__c 
            WHERE Stage__c IN :activeStages
            AND Customer__c != null
        ]) {
            customerIds.add(cb.Customer__c);
            if (cb.Management_Company__c != null) {
                managementCompanyIds.add(cb.Management_Company__c);
            }
        }
        
        // Get unique Regional Managers from Customers (Accounts)
        Set<Id> regionalManagerIds = new Set<Id>();
        
        for (Account acc : [
            SELECT Id, Regional_Manager__c
            FROM Account 
            WHERE Id IN :customerIds
        ]) {
            if (acc.Regional_Manager__c != null) {
                regionalManagerIds.add(acc.Regional_Manager__c);
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
        
        // Get Management Company names
        for (Management_Company__c mc : [
            SELECT Id, Name
            FROM Management_Company__c
            WHERE Id IN :managementCompanyIds
            ORDER BY Name
        ]) {
            options.managementCompanies.add(new PicklistOption(mc.Name, mc.Id));
        }
        
        return options;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<AccountWithFiles> getAccountsWithFiles(
        String recordId,
        List<Id> recordIds,
        String regionalManagerId,
        String managementCompanyId,
        String customerName,
        String contractYear
    ) {
        List<AccountWithFiles> result = new List<AccountWithFiles>();
        
        // 1. Get active stages for Contract_Bid__c
        Schema.DescribeFieldResult fieldResult = Contract_Bid__c.Stage__c.getDescribe();
        List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
        StageReferenceSettings__mdt stageReference = StageReferenceSettings__mdt.getInstance('Active_Stages');
        List<String> activeStages = stageReference.Stage_Names__c.split(',');

        Set<Id> selectedBidIds = new Set<Id>();
        if (recordIds != null) {
            for (Id bidId : recordIds) {
                if (bidId != null) {
                    selectedBidIds.add(bidId);
                }
            }
        }

        Boolean hasExplicitSelection = !selectedBidIds.isEmpty() || String.isNotBlank(recordId);

        // 2. Build dynamic SOQL query - include all Account filter fields and EBD due date.
        // Explicit list/record selection must not be re-filtered by active stages.
        String soqlQuery = 'SELECT Id, Name, Customer__c, Stage__c, ' +
                           'Customer__r.Name, Customer__r.Email__c, ' +
                           'Customer__r.BillingCountry, ' +
                           'Customer__r.Regional_Manager__c, Customer__r.Regional_Manager__r.Name, ' +
                           'Management_Company__c, Management_Company__r.Name, ' +
                           'EBD_Due_Date__c, Renewal_Client__c ' +
                           'FROM Contract_Bid__c ' +
                           'WHERE Customer__c != null';

        if (!hasExplicitSelection) {
            soqlQuery += ' AND Stage__c IN :activeStages';
        }

        if (!selectedBidIds.isEmpty()) {
            soqlQuery += ' AND Id IN :selectedBidIds';
        } else if (String.isNotBlank(recordId)) {
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

        // 3. Map AccountId -> Contract_Bid__c and filter by Account-level fields.
        // Also map both Account and Contract Bid Ids so files can be loaded from either record.
        Map<Id, Contract_Bid__c> contractsByAccount = new Map<Id, Contract_Bid__c>();
        Map<Id, Id> linkedEntityToAccountId = new Map<Id, Id>();
        Set<Id> contractBidIds = new Set<Id>();
        for (Contract_Bid__c contract : contractMap.values()) {
            // Apply Regional Manager filter (from Account)
            if (String.isNotBlank(regionalManagerId)) {
                if (contract.Customer__r.Regional_Manager__c != regionalManagerId) {
                    continue;
                }
            }
            
            // Apply Management Company filter (from Contract Bid)
            if (String.isNotBlank(managementCompanyId)) {
                if (contract.Management_Company__c != managementCompanyId) {
                    continue;
                }
            }
            
            contractsByAccount.put(contract.Customer__c, contract);
            linkedEntityToAccountId.put(contract.Customer__c, contract.Customer__c);
            linkedEntityToAccountId.put(contract.Id, contract.Customer__c);
            if (contract.Id != null) {
                contractBidIds.add(contract.Id);
            }
        }

        // 4. Check if there are accounts to process
        if (linkedEntityToAccountId.isEmpty()) {
            // Return empty list instead of throwing an error
            return new List<AccountWithFiles>();
        }

        // 5. Get document links for Accounts and related Contract Bids
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :linkedEntityToAccountId.keySet()
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

        // 7. Map DocumentId -> AccountId (Contract Bid files resolve to Customer__c)
        Map<Id, Id> docIdToAccountIdMap = new Map<Id, Id>();
        for (ContentDocumentLink link : links) {
            Id accountId = linkedEntityToAccountId.get(link.LinkedEntityId);
            if (accountId != null) {
                docIdToAccountIdMap.put(link.ContentDocumentId, accountId);
            }
        }

        // 8. Get ContentVersions for the documents
        Set<Id> latestVersionIds = new Set<Id>();
        for (ContentDocument doc : docMap.values()) {
            if (doc.LatestPublishedVersionId != null) {
                latestVersionIds.add(doc.LatestPublishedVersionId);
            }
        }

        Set<Id> bidDocIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            if (contractBidIds.contains(link.LinkedEntityId)) {
                bidDocIds.add(link.ContentDocumentId);
            }
        }

        String contractYearFilter = String.isNotBlank(contractYear)
            ? contractYear.trim()
            : null;

        List<ContentVersion> versions = latestVersionIds.isEmpty()
            ? new List<ContentVersion>()
            : [
                SELECT Id, Title, ContentDocumentId, FileExtension, To_Sent__c
                FROM ContentVersion
                WHERE Id IN :latestVersionIds
                    AND FileExtension IN ('pdf', 'doc', 'docx')
                    AND Title LIKE '%Contract%'
                    AND (NOT Title LIKE '%Signed Contract%')
                    AND (NOT Title LIKE '%Completed%')
              ];

        List<ContentVersion> filteredVersions = new List<ContentVersion>();

        for (ContentVersion cv : versions) {
            if (cv.Title == null) {
                continue;
            }
            if (
                cv.Title.contains('Welcome Letter')
                || cv.Title.contains('Bid Worksheet')
                || cv.Title.contains('Signed Contract')
                || cv.Title.contains('Completed')
            ) {
                continue;
            }

            Boolean fromContractBid = bidDocIds.contains(cv.ContentDocumentId);
            if (
                !fromContractBid
                && String.isNotBlank(contractYearFilter)
                && !cv.Title.contains(contractYearFilter)
            ) {
                continue;
            }

            filteredVersions.add(cv);
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
            
            if (accountId != null) {
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
                awf.managementCompanyName = contract.Management_Company__r != null
                    ? contract.Management_Company__r.Name
                    : null;
                
                result.add(awf);
            }
        }

        return result;
    }
}