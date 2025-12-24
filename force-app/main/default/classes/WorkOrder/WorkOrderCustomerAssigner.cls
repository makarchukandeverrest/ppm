public with sharing class WorkOrderCustomerAssigner {
    private List<WorkOrder> newList;

    public WorkOrderCustomerAssigner(List<WorkOrder> newList) {
        System.debug('WorkOrderCustomerAssigner ');
        this.newList = newList;
        linkCustomers();
        linkProposal();
    }

    private void linkCustomers() {
        List<String> accountNames = new List<String>();
        for (WorkOrder w : newList) {
            if(String.isNotBlank(w.Quick_Books_Customer_Name__c)) {
                accountNames.add(w.Quick_Books_Customer_Name__c.split(':')[0].trim());
            }
        }
        List<Account> accounts = new List<Account>();

        if(!accountNames.isEmpty()){
            accounts = [SELECT Id, Name FROM Account WHERE Name IN :accountNames LIMIT 10000];
        }

        if(!accounts.isEmpty()){
            Map<String, Id> nameToAccount = new Map<String, Id>();
            for(Account a : accounts){
                nameToAccount.put(a.Name, a.Id);
            }

            for(WorkOrder w :newList){
                if(w.AccountId == null && nameToAccount.containsKey(w.Quick_Books_Customer_Name__c.split(':')[0].trim())){
                    w.AccountId = nameToAccount.get(w.Quick_Books_Customer_Name__c.split(':')[0].trim());
                }
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
        System.debug('proposalReferenceNumbers '+proposalReferenceNumbers);
        List<Opportunity> proposals = new List<Opportunity>();
        Map<String, Id> referenceNumberToOpportunityId = new Map<String, Id>();
        if(!proposalReferenceNumbers.isEmpty()){
            proposals = [SELECT Id, Reference_Number__c FROM Opportunity WHERE Reference_Number__c IN :proposalReferenceNumbers LIMIT 10000];
        }
        System.debug('proposals '+proposals);
        if(!proposals.isEmpty()){
            for(Opportunity o : proposals){
                referenceNumberToOpportunityId.put(o.Reference_Number__c, o.Id);
            }
        }
        System.debug('referenceNumberToOpportunityId '+referenceNumberToOpportunityId);
        if(!referenceNumberToOpportunityId.keySet().isEmpty()){
            for(WorkOrder w :newList){
                if(String.isNotBlank(w.Quickbooks_Memo__c) && referenceNumberToOpportunityId.containsKey(w.Quickbooks_Memo__c.split(' ')[1].replace(':',''))){
                    w.Proposal__c = referenceNumberToOpportunityId.get(w.Quickbooks_Memo__c.split(' ')[1].replace(':',''));
                }
            }
        }
    }
}