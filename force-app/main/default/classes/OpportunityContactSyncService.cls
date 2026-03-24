public inherited sharing class OpportunityContactSyncService {
    public static void assignContacts(List<Opportunity> opps) {
        for(Opportunity opp : opps){
            if(opp.AccountId != null){
                opp.Customer_Billing_Contact__c = opp.Account.Billing_Contact__c;
                opp.Customer_Maintenance_Contact__c = opp.Account.Maintenance_Contact__c;
                opp.Customer_Primary_Contact__c = opp.Account.Primary_Contact__c;
                opp.Customer_Secondary_Contact__c = opp.Account.Secondary_Contact__c;
            }
        }
    }

    public static void assignContacts(List<Account> accs) {
        Map<Id, Account> accMap = new Map<Id, Account>(accs);
        List<Opportunity> opps = [
            SELECT Id, AccountId, Customer_Billing_Contact__c, Customer_Maintenance_Contact__c, Customer_Primary_Contact__c, Customer_Secondary_Contact__c
            FROM Opportunity
            WHERE AccountId IN :accMap.keySet() AND IsClosed = false
        ];
        
        for(Opportunity opp : opps){
            if(opp.AccountId != null && accMap.containsKey(opp.AccountId)){
                Account acc = accMap.get(opp.AccountId);
                opp.Customer_Billing_Contact__c = acc.Billing_Contact__c;
                opp.Customer_Maintenance_Contact__c = acc.Maintenance_Contact__c;
                opp.Customer_Primary_Contact__c = acc.Primary_Contact__c;
                opp.Customer_Secondary_Contact__c = acc.Secondary_Contact__c;
            }
        }
    }
}