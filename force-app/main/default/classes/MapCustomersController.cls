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
        @AuraEnabled public Date accountContractEndDate;
        @AuraEnabled public Boolean hasCurrentYearBid;

        // Primary Contact (Account)
        @AuraEnabled public Id primaryContactId;
        @AuraEnabled public String primaryContactName;
        @AuraEnabled public String primaryContactPhone;
        @AuraEnabled public String primaryContactEmail;

        // Contract Bid fields (Recent or Latest-by-start-date)
        @AuraEnabled public Id contractBidId;
        @AuraEnabled public String contractBidName;
        @AuraEnabled public String contractBidStage;
        @AuraEnabled public Date contractStartDate;
        @AuraEnabled public Date contractEndDate;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String contractYear;
        @AuraEnabled public Decimal total;

        // Extra Contract Bid fields
        @AuraEnabled public Id managementCompanyId;
        @AuraEnabled public String managementCompanyName;
        @AuraEnabled public String contractBidLabel; // multi-select picklist raw value
        @AuraEnabled public String contractBidColoredLabels; // formula HTML from Colored_Labels__c
        @AuraEnabled public String contractBidDescription; // using Additional_Comments__c for notes

        // Latest Activity (Task/Event) on Account
        @AuraEnabled public String lastActivitySubject;
        @AuraEnabled public Datetime lastActivityDateTime;
        @AuraEnabled public String lastActivityType; // 'Task' or 'Event'
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
        row.accountContractEndDate = a.Contract_End_Date__c;
        row.regionalManagerName = (a.Regional_Manager__r != null) ? a.Regional_Manager__r.Name : null;
        row.primaryContactId = a.Primary_Contact__c;
        row.primaryContactName = (a.Primary_Contact__r != null) ? a.Primary_Contact__r.Name : null;
        row.primaryContactPhone = (a.Primary_Contact__r != null) ? a.Primary_Contact__r.Phone : null;
        row.primaryContactEmail = (a.Primary_Contact__r != null) ? a.Primary_Contact__r.Email : null;

        if (bid != null) {
            row.contractBidId = bid.Id;
            row.contractBidName = bid.Name;
            row.contractBidStage = bid.Stage__c;
            row.contractStartDate = bid.Contract_Start_Date__c;
            row.contractEndDate = bid.Contract_End_Date__c;
            row.dueDate = bid.Due_Date__c;
            row.contractYear = bid.Contract_Year__c;
            row.total = bid.Total__c;

            row.managementCompanyId = bid.Management_Company__c;
            row.managementCompanyName = (bid.Management_Company__r != null) ? bid.Management_Company__r.Name : null;
            row.contractBidLabel = bid.Label__c;
            row.contractBidColoredLabels = bid.Colored_Labels__c;
            row.contractBidDescription = bid.Additional_Comments__c;
        }

        return row;
    }

    private static String getCurrentContractYear() {
        Integer year = Date.today().year();
        Integer startYear = (Date.today().month() >= 7) ? year : year - 1;
        return startYear + '-' + (startYear + 1);
    }

    private static void populateHasCurrentYearBid(List<CustomerMapRow> rows) {
        if (rows.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        for (CustomerMapRow row : rows) {
            if (row == null || row.accountId == null) {
                continue;
            }
            accountIds.add(row.accountId);
        }
        if (accountIds.isEmpty()) {
            return;
        }

        String currentContractYear = getCurrentContractYear();
        Set<Id> accountsWithCurrentYearBid = new Set<Id>();
        for (Contract_Bid__c bid : [
            SELECT Customer__c
            FROM Contract_Bid__c
            WHERE Customer__c IN :accountIds
            AND Contract_Year__c = :currentContractYear
        ]) {
            if (bid.Customer__c != null) {
                accountsWithCurrentYearBid.add(bid.Customer__c);
            }
        }

        for (CustomerMapRow row : rows) {
            if (row == null || row.accountId == null) {
                continue;
            }
            row.hasCurrentYearBid = accountsWithCurrentYearBid.contains(row.accountId);
        }
    }

    private class ActivityPick {
        public String subject;
        public Datetime dt;
        public String typeName;
        public ActivityPick(String subject, Datetime dt, String typeName) {
            this.subject = subject;
            this.dt = dt;
            this.typeName = typeName;
        }
    }

    private static void populateLatestActivity(List<CustomerMapRow> rows) {
        if (rows.isEmpty()) return;

        Set<Id> accountIds = new Set<Id>();
        Map<Id, CustomerMapRow> rowByAccountId = new Map<Id, CustomerMapRow>();
        for (CustomerMapRow row : rows) {
            if (row == null) {
                continue;
            }
            if (row.accountId != null) {
                accountIds.add(row.accountId);
                rowByAccountId.put(row.accountId, row);
            }
        }
        if (accountIds.isEmpty()) return;

        Map<Id, ActivityPick> bestByAccount = new Map<Id, ActivityPick>();

        // Tasks
        for (Task t : [
            SELECT WhatId, Subject, ActivityDate, CreatedDate
            FROM Task
            WHERE WhatId IN :accountIds
            ORDER BY ActivityDate DESC NULLS LAST, CreatedDate DESC
        ]) {
            if (t.WhatId == null || bestByAccount.containsKey(t.WhatId)) continue;
            Datetime dt = (t.ActivityDate != null)
                ? Datetime.newInstance(t.ActivityDate, Time.newInstance(0, 0, 0, 0))
                : t.CreatedDate;
            bestByAccount.put((Id)t.WhatId, new ActivityPick(t.Subject, dt, 'Task'));
        }

        // Events
        for (Event e : [
            SELECT WhatId, Subject, StartDateTime, CreatedDate
            FROM Event
            WHERE WhatId IN :accountIds
            ORDER BY StartDateTime DESC NULLS LAST, CreatedDate DESC
        ]) {
            if (e.WhatId == null) continue;
            Datetime dt = (e.StartDateTime != null) ? e.StartDateTime : e.CreatedDate;
            ActivityPick existing = bestByAccount.get((Id)e.WhatId);
            if (existing == null || (dt != null && existing.dt != null && dt.getTime() > existing.dt.getTime())) {
                bestByAccount.put((Id)e.WhatId, new ActivityPick(e.Subject, dt, 'Event'));
            }
        }

        for (Id accId : bestByAccount.keySet()) {
            CustomerMapRow row = rowByAccountId.get(accId);
            if (row == null) continue;
            ActivityPick pick = bestByAccount.get(accId);
            row.lastActivitySubject = pick.subject;
            row.lastActivityDateTime = pick.dt;
            row.lastActivityType = pick.typeName;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<CustomerMapRow> getCustomers() {
        List<Account> accounts = [
            SELECT Id, Name, BillingStreet, BillingCity, BillingState,
                   BillingPostalCode, BillingCountry, BillingLatitude, BillingLongitude,
                   Contract_Periods__c, County__c, Regional_Manager__r.Name, Email__c,
                   Current_Customer__c, Contract_End_Date__c,
                   Primary_Contact__c, Primary_Contact__r.Name, Primary_Contact__r.Phone, Primary_Contact__r.Email,
                   Recent_Contract_Bid__r.Id, Recent_Contract_Bid__r.Name, Recent_Contract_Bid__r.Stage__c,
                   Recent_Contract_Bid__r.Contract_Start_Date__c, Recent_Contract_Bid__r.Contract_End_Date__c,
                   Recent_Contract_Bid__r.Due_Date__c, Recent_Contract_Bid__r.Contract_Year__c,
                   Recent_Contract_Bid__r.Total__c,
                   Recent_Contract_Bid__r.Management_Company__c, Recent_Contract_Bid__r.Management_Company__r.Name,
                   Recent_Contract_Bid__r.Label__c, Recent_Contract_Bid__r.Colored_Labels__c,
                   Recent_Contract_Bid__r.Additional_Comments__c
            FROM Account
            WHERE BillingPostalCode != null OR (BillingLatitude != null AND BillingLongitude != null)
            ORDER BY Name ASC
        ];

        List<CustomerMapRow> rows = new List<CustomerMapRow>();
        for (Account a : accounts) {
            rows.add(toRow(a, a.Recent_Contract_Bid__r));
        }
        populateHasCurrentYearBid(rows);
        populateLatestActivity(rows);
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<CustomerMapRow> getCustomersWithLatestContractBid() {
        List<Account> accounts = [
            SELECT Id, Name, BillingStreet, BillingCity, BillingState,
                   BillingPostalCode, BillingCountry, BillingLatitude, BillingLongitude,
                   Contract_Periods__c, County__c, Regional_Manager__r.Name, Email__c,
                   Current_Customer__c, Contract_End_Date__c,
                   Primary_Contact__c, Primary_Contact__r.Name, Primary_Contact__r.Phone, Primary_Contact__r.Email,
                   (
                       SELECT Id, Name, Stage__c, Contract_Start_Date__c, Contract_End_Date__c,
                              Due_Date__c, Contract_Year__c, Total__c,
                              Management_Company__c, Management_Company__r.Name,
                              Label__c, Colored_Labels__c, Additional_Comments__c
                       FROM Contract_Bids__r
                       ORDER BY Contract_Start_Date__c DESC NULLS LAST, CreatedDate DESC
                       LIMIT 1
                   )
            FROM Account
            WHERE BillingPostalCode != null OR (BillingLatitude != null AND BillingLongitude != null)
            ORDER BY Name ASC
        ];

        List<CustomerMapRow> rows = new List<CustomerMapRow>();
        for (Account a : accounts) {
            Contract_Bid__c latestBid =
                (a.Contract_Bids__r != null && !a.Contract_Bids__r.isEmpty())
                    ? a.Contract_Bids__r[0]
                    : null;
            rows.add(toRow(a, latestBid));
        }
        populateHasCurrentYearBid(rows);
        populateLatestActivity(rows);
        return rows;
    }
}
