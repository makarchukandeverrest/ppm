@isTest
public with sharing class ItemsSharePointScheduledJobTest {
    @TestSetup
    static void makeData(){
        // Your existing test data setup
        Processed_SharePoint_Item__c processedItem = new Processed_SharePoint_Item__c(
            External_Item_Id__c = 'x02WB00000BcKrBAAA',
            Name = 'Test Processed Item'
        );
        insert processedItem;

        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
    }

    @isTest 
    static void testJobScheduling() {
        Test.createSoqlStub(Items_SharePoint__x.SObjectType, new ItemsSharePointMockProvider());
        Test.setMock(HttpCalloutMock.class, new SharePointFileDataMock());
        Test.startTest();
        // Schedule the job
        String jobName = 'Test SharePoint Sync';
        String cronExp = '0 0 1 * * ?'; // Every day at 1 AM
        String jobId = System.schedule(jobName, cronExp, new ItemsSharePointScheduledJob());
        
        // Get the scheduled job
        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime
            FROM CronTrigger 
            WHERE Id = :jobId
        ];
        Test.stopTest();
        
        // Verify the job was scheduled
        System.assertEquals(cronExp, ct.CronExpression);
        System.assertEquals(0, ct.TimesTriggered);
    }
}