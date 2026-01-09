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
                Email__c = 'customer' + i + '@example.com',
                County__c = 'Montgomery County',
                Contract_Periods__c  = '2021-2022'
            );
            accts.add(a);
        }
        insert accts;

        // Optionally relate a Regional Manager lookup if field exists in org
        try {
            Contact mgr = new Contact(LastName = 'Regional Manager');
            insert mgr;

            Account updateOne = [SELECT Id FROM Account WHERE Name = 'Test Customer 0' LIMIT 1];
            // If your lookup API name differs, update the key below accordingly.
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
            List<Account> results = MapCustomersController.getCustomers();
            Test.stopTest();

            System.assertNotEquals(null, results, 'Results should not be null');
            System.assert(results.size() > 0, 'Should return at least one Account');
            System.assertEquals(3, results.size(), 'Should return all 3 test accounts');

            // Verify ordering by Name ASC
            List<Account> sortedResults = new List<Account>(results);
            sortedResults.sort(new AccountNameComparator());
            
            for(Integer i = 0; i < results.size(); i++) {
                System.assertEquals(
                    sortedResults[i].Name, 
                    results[i].Name, 
                    'Results should be ordered by Name ASC. Expected: ' + sortedResults[i].Name + ', Actual: ' + results[i].Name
                );
            }

            // Validate fields on a sample record
            for(Account a : results) {
                System.assertNotEquals(null, a.Id, 'Id should be populated');
                System.assertNotEquals(null, a.Name, 'Name should be populated');
                
                // Address fields inserted in setup
                System.assertEquals('123 Test St', a.BillingStreet, 'BillingStreet mismatch');
                System.assertEquals('Test City', a.BillingCity, 'BillingCity mismatch');
                System.assertEquals('CA', a.BillingState, 'BillingState mismatch');
                System.assert(a.BillingPostalCode != null, 'BillingPostalCode should be populated');
                System.assertEquals('USA', a.BillingCountry, 'BillingCountry mismatch');

                // Geo fields
                System.assertNotEquals(null, a.BillingLatitude, 'BillingLatitude should be populated');
                System.assertNotEquals(null, a.BillingLongitude, 'BillingLongitude should be populated');

                // Custom fields
                System.assertNotEquals(null, a.Email__c, 'Email__c should be populated');

                // Check Regional Manager relationship if present
                if(a.Regional_Manager__c != null) {
                    System.assertNotEquals(null, a.Regional_Manager__r, 'Regional_Manager__r should be populated');
                    System.assertNotEquals(null, a.Regional_Manager__r.Name, 'Regional_Manager__r.Name should be populated');
                }
            }
        }
    }

        // Helper comparator class for sorting Accounts by Name
        private class AccountNameComparator implements System.Comparator<Account> {
            public Integer compare(Account a1, Account a2) {
                if(a1.Name == a2.Name) return 0;
                if(a1.Name > a2.Name) return 1;
                return -1;
            }
        }
}