public with sharing class MapCustomersController {
    public class CustomerMapRow {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;

        @AuraEnabled public String billingStreet;
        @AuraEnabled public String billingCity;
        @AuraEnabled public String billingState;
        @AuraEnabled public String billingPostalCode;
        @AuraEnabled public String billingCountry;
        @AuraEnabled public Decimal billingLatitude;
        @AuraEnabled public Decimal billingLongitude;

        @AuraEnabled public String contractPeriods;
        @AuraEnabled public String county;
        @AuraEnabled public String email;
        @AuraEnabled public String regionalManagerName;
        @AuraEnabled public Boolean currentCustomer;

        // Contract Bid fields (Recent or Latest-by-start-date)
        @AuraEnabled public Id contractBidId;
        @AuraEnabled public String contractBidName;
        @AuraEnabled public String contractBidStage;
        @AuraEnabled public Date contractStartDate;
        @AuraEnabled public Date contractEndDate;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String contractYear;
        @AuraEnabled public Decimal total;
    }

    private static CustomerMapRow toRow(Account a, Contract_Bid__c bid) {
        CustomerMapRow row = new CustomerMapRow();

        row.accountId = a.Id;
        row.name = a.Name;

        row.billingStreet = a.BillingStreet;
        row.billingCity = a.BillingCity;
        row.billingState = a.BillingState;
        row.billingPostalCode = a.BillingPostalCode;
        row.billingCountry = a.BillingCountry;
        row.billingLatitude = a.BillingLatitude;
        row.billingLongitude = a.BillingLongitude;

        row.contractPeriods = a.Contract_Periods__c;
        row.county = a.County__c;
        row.email = a.Email__c;
        row.currentCustomer = a.Current_Customer__c;
        row.regionalManagerName = (a.Regional_Manager__r != null) ? a.Regional_Manager__r.Name : null;

        if (bid != null) {
            row.contractBidId = bid.Id;
            row.contractBidName = bid.Name;
            row.contractBidStage = bid.Stage__c;
            row.contractStartDate = bid.Contract_Start_Date__c;
            row.contractEndDate = bid.Contract_End_Date__c;
            row.dueDate = bid.Due_Date__c;
            row.contractYear = bid.Contract_Year__c;
            row.total = bid.Total__c;
        }

        return row;
    }

    @AuraEnabled(cacheable=true)
    public static List<CustomerMapRow> getCustomers() {
        List<Account> accounts = [
            SELECT Id, Name, BillingStreet, BillingCity, BillingState,
                   BillingPostalCode, BillingCountry, BillingLatitude, BillingLongitude,
                   Contract_Periods__c, County__c, Regional_Manager__r.Name, Email__c,
                   Current_Customer__c,
                   Recent_Contract_Bid__r.Id, Recent_Contract_Bid__r.Name, Recent_Contract_Bid__r.Stage__c,
                   Recent_Contract_Bid__r.Contract_Start_Date__c, Recent_Contract_Bid__r.Contract_End_Date__c,
                   Recent_Contract_Bid__r.Due_Date__c, Recent_Contract_Bid__r.Contract_Year__c,
                   Recent_Contract_Bid__r.Total__c
            FROM Account
            WHERE BillingPostalCode != null OR (BillingLatitude != null AND BillingLongitude != null)
            ORDER BY Name ASC
        ];

        List<CustomerMapRow> rows = new List<CustomerMapRow>(accounts.size());
        for (Account a : accounts) {
            rows.add(toRow(a, a.Recent_Contract_Bid__r));
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<CustomerMapRow> getCustomersWithLatestContractBid() {
        List<Account> accounts = [
            SELECT Id, Name, BillingStreet, BillingCity, BillingState,
                   BillingPostalCode, BillingCountry, BillingLatitude, BillingLongitude,
                   Contract_Periods__c, County__c, Regional_Manager__r.Name, Email__c,
                   Current_Customer__c,
                   (
                       SELECT Id, Name, Stage__c, Contract_Start_Date__c, Contract_End_Date__c,
                              Due_Date__c, Contract_Year__c, Total__c
                       FROM Contract_Bids__r
                       ORDER BY Contract_Start_Date__c DESC NULLS LAST, CreatedDate DESC
                       LIMIT 1
                   )
            FROM Account
            WHERE BillingPostalCode != null OR (BillingLatitude != null AND BillingLongitude != null)
            ORDER BY Name ASC
        ];

        List<CustomerMapRow> rows = new List<CustomerMapRow>(accounts.size());
        for (Account a : accounts) {
            Contract_Bid__c latestBid =
                (a.Contract_Bids__r != null && !a.Contract_Bids__r.isEmpty())
                    ? a.Contract_Bids__r[0]
                    : null;
            rows.add(toRow(a, latestBid));
        }
        return rows;
    }
}
