@isTest
public with sharing class EmailThreadSharingServiceTest {
    @testSetup
    static void setupData() {

        EmailMessage emailMessage = new EmailMessage(
            ThreadIdentifier = 'testIdentifier',
            FromAddress = 'testfrom@test.com',
            ToAddress = 'testto@test.com',
            CcAddress = 'testcc@test.com',
            BccAddress = 'testbcc@test.com'
        );
        insert emailMessage;
        //For trigger test  IMPORTANT to insert the email thread after the email message
        Email_Platform__Email_Thread__c emailThread = new Email_Platform__Email_Thread__c(
            Email_Platform__Thread_Identifier__c = emailMessage.ThreadIdentifier,
            Email_Platform__Subject__c = 'Test Subject',
            Email_Platform__From_Address__c = 'test@test.com'
        );
        insert emailThread;

        User testUser = new User(
            Username = 'testfrom@test.com.testuser',
            LastName = 'TestUser',
            Alias = 'tuser',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Email = 'testfrom@test.com',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id
        );
        insert testUser;
    }

    @isTest
    static void testGrantAccessToEmailThread() {
        Test.startTest();
        List<Email_Platform__Email_Thread__c> emailThreads = [SELECT Id, Email_Platform__Thread_Identifier__c FROM Email_Platform__Email_Thread__c];
        EmailThreadSharingService.grantAccessToEmailThread(emailThreads);
        Test.stopTest();
    }
}