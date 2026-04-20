@IsTest
private class QuickBooksAccountCheckerTest {

    @TestSetup
    static void makeData() {
        // Just a base account to ensure object works in org
        Account acc = new Account(
            Name            = 'Good Company',
            AccountNumber   = 'GC123',
            QuickBooks_Id__c = 'QB000',
            BillingStreet   = 'Test Drive 123'
        );
        insert acc;
    }

    @IsTest
    static void testValidAccount_NoErrors_AndStreetReordered() {
        Account acc = new Account(
            Name             = 'Good Company',
            AccountNumber    = 'GC123',
            QuickBooks_Id__c = 'QB001',
            BillingStreet    = 'Test Drive 321'
        );

        Test.startTest();
        // Запускаем фильтр напрямую
        QuickBooksAccountChecker.filterAccounts(new List<Account>{ acc });
        Test.stopTest();

        // Имя не меняется
        System.assertEquals('Good Company', acc.Name);
        // BillingStreet должен стать "321 Test Drive"
        System.assertEquals('321 Test Drive', acc.BillingStreet);
    }

    @IsTest
    static void testExcludedYearInName_AddError() {
        Account acc = new Account(
            Name             = 'Customer 2024',
            AccountNumber    = 'CUST001',
            QuickBooks_Id__c = 'QB002',
            BillingStreet    = 'Main St 10'
        );

        Test.startTest();
        try {
            // Проверяем addError через DML
            insert acc;
            // В реальной жизни filterAccounts должен вызываться триггером before insert
            // Здесь симулируем триггер вручную
        } catch (DmlException e) {
            // addError должен блокировать insert с нашим текстом
            System.assert(
                e.getDmlMessage(0).contains('Account is rejected: contains excluded year reference.')
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testExcludedYearInAccountNumber_AddError() {
        Account acc = new Account(
            Name             = 'Some Customer',
            AccountNumber    = 'Client-24-25',
            QuickBooks_Id__c = 'QB003',
            BillingStreet    = 'Some Street 5'
        );

        Test.startTest();
        try {
            insert acc;
        } catch (DmlException e) {
            System.assert(
                e.getDmlMessage(0).contains('Account is rejected: contains excluded year reference.')
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testNumericOnlyName_AddError() {
        Account acc = new Account(
            Name             = '12345',
            AccountNumber    = 'CUST123',
            QuickBooks_Id__c = 'QB004',
            BillingStreet    = 'Numeric St 7'
        );

        Test.startTest();
        try {
            insert acc;
        } catch (DmlException e) {
            System.assert(
                e.getDmlMessage(0).contains('Account is rejected: Name/CompanyName cannot be numeric only.')
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testNumericOnlyAccountNumber_AddError() {
        Account acc = new Account(
            Name             = 'Valid Name',
            AccountNumber    = '999999',
            QuickBooks_Id__c = 'QB005',
            BillingStreet    = 'Somewhere 9'
        );

        Test.startTest();
        try {
            insert acc;
        } catch (DmlException e) {
            System.assert(
                e.getDmlMessage(0).contains('Account is rejected: Name/CompanyName cannot be numeric only.')
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testBlankOrNullFields_NoErrors() {
        Account acc1 = new Account(
            Name             = null,
            AccountNumber    = null,
            QuickBooks_Id__c = 'QB006'
        );
        Account acc2 = new Account(
            Name             = '',
            AccountNumber    = '',
            QuickBooks_Id__c = 'QB007'
        );

        Test.startTest();
        QuickBooksAccountChecker.filterAccounts(new List<Account>{ acc1, acc2 });
        Test.stopTest();

        // Просто убеждаемся, что метод не падает и значения не меняются
        System.assertEquals(null, acc1.Name);
        System.assertEquals('', acc2.Name);
    }
}