@IsTest
private class MapCustomersControllerTest {
    @TestSetup
    static void setupData() {
        // Create a standard user for user-mode execution
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'stdusr',
            Email = 'stdusr@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'stdusr' + DateTime.now().getTime() + '@example.com',
            ProfileId = p.Id
        );
        insert u;

        // Create Accounts with fields used by the controller query
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            Account a = new Account(
                Name = 'Test Customer ' + i,
                BillingStreet = '123 Test St',
                BillingCity = 'Test City',
                BillingState = 'CA',
                BillingPostalCode = '9000' + String.valueOf(i),
                BillingCountry = 'USA',
                BillingLatitude = 34.0522,
                BillingLongitude = -118.2437,
                County__c = 'Montgomery County',
                Contract_Periods__c  = '2021-2022'
            );
            accts.add(a);
        }
        insert accts;

        // Add a primary contact and relate to one account
        Contact primary = new Contact(
            LastName = 'Primary Contact',
            Phone = '555-0100',
            Email = 'primary@example.com'
        );
        insert primary;
        Account updatePrimary = [SELECT Id FROM Account WHERE Name = 'Test Customer 0' LIMIT 1];
        updatePrimary.Primary_Contact__c = primary.Id;
        update updatePrimary;

        // Manually share all accounts with the standard user (OWD = Private)
        List<AccountShare> shares = new List<AccountShare>();
        for (Account a : accts) {
            AccountShare s = new AccountShare();
            s.AccountId = a.Id;
            s.UserOrGroupId = u.Id;
            s.AccountAccessLevel = 'Edit';       // 'Read' или 'Edit'
            s.OpportunityAccessLevel = 'Edit';   // или 'Read' при необходимости
            s.RowCause = Schema.AccountShare.RowCause.Manual;
            shares.add(s);
        }
        insert shares;

        // Optionally relate a Regional Manager lookup if field exists in org
        try {
            Contact mgr = new Contact(LastName = 'Regional Manager');
            insert mgr;

            Account updateOne = [SELECT Id FROM Account WHERE Name = 'Test Customer 0' LIMIT 1];
            updateOne.Regional_Manager__c = mgr.Id;
            update updateOne;
        } catch (Exception e) {
            // Ignore if field does not exist or relationship differs
        }
    }

    @IsTest
    static void testGetCustomers_ReturnsAccountsAndFields() {
        // Run in a non-admin user context to respect 'with sharing'
        User u = [SELECT Id FROM User WHERE Username LIKE 'stdusr%' LIMIT 1];

        System.runAs(u) {
            Test.startTest();
            List<MapCustomersController.CustomerMapRow> results = MapCustomersController.getCustomers();
            Test.stopTest();

            System.assertNotEquals(null, results, 'Results should not be null');
            System.assert(results.size() > 0, 'Should return at least one row');
            System.assertEquals(3, results.size(), 'Should return all 3 test accounts');

            // Verify ordering by Name ASC
            List<MapCustomersController.CustomerMapRow> sortedResults = new List<MapCustomersController.CustomerMapRow>(results);
            sortedResults.sort(new CustomerMapRowNameComparator());

            for (Integer i = 0; i < results.size(); i++) {
                System.assertEquals(
                    sortedResults[i].name,
                    results[i].name,
                    'Results should be ordered by Name ASC. Expected: ' +
                    sortedResults[i].name + ', Actual: ' + results[i].name
                );
            }

            // Validate fields on a sample record
            for (MapCustomersController.CustomerMapRow row : results) {
                System.assertNotEquals(null, row.accountId, 'accountId should be populated');
                System.assertNotEquals(null, row.name, 'name should be populated');

                // Address fields inserted in setup
                System.assertEquals('123 Test St', row.billingStreet, 'BillingStreet mismatch');
                System.assertEquals('Test City', row.billingCity, 'BillingCity mismatch');
                System.assertEquals('CA', row.billingState, 'BillingState mismatch');
                System.assert(row.billingPostalCode != null, 'BillingPostalCode should be populated');
                System.assertEquals('USA', row.billingCountry, 'BillingCountry mismatch');

                // Geo fields
                System.assertNotEquals(null, row.billingLatitude, 'BillingLatitude should be populated');
                System.assertNotEquals(null, row.billingLongitude, 'BillingLongitude should be populated');

                // Check Regional Manager relationship if present
                if (row.regionalManagerName != null) {
                    System.assertNotEquals('', row.regionalManagerName, 'regionalManagerName should be populated');
                }
            }
        }
    }

    @IsTest
    static void testGetCustomersWithLatestContractBid_ReturnsLatestBidByStartDate() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Test Customer 0' LIMIT 1];

        Integer year = Date.today().year();
        Integer startYear = (Date.today().month() >= 7) ? year : year - 1;
        String currentContractYear = startYear + '-' + (startYear + 1);

        insert new List<Contract_Bid__c>{
            new Contract_Bid__c(
                Customer__c = account.Id,
                Contract_Start_Date__c = Date.today().addYears(-2),
                Stage__c = 'Closed - LOST',
                Contract_Year__c = '2021-2022'
            ),
            new Contract_Bid__c(
                Customer__c = account.Id,
                Contract_Start_Date__c = Date.today(),
                Stage__c = 'Closed - WON',
                Contract_Year__c = currentContractYear,
                Label__c = 'Hot Lead'
            )
        };

        User u = [SELECT Id FROM User WHERE Username LIKE 'stdusr%' LIMIT 1];

        System.runAs(u) {
            Test.startTest();
            List<MapCustomersController.CustomerMapRow> results = MapCustomersController.getCustomersWithLatestContractBid();
            Test.stopTest();

            MapCustomersController.CustomerMapRow result = null;
            for (MapCustomersController.CustomerMapRow row : results) {
                if (row.accountId == account.Id) {
                    result = row;
                    break;
                }
            }

            System.assertNotEquals(null, result, 'Row should be returned');
            System.assertNotEquals(null, result.contractBidId, 'Latest bid should be populated');
            System.assertEquals(
                'Closed - WON',
                result.contractBidStage,
                'Latest bid should be selected by Contract_Start_Date__c'
            );
            System.assertEquals(
                currentContractYear,
                result.contractYear,
                'Latest bid fields should be populated'
            );
            System.assertNotEquals(null, result.contractBidColoredLabels, 'Colored labels should be populated');
            System.assert(result.contractBidColoredLabels.contains('Hot Lead'), 'Colored labels should include label text');
            System.assertEquals(true, result.hasCurrentYearBid, 'Should detect current-year bid');

            // Newly added fields should not break serialization
            System.assertNotEquals(null, result.primaryContactId, 'primaryContactId should be populated');
            System.assertNotEquals(null, result.primaryContactName, 'primaryContactName should be populated');
        }
    }

    // Helper comparator class for sorting CustomerMapRow by Name
    private class CustomerMapRowNameComparator implements System.Comparator<MapCustomersController.CustomerMapRow> {
        public Integer compare(MapCustomersController.CustomerMapRow a1, MapCustomersController.CustomerMapRow a2) {
            if (a1.name == a2.name) return 0;
            if (a1.name > a2.name) return 1;
            return -1;
        }
    }
}