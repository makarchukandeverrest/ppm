@IsTest
private with sharing class InvoiceQuickBooksLinkCustomerTest {
    @testSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'The Ashberry'
        );
        insert acc;
    }

    @IsTest
    static void testInvoiceAssignedToTheAshberry() {
        Account theAshberry = [
            SELECT Id, Name
            FROM Account
            WHERE Name = 'The Ashberry'
            LIMIT 1
        ];

        Invoice__c inv = new Invoice__c(
            Name = 'Ashberry:2026 Service',
            Memo__c = 'Pool Permit',
            Proposal_QuickBooks_Id__c = null,
            WorkOrder_QuickBooks_Id__c = null
        );

        Test.startTest();
        insert inv;
        Test.stopTest();

        Invoice__c insertedInv = [
            SELECT Id, Name, Customer__c
            FROM Invoice__c
            WHERE Id = :inv.Id
            LIMIT 1
        ];

        System.assertNotEquals(
            null,
            insertedInv.Customer__c,
            'Customer__c must be populated for Ashberry invoice'
        );

        System.assertEquals(
            theAshberry.Id,
            insertedInv.Customer__c,
            'Invoice should be linked to "The Ashberry" account'
        );
    }
}