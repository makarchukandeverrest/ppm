@IsTest
private class QuickBooksAccountCheckerTest {

    @TestSetup
    static void makeData(){
        Account acc = new Account(
            Name = 'Good Company',
            AccountNumber = 'GC123',
            QuickBooks_Id__c = 'QB000',
            BillingStreet = 'Test Drive 123'
        );
        insert acc;
    }
    @IsTest
    static void testValidAccount() {
        Account acc = new Account(
            Name = 'Good Company',
            AccountNumber = 'GC123',
            QuickBooks_Id__c = 'QB000',
            BillingStreet = 'Test Drive 321'
        );

        Test.startTest();
        List<Account> accounts = new List<Account>{acc};
        QuickBooksAccountChecker.filterAccounts(accounts);
        // No errors should be thrown
        System.assertEquals('Good Company', acc.Name);
        Test.stopTest();
    }

    @IsTest
    static void testBlankOrNullFields() {
        Account acc1 = new Account(Name = null, AccountNumber = null, QuickBooks_Id__c = 'QB001');
        Account acc2 = new Account(Name = '', AccountNumber = '', QuickBooks_Id__c = 'QB002');
        List<Account> accounts = new List<Account>{acc1, acc2};

        Test.startTest();
        QuickBooksAccountChecker.filterAccounts(accounts);
        Test.stopTest();
        // No errors should be thrown for blank/null fields
        System.assertEquals(null, acc1.Name);
        System.assertEquals('', acc2.Name);
    }
}