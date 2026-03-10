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
}