public with sharing class InvoiceQuickBooksProposalLinker {
    private List<Invoice__c> newList;

    public InvoiceQuickBooksProposalLinker(List<Invoice__c> newList) {
        this.newList = newList;
        linkInvoices();
    }

    private void linkInvoices() {
        try {
            Set<String> proposalQuickBooksIds = new Set<String>();
            Set<String> workOrderQuickBooksIds = new Set<String>();
            Set<String> proposalReferenceNumbers = new Set<String>();
            List<String> accountNames = new List<String>();

            Map<String, Id> quickBooksIdToOpportunityId = new Map<String, Id>();
            Map<String, Id> referenceNumberToOpportunityId = new Map<String, Id>();
            Map<String, Id> quickBooksIdToWorkOrderId = new Map<String, Id>();

            for (Invoice__c invoice : newList) {
                // Safe account name extraction
                if (String.isNotBlank(invoice.Name) && invoice.Name.contains(':')) {
                    accountNames.add(invoice.Name.split(':')[0].trim());
                }
                
                if (String.isNotBlank(invoice.Proposal_QuickBooks_Id__c)) {
                    proposalQuickBooksIds.add(invoice.Proposal_QuickBooks_Id__c);
                }
                
                if (String.isNotBlank(invoice.WorkOrder_QuickBooks_Id__c)) {
                    workOrderQuickBooksIds.add(invoice.WorkOrder_QuickBooks_Id__c);
                }
                
                // IMPROVED MEMO__C PROCESSING
                if (String.isNotBlank(invoice.Memo__c)) {
                    String referenceNumber = extractReferenceNumber(invoice.Memo__c);
                    if (String.isNotBlank(referenceNumber)) {
                        proposalReferenceNumbers.add(referenceNumber);
                    }
                }
            }

            // Get accounts
            List<Account> accounts = [SELECT Id, Name FROM Account WHERE Name IN :accountNames LIMIT 10000];
            Map<String, Id> nameToAccount = new Map<String, Id>();
            for (Account a : accounts) {
                nameToAccount.put(a.Name, a.Id);
            }

            // Opportunity lookup logic
            if (!proposalQuickBooksIds.isEmpty()) {
                for (Opportunity opp : [
                    SELECT Id, QuickBooks_Id__c, Reference_Number__c 
                    FROM Opportunity 
                    WHERE QuickBooks_Id__c IN :proposalQuickBooksIds
                    LIMIT 10000
                ]) {
                    quickBooksIdToOpportunityId.put(opp.QuickBooks_Id__c, opp.Id);
                    if (String.isNotBlank(opp.Reference_Number__c)) {
                        referenceNumberToOpportunityId.put(opp.Reference_Number__c, opp.Id);
                    }
                }
            }
            
            // ALWAYS search by reference numbers, even if QuickBooks Ids exist
            if (!proposalReferenceNumbers.isEmpty()) {
                for (Opportunity opp : [
                    SELECT Id, Reference_Number__c 
                    FROM Opportunity 
                    WHERE Reference_Number__c IN :proposalReferenceNumbers
                    LIMIT 10000
                ]) {
                    referenceNumberToOpportunityId.put(opp.Reference_Number__c, opp.Id);
                }
            }

            // Get Work Orders
            if (!workOrderQuickBooksIds.isEmpty()) {
                for (WorkOrder wo : [
                    SELECT Id, AccountId, Quick_Books_Id__c 
                    FROM WorkOrder  
                    WHERE Quick_Books_Id__c IN :workOrderQuickBooksIds AND AccountId != null
                    LIMIT 10000
                ]) {
                    quickBooksIdToWorkOrderId.put(wo.Quick_Books_Id__c, wo.Id);
                }
            }

            // Process invoices
            for (Invoice__c invoice : newList) {
                // Work Order assignment
                if (String.isNotBlank(invoice.WorkOrder_QuickBooks_Id__c) && 
                    quickBooksIdToWorkOrderId.containsKey(invoice.WorkOrder_QuickBooks_Id__c)) {
                    invoice.Work_Order__c = quickBooksIdToWorkOrderId.get(invoice.WorkOrder_QuickBooks_Id__c);
                }

                // Proposal assignment
                if (String.isNotBlank(invoice.Proposal_QuickBooks_Id__c) &&
                    quickBooksIdToOpportunityId.containsKey(invoice.Proposal_QuickBooks_Id__c)) {
                    invoice.Proposal__c = quickBooksIdToOpportunityId.get(invoice.Proposal_QuickBooks_Id__c);
                } else if (String.isNotBlank(invoice.Memo__c)) {
                    String referenceNumber = extractReferenceNumber(invoice.Memo__c);
                    if (String.isNotBlank(referenceNumber) && 
                        referenceNumberToOpportunityId.containsKey(referenceNumber)) {
                        invoice.Proposal__c = referenceNumberToOpportunityId.get(referenceNumber);
                    }
                }

                // Customer assignment
                if (String.isNotBlank(invoice.Name)) {
                    String accountName = extractAccountName(invoice.Name);
                    if (String.isNotBlank(accountName) && nameToAccount.containsKey(accountName)) {
                        invoice.Customer__c = nameToAccount.get(accountName);
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug('Error in InvoiceQuickBooksProposalLinker: ' + e.getMessage() + 
                        ' StackTrace: ' + e.getStackTraceString());
        }
    }

    /**
     * Safe reference number extraction from Memo__c
     */
    private String extractReferenceNumber(String memo) {
        if (String.isBlank(memo)) return null;
        
        try {
            // Look for patterns: "Estimate 12345:", "12345:", etc.
            Pattern pattern = Pattern.compile('(?:Estimate)?\\s*(\\d+)(?::|\\s|$)');
            Matcher matcher = pattern.matcher(memo);
            
            if (matcher.find()) {
                return matcher.group(1);
            }
        } catch (Exception e) {
            System.debug('Error extracting reference number from memo: ' + memo + ' - ' + e.getMessage());
        }
        
        return null;
    }

    /**
     * Safe account name extraction from Name field
     */
    private String extractAccountName(String invoiceName) {
        if (String.isBlank(invoiceName)) return null;
        
        try {
            if (invoiceName.contains(':')) {
                return invoiceName.split(':')[0].trim();
            } else if (invoiceName.contains('Contract') || invoiceName.contains('Service')) {
                // Logic for other formats if needed
                return invoiceName;
            }
        } catch (Exception e) {
            System.debug('Error extracting account name from: ' + invoiceName + ' - ' + e.getMessage());
        }
        
        return null;
    }
}