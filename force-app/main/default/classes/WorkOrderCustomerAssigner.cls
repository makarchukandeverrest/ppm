public without sharing class WorkOrderCustomerAssigner {
    private List<WorkOrder> newList;

    public WorkOrderCustomerAssigner(List<WorkOrder> newList) {
        this.newList = newList;
        linkCustomers();
        linkProposal();
    }

    private void linkCustomers() {
        Set<String> accountNames = new Set<String>();
        Set<String> accountQuickBooksIds = new Set<String>();
        for (WorkOrder w : newList) {
            if (String.isBlank(w.Quickbooks_Customer_Id__c)) {
                continue;
            }

            String raw = w.Quickbooks_Customer_Id__c.trim();
            Integer colonIdx = raw.indexOf(':');
            if (colonIdx >= 0) {
                String namePart = raw.substring(0, colonIdx).trim();
                String qbIdPart = raw.substring(colonIdx + 1).trim();
                if (String.isNotBlank(namePart)) {
                    accountNames.add(namePart);
                }
                if (String.isNotBlank(qbIdPart)) {
                    accountQuickBooksIds.add(qbIdPart);
                }
            } else {
                // No ":" means the value might be either a customer name or a QuickBooks Id.
                // We collect it for both lookups, and later prefer QuickBooks Id match.
                if (String.isNotBlank(raw)) {
                    accountNames.add(raw);
                    accountQuickBooksIds.add(raw);
                }
            }
        }

        if (accountNames.isEmpty() && accountQuickBooksIds.isEmpty()) {
            return;
        }

        List<Account> accounts;
        if (!accountNames.isEmpty() && !accountQuickBooksIds.isEmpty()) {
            accounts = [
                SELECT Id, Name, QuickBooks_Id__c
                FROM Account
                WHERE Name IN :accountNames OR QuickBooks_Id__c IN :accountQuickBooksIds
                LIMIT 10000
            ];
        } else if (!accountNames.isEmpty()) {
            accounts = [
                SELECT Id, Name, QuickBooks_Id__c
                FROM Account
                WHERE Name IN :accountNames
                LIMIT 10000
            ];
        } else {
            accounts = [
                SELECT Id, Name, QuickBooks_Id__c
                FROM Account
                WHERE QuickBooks_Id__c IN :accountQuickBooksIds
                LIMIT 10000
            ];
        }

        if (accounts.isEmpty()) {
            return;
        }

        Map<String, Id> nameToAccountId = new Map<String, Id>();
        Map<String, Id> qbIdToAccountId = new Map<String, Id>();
        for (Account a : accounts) {
            if (String.isNotBlank(a.Name)) {
                nameToAccountId.put(a.Name, a.Id);
            }
            if (String.isNotBlank(a.QuickBooks_Id__c)) {
                qbIdToAccountId.put(a.QuickBooks_Id__c, a.Id);
            }
        }

        for (WorkOrder w : newList) {
            if (w.AccountId != null || String.isBlank(w.Quickbooks_Customer_Id__c)) {
                continue;
            }

            String raw = w.Quickbooks_Customer_Id__c.trim();
            Integer colonIdx = raw.indexOf(':');
            String namePart;
            String qbIdPart;
            if (colonIdx >= 0) {
                namePart = raw.substring(0, colonIdx).trim();
                qbIdPart = raw.substring(colonIdx + 1).trim();
            } else {
                // Ambiguous (no ":"): try as QuickBooks Id first, then as Name.
                namePart = raw;
                qbIdPart = raw;
            }

            if (String.isNotBlank(qbIdPart) && qbIdToAccountId.containsKey(qbIdPart)) {
                w.AccountId = qbIdToAccountId.get(qbIdPart);
            } else if (String.isNotBlank(namePart) && nameToAccountId.containsKey(namePart)) {
                w.AccountId = nameToAccountId.get(namePart);
            }
        }
    }

    private void linkProposal(){
        List<String> proposalReferenceNumbers = new List<String>();
        for (WorkOrder w : newList) {
            if(String.isNotBlank(w.Quickbooks_Memo__c)) {
                proposalReferenceNumbers.add(w.Quickbooks_Memo__c.split(' ')[1].replace(':',''));
            }
        }
        List<Opportunity> proposals = new List<Opportunity>();
        Map<String, Id> referenceNumberToOpportunityId = new Map<String, Id>();
        if(!proposalReferenceNumbers.isEmpty()){
            proposals = [SELECT Id, Reference_Number__c FROM Opportunity WHERE Reference_Number__c IN :proposalReferenceNumbers LIMIT 10000];
        }
        if(!proposals.isEmpty()){
            for(Opportunity o : proposals){
                referenceNumberToOpportunityId.put(o.Reference_Number__c, o.Id);
            }
        }
        if(!referenceNumberToOpportunityId.keySet().isEmpty()){
            for(WorkOrder w :newList){
                if(String.isNotBlank(w.Quickbooks_Memo__c) && referenceNumberToOpportunityId.containsKey(w.Quickbooks_Memo__c.split(' ')[1].replace(':',''))){
                    w.Proposal__c = referenceNumberToOpportunityId.get(w.Quickbooks_Memo__c.split(' ')[1].replace(':',''));
                }
            }
        }
    }
}