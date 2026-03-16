@IsTest
public with sharing class CustomerRegionalManagerServiceTest {

    // Use the current running user as "Regional Manager" to ensure
    // the new owner has read access to the records we create.
    private static User getRegionalManagerUser() {
        return [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
    }

    @IsTest
    static void testAssignOwnerByCustomer_WorkOrder() {
        User rm = getRegionalManagerUser();

        Account acc = new Account(
            Name               = 'Test Account WO',
            Regional_Manager__c = rm.Id
        );
        insert acc;

        WorkOrder wo = new WorkOrder(
            Subject   = 'Test WO',
            AccountId = acc.Id
        );
        insert wo;

        Test.startTest();
        // Re-query to populate Account.Regional_Manager__c relation
        WorkOrder woForService = [
            SELECT Id, AccountId, Account.Regional_Manager__c
            FROM WorkOrder
            WHERE Id = :wo.Id
        ];
        CustomerRegionalManagerService.assignOwnerByCustomer(new List<WorkOrder>{ woForService });
        Test.stopTest();

        WorkOrder woAfter = [
            SELECT Id, OwnerId
            FROM WorkOrder
            WHERE Id = :wo.Id
        ];
        System.assertEquals(
            rm.Id,
            woAfter.OwnerId,
            'WorkOrder owner should be set to account Regional Manager'
        );
    }

    @IsTest
    static void testAssignOwnerByCustomer_Invoice() {
        User rm = getRegionalManagerUser();

        Account acc = new Account(
            Name               = 'Test Account Inv',
            Regional_Manager__c = rm.Id
        );
        insert acc;

        Invoice__c inv = new Invoice__c(
            Name        = 'Test Invoice',
            Customer__c = acc.Id
        );
        insert inv;

        Test.startTest();
        // Re-query to populate Customer__r.Regional_Manager__c relation
        Invoice__c invForService = [
            SELECT Id, Customer__c, Customer__r.Regional_Manager__c
            FROM Invoice__c
            WHERE Id = :inv.Id
        ];
        CustomerRegionalManagerService.assignOwnerByCustomer(new List<Invoice__c>{ invForService });
        Test.stopTest();

        Invoice__c invAfter = [
            SELECT Id, OwnerId
            FROM Invoice__c
            WHERE Id = :inv.Id
        ];
        System.assertEquals(
            rm.Id,
            invAfter.OwnerId,
            'Invoice owner should be set to customer Regional Manager'
        );
    }

    @IsTest
    static void testAssignOwnerByCustomer_AccountUpdatesRelatedRecords() {
        User rm = getRegionalManagerUser();

        Account acc = new Account(
            Name               = 'Test Account Related',
            Regional_Manager__c = rm.Id
        );
        insert acc;

        WorkOrder wo = new WorkOrder(
            Subject   = 'Related WO',
            AccountId = acc.Id
        );
        insert wo;

        Invoice__c inv = new Invoice__c(
            Name        = 'Related Invoice',
            Customer__c = acc.Id
        );
        insert inv;

        Test.startTest();
        CustomerRegionalManagerService.assignOwnerByCustomer(new List<Account>{ acc });
        Test.stopTest();

        WorkOrder woAfter = [
            SELECT Id, OwnerId
            FROM WorkOrder
            WHERE Id = :wo.Id
        ];
        Invoice__c invAfter = [
            SELECT Id, OwnerId
            FROM Invoice__c
            WHERE Id = :inv.Id
        ];

        System.assertEquals(
            rm.Id,
            woAfter.OwnerId,
            'Related WorkOrder owner should be updated to account Regional Manager'
        );
        System.assertEquals(
            rm.Id,
            invAfter.OwnerId,
            'Related Invoice owner should be updated to account Regional Manager'
        );
    }
}