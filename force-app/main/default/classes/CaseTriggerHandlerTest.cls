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
}
