@isTest
private class CaseTriggerHandlerTest {

    @isTest
    static void fillsContactFromAccountPrimaryContactOnInsert() {
        Account acc = new Account(Name = 'Case Trigger Test Customer');
        insert acc;

        Contact primary = new Contact(
            FirstName = 'Primary',
            LastName = 'Contact',
            Email = 'primary@example.com',
            AccountId = acc.Id
        );
        insert primary;

        acc.Primary_Contact__c = primary.Id;
        update acc;

        Test.startTest();
        Case c = new Case(
            Subject = 'Winterization Case',
            AccountId = acc.Id,
            Status = 'New',
            Origin = 'Web'
        );
        insert c;
        Test.stopTest();

        Case inserted = [SELECT Id, ContactId FROM Case WHERE Id = :c.Id];
        System.assertEquals(
            primary.Id,
            inserted.ContactId,
            'ContactId should be filled from Account Primary_Contact__c'
        );
    }

    @isTest
    static void keepsExistingContactOnInsert() {
        Account acc = new Account(Name = 'Case Trigger Keep Contact Customer');
        insert acc;

        Contact primary = new Contact(
            FirstName = 'Primary',
            LastName = 'Contact',
            Email = 'primary-keep@example.com',
            AccountId = acc.Id
        );
        Contact existing = new Contact(
            FirstName = 'Existing',
            LastName = 'Contact',
            Email = 'existing@example.com',
            AccountId = acc.Id
        );
        insert new List<Contact>{ primary, existing };

        acc.Primary_Contact__c = primary.Id;
        update acc;

        Test.startTest();
        Case c = new Case(
            Subject = 'Case With Contact',
            AccountId = acc.Id,
            ContactId = existing.Id,
            Status = 'New',
            Origin = 'Web'
        );
        insert c;
        Test.stopTest();

        Case inserted = [SELECT Id, ContactId FROM Case WHERE Id = :c.Id];
        System.assertEquals(
            existing.Id,
            inserted.ContactId,
            'Existing ContactId should not be overwritten'
        );
    }

    @isTest
    static void fillsRegionalManagerFromAccountOnInsert() {
        User rm = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        Account acc = new Account(
            Name = 'Case RM Customer',
            Regional_Manager__c = rm.Id
        );
        insert acc;

        Test.startTest();
        Case c = new Case(
            Subject = 'Case RM Insert',
            AccountId = acc.Id,
            Status = 'New',
            Origin = 'Web'
        );
        insert c;
        Test.stopTest();

        Case inserted = [SELECT Id, Regional_Manager__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(
            rm.Id,
            inserted.Regional_Manager__c,
            'Case Regional Manager should be copied from Account on insert'
        );
    }

    @isTest
    static void syncsRegionalManagerWhenAccountChanges() {
        User rm = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        Account withRm = new Account(
            Name = 'Case RM Source',
            Regional_Manager__c = rm.Id
        );
        Account withoutRm = new Account(Name = 'Case RM Target');
        insert new List<Account>{ withRm, withoutRm };

        Case c = new Case(
            Subject = 'Case RM Reparent',
            AccountId = withRm.Id,
            Status = 'New',
            Origin = 'Web'
        );
        insert c;

        Test.startTest();
        c.AccountId = withoutRm.Id;
        update c;
        Test.stopTest();

        Case updated = [SELECT Id, Regional_Manager__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(
            null,
            updated.Regional_Manager__c,
            'Case Regional Manager should match the new Account'
        );
    }

    @isTest
    static void resetsManualRegionalManagerOverride() {
        User rm = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        Account acc = new Account(
            Name = 'Case RM Override Customer',
            Regional_Manager__c = rm.Id
        );
        insert acc;

        Case c = new Case(
            Subject = 'Case RM Override',
            AccountId = acc.Id,
            Status = 'New',
            Origin = 'Web'
        );
        insert c;

        Test.startTest();
        c.Regional_Manager__c = null;
        update c;
        Test.stopTest();

        Case updated = [SELECT Id, Regional_Manager__c FROM Case WHERE Id = :c.Id];
        System.assertEquals(
            rm.Id,
            updated.Regional_Manager__c,
            'Manual Case Regional Manager changes should be reset to the Account value'
        );
    }
}
