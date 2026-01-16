@isTest
private class ContactTriggerHandlerTest {

    @IsTest
    static void testEmailBouncedHandling() {
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;

        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = testAccount.Id
        );
        insert testContact;

        Contact insertedContact = [SELECT Id, EmailBouncedDate FROM Contact WHERE Id = :testContact.Id];
        System.assertEquals(null, insertedContact.EmailBouncedDate, 'EmailBouncedDate should be null initially');

        Test.startTest();
        insertedContact.EmailBouncedDate = Datetime.now();
        update insertedContact;
        Test.stopTest();

        Contact updatedContact = [SELECT Id, EmailBouncedDate FROM Contact WHERE Id = :testContact.Id];
        System.assertNotEquals(null, updatedContact.EmailBouncedDate, 'EmailBouncedDate should be set after update');
    }

    @IsTest
    static void testNoBounceWhenEmailBouncedDateUnchanged() {
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;

        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = testAccount.Id,
            EmailBouncedDate = Datetime.now().addDays(-1)
        );
        insert testContact;

        Test.startTest();
        testContact.Phone = '1234567890';
        update testContact;
        Test.stopTest();

        Contact updatedContact = [SELECT Id, Phone FROM Contact WHERE Id = :testContact.Id];
        System.assertEquals('1234567890', updatedContact.Phone, 'Phone should be updated');
    }

    @IsTest
    static void testEmailBouncedDateSetToNull() {
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;

        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = testAccount.Id,
            EmailBouncedDate = Datetime.now()
        );
        insert testContact;

        Test.startTest();
        testContact.EmailBouncedDate = null;
        update testContact;
        Test.stopTest();

        Contact updatedContact = [SELECT Id, EmailBouncedDate FROM Contact WHERE Id = :testContact.Id];
        System.assertEquals(null, updatedContact.EmailBouncedDate, 'EmailBouncedDate should be null after clearing');
    }
}