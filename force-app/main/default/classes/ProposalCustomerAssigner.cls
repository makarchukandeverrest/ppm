public inherited sharing class ProposalCustomerAssigner {
    public static void assignCustomer(List<Opportunity> opps){
        Set<String> accountNames = new Set<String>();
        for(Opportunity opp : opps){
            if(opp.Name != null && opp.Account_QuickBooks_Id__c == null){
                accountNames.add(opp.Name.substringBefore(':').trim());
            }
        }

        List<Account> accounts = new List<Account>([SELECT Id, Name FROM Account WHERE Name IN :accountNames]);
        Map<String, Id> accountMap = new Map<String, Id>();
        for (Account a : accounts) {
            accountMap.put(a.Name, a.Id);
        }

        for(Opportunity opp : opps){
            if(opp.Name != null && opp.Account_QuickBooks_Id__c == null){
                opp.AccountId = accountMap.get(opp.Name.substringBefore(':').trim());
            }
            if(opp.AccountId != null){
                opp.Customer_Billing_Contact__c = opp.Account.Billing_Contact__c;
                opp.Customer_Maintenance_Contact__c = opp.Account.Maintenance_Contact__c;
                opp.Customer_Primary_Contact__c = opp.Account.Primary_Contact__c;
                opp.Customer_Secondary_Contact__c = opp.Account.Secondary_Contact__c;
            }
        }
        

    }
}