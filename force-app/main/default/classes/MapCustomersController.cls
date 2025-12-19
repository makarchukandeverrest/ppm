public with sharing class MapCustomersController {
    @AuraEnabled(cacheable=true)
    public static List<Account> getCustomers(){
            return [
                SELECT Id, Name, BillingStreet, BillingCity, BillingState, 
                       BillingPostalCode, BillingCountry, BillingLatitude, BillingLongitude,Contract_Periods__c, County__c, Regional_Manager__r.Name,Email__c  
                FROM Account
                ORDER BY Name ASC
                LIMIT 100
            ];
    }
}