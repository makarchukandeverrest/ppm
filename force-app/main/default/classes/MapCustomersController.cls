public with sharing class MapCustomersController {
    @AuraEnabled(cacheable=true)
    public static List<Account> getCustomers(){
            return [
                SELECT Id, Name, BillingStreet, BillingCity, BillingState,
                       BillingPostalCode, BillingCountry, BillingLatitude, BillingLongitude,
                       Contract_Periods__c, County__c, Regional_Manager__r.Name, Email__c,
                       Current_Customer__c, Recent_Contract_Bid__c,
                       Recent_Contract_Bid__r.Name, Recent_Contract_Bid__r.Stage__c,
                       Recent_Contract_Bid__r.Contract_Start_Date__c, Recent_Contract_Bid__r.Contract_End_Date__c,
                       Recent_Contract_Bid__r.Due_Date__c, Recent_Contract_Bid__r.Contract_Year__c,
                       Recent_Contract_Bid__r.Total__c
                FROM Account
                WHERE BillingPostalCode != null OR (BillingLatitude != null AND BillingLongitude != null)
                ORDER BY Name ASC
            ];
    }
}