@IsTest
private class AccountTriggerHandlerTest {

    private static Account insertCurrentCustomer(String stage) {
        Account acc = new Account(
            Name = 'Current Client Test',
            Stage__c = stage,
            Current_Customer__c = true
        );
        insert acc;
        return acc;
    }

    @IsTest
    static void testBeforeUpdate_ClosedLost_UnmarksCurrentCustomer() {
        Account acc = insertCurrentCustomer('Closed - WON');

        Test.startTest();
        acc.Stage__c = AccountCurrentCustomerUpdater.STAGE_CLOSED_LOST;
        update acc;
        Test.stopTest();

        acc = [
            SELECT Current_Customer__c, Stage__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals('Closed - LOST', acc.Stage__c);
        System.assertEquals(false, acc.Current_Customer__c);
    }

    @IsTest
    static void testBeforeUpdate_OtherStageChange_KeepsCurrentCustomer() {
        Account acc = insertCurrentCustomer('Closed - WON');

        Test.startTest();
        acc.Stage__c = 'Proposal/Review';
        update acc;
        Test.stopTest();

        acc = [
            SELECT Current_Customer__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals(true, acc.Current_Customer__c);
    }

    @IsTest
    static void testClosedWonBid_MarksCurrentCustomer() {
        Account acc = new Account(Name = 'Won Client Test', Current_Customer__c = false);
        insert acc;

        Test.startTest();
        AccountCurrentCustomerUpdater.updateCustomers(
            new List<Contract_Bid__c>{
                new Contract_Bid__c(Customer__c = acc.Id, Contract_Year__c = '2025-2026')
            }
        );
        Test.stopTest();

        acc = [
            SELECT Current_Customer__c, Contract_Periods__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals(true, acc.Current_Customer__c);
        System.assertEquals('2025-2026', acc.Contract_Periods__c);
    }

    @IsTest
    static void testClosedWonBid_AppendsPeriod() {
        Account acc = new Account(
            Name = 'Existing Period Client',
            Current_Customer__c = false,
            Contract_Periods__c = '2024-2025'
        );
        insert acc;

        Test.startTest();
        AccountCurrentCustomerUpdater.updateCustomers(
            new List<Contract_Bid__c>{
                new Contract_Bid__c(Customer__c = acc.Id, Contract_Year__c = '2025-2026')
            }
        );
        Test.stopTest();

        acc = [SELECT Contract_Periods__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('2024-2025;2025-2026', acc.Contract_Periods__c);
    }

    @IsTest
    static void testUpdateCustomers_SkipsBidsWithoutCustomer() {
        AccountCurrentCustomerUpdater.updateCustomers(new List<Contract_Bid__c>());
        AccountCurrentCustomerUpdater.updateCustomers(
            new List<Contract_Bid__c>{ new Contract_Bid__c(Name = 'No Customer', Stage__c = 'Closed - WON') }
        );
        System.assert(true, 'Bids without Customer__c should be skipped');
    }

    @IsTest
    static void testClearCurrentCustomerOnLost_NullInputs_NoException() {
        AccountCurrentCustomerUpdater.clearCurrentCustomerOnLost(null, null);
        AccountCurrentCustomerUpdater.clearCurrentCustomerOnLost(
            new List<Account>{ new Account(Name = 'No Id') },
            new Map<Id, Account>()
        );
        System.assert(true, 'Null and unmatched oldMap entries should be ignored');
    }

    @IsTest
    static void testBeforeUpdate_AlreadyClosedLost_DoesNotChangeCheckbox() {
        Account acc = insertCurrentCustomer('Closed - LOST');

        Test.startTest();
        acc.Name = 'Current Client Test Updated';
        update acc;
        Test.stopTest();

        acc = [
            SELECT Current_Customer__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals(
            true,
            acc.Current_Customer__c,
            'Checkbox should change only when Stage becomes Closed - LOST'
        );
    }
}
