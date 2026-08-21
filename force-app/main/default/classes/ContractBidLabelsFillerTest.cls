@IsTest
private class ContractBidLabelsFillerTest {
    @TestSetup
    static void setup() {
        Account labelsCustomer = new Account(Name = 'Labels Customer');
        Account targetCustomer = new Account(Name = 'Target Customer');
        Account otherCustomer = new Account(Name = 'Other Customer');
        Account nameYearCustomer = new Account(Name = 'Name Year Customer');
        insert new List<Account>{ labelsCustomer, targetCustomer, otherCustomer, nameYearCustomer };

        insert new List<Contract_Bid__c>{
            new Contract_Bid__c(
                Name = 'Previous Year Bid',
                Customer__c = labelsCustomer.Id,
                Stage__c = 'Contact Verified and Updated',
                Contract_Year__c = '2025-2026',
                Label__c = 'Hot Lead'
            ),
            new Contract_Bid__c(
                Name = 'Previous Year',
                Customer__c = targetCustomer.Id,
                Stage__c = 'Contact Verified and Updated',
                Contract_Year__c = '2025-2026',
                Label__c = 'Warm Lead'
            ),
            new Contract_Bid__c(
                Name = 'Older Year',
                Customer__c = targetCustomer.Id,
                Stage__c = 'Contact Verified and Updated',
                Contract_Year__c = '2024-2025',
                Label__c = 'Cold Lead'
            ),
            new Contract_Bid__c(
                Name = 'Other Previous Year',
                Customer__c = otherCustomer.Id,
                Stage__c = 'Contact Verified and Updated',
                Contract_Year__c = '2025-2026',
                Label__c = 'Hot Lead'
            ),
            new Contract_Bid__c(
                Name = 'Oak Pool 2025 - 2026',
                Customer__c = nameYearCustomer.Id,
                Stage__c = 'Contact Verified and Updated',
                Label__c = 'Hot Lead'
            )
        };
    }

    @IsTest
    static void insert_addsDefaultLabels() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Labels Customer'];

        Test.startTest();
        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'New Bid',
            Customer__c = customer.Id,
            Stage__c = 'Contact Verified and Updated',
            Contract_Year__c = '2026-2027'
        );
        insert bid;
        Test.stopTest();

        bid = [SELECT Label__c FROM Contract_Bid__c WHERE Id = :bid.Id];
        System.assert(bid.Label__c.contains('Assumptive Bid'));
        System.assert(bid.Label__c.contains('Contract Created'));
    }

    @IsTest
    static void insert_keepsExistingLabelsAndAddsDefaults() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Labels Customer'];

        Test.startTest();
        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'New Bid',
            Customer__c = customer.Id,
            Stage__c = 'Contact Verified and Updated',
            Contract_Year__c = '2026-2027',
            Label__c = 'Hot Lead'
        );
        insert bid;
        Test.stopTest();

        bid = [SELECT Label__c FROM Contract_Bid__c WHERE Id = :bid.Id];
        System.assert(bid.Label__c.contains('Hot Lead'));
        System.assert(bid.Label__c.contains('Assumptive Bid'));
        System.assert(bid.Label__c.contains('Contract Created'));
    }

    @IsTest
    static void insert_replacesPreviousYearLabels() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Labels Customer'];
        Contract_Bid__c previousBid = [
            SELECT Label__c
            FROM Contract_Bid__c
            WHERE Name = 'Previous Year Bid'
        ];

        Test.startTest();
        insert new Contract_Bid__c(
            Name = 'Current Year Bid',
            Customer__c = customer.Id,
            Stage__c = 'Contact Verified and Updated',
            Contract_Year__c = '2026-2027'
        );
        Test.stopTest();

        previousBid = [SELECT Label__c FROM Contract_Bid__c WHERE Id = :previousBid.Id];
        System.assertEquals('New record created', previousBid.Label__c);
    }

    @IsTest
    static void insert_skipsOtherCustomerAndOlderYear() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Target Customer'];
        Contract_Bid__c previousBid = [SELECT Id FROM Contract_Bid__c WHERE Name = 'Previous Year'];
        Contract_Bid__c olderBid = [SELECT Id FROM Contract_Bid__c WHERE Name = 'Older Year'];
        Contract_Bid__c otherCustomerBid = [SELECT Id FROM Contract_Bid__c WHERE Name = 'Other Previous Year'];

        Test.startTest();
        insert new Contract_Bid__c(
            Name = 'Current Year',
            Customer__c = customer.Id,
            Stage__c = 'Contact Verified and Updated',
            Contract_Year__c = '2026-2027'
        );
        Test.stopTest();

        Map<Id, Contract_Bid__c> bids = new Map<Id, Contract_Bid__c>([
            SELECT Label__c
            FROM Contract_Bid__c
            WHERE Id IN :new List<Id>{ previousBid.Id, olderBid.Id, otherCustomerBid.Id }
        ]);

        System.assertEquals('New record created', bids.get(previousBid.Id).Label__c);
        System.assert(bids.get(olderBid.Id).Label__c.contains('Cold Lead'));
        System.assert(!bids.get(olderBid.Id).Label__c.contains('New record created'));
        System.assert(bids.get(otherCustomerBid.Id).Label__c.contains('Hot Lead'));
        System.assert(!bids.get(otherCustomerBid.Id).Label__c.contains('New record created'));
    }

    @IsTest
    static void insert_usesYearFromNameWhenFieldBlank() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Name Year Customer'];
        Contract_Bid__c previousBid = [
            SELECT Label__c
            FROM Contract_Bid__c
            WHERE Name = 'Oak Pool 2025 - 2026'
        ];

        Test.startTest();
        insert new Contract_Bid__c(
            Name = 'Oak Pool 2026 - 2027',
            Customer__c = customer.Id,
            Stage__c = 'Contact Verified and Updated'
        );
        Test.stopTest();

        previousBid = [SELECT Label__c FROM Contract_Bid__c WHERE Id = :previousBid.Id];
        System.assertEquals('New record created', previousBid.Label__c);
    }
}
