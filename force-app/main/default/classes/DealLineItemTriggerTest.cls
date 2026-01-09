@isTest
private class DealLineItemTriggerTest {
@isTest
static void testTriggerAfterInsert() {
    // ARRANGE
    Account testAccount = new Account(Name = 'Test Account');
    insert testAccount;

    Opportunity testDeal = new Opportunity(
        Name = 'Test Deal for Trigger',
        AccountId = testAccount.Id,
        CloseDate = Date.today().addDays(30),
        StageName = 'Prospecting'
    );
    insert testDeal;

    Deal_Line_Item__c lineItem = new Deal_Line_Item__c(
        Name = 'Trigger Test Item',
        Description__c = 'Test Description',
        Quantity__c = 2,
        Unit_Cost__c = 50.00,
        Deal__c = testDeal.Id,
        QuickBooks_Id__c = 'QB-TRIGGER-TEST'
    );

    // ACT - This insert should fire the trigger
    Test.startTest();
    insert lineItem;
    Test.stopTest();

    // ASSERT
    Opportunity updatedDeal = [SELECT Id, Line_Items__c FROM Opportunity WHERE Id = :testDeal.Id];
    System.assertNotEquals(null, updatedDeal.Line_Items__c, 'Line_Items__c should be updated by trigger after insert');
    
    // Verify JSON content
    List<Object> parsedItems = (List<Object>) JSON.deserializeUntyped(updatedDeal.Line_Items__c);
    System.assertEquals(1, parsedItems.size(), 'JSON should contain 1 line item');
}

/**
 * @description Tests the DealLineItemTrigger on after update
 */
@isTest
static void testTriggerAfterUpdate() {
    // ARRANGE
    Account testAccount = new Account(Name = 'Test Account');
    insert testAccount;

    Opportunity testDeal = new Opportunity(
        Name = 'Test Deal for Update Trigger',
        AccountId = testAccount.Id,
        CloseDate = Date.today().addDays(30),
        StageName = 'Prospecting'
    );
    insert testDeal;

    Deal_Line_Item__c lineItem = new Deal_Line_Item__c(
        Name = 'Update Test Item',
        Description__c = 'Original Description',
        Quantity__c = 1,
        Unit_Cost__c = 25.00,
        Deal__c = testDeal.Id,
        QuickBooks_Id__c = 'QB-UPDATE-TEST'
    );
    insert lineItem;

    // Wait for initial trigger to complete, then update
    Opportunity dealBeforeUpdate = [SELECT Id, Line_Items__c FROM Opportunity WHERE Id = :testDeal.Id];
    System.assertNotEquals(null, dealBeforeUpdate.Line_Items__c, 'Line_Items__c should be set after initial insert');

    // ACT - Update the line item (should fire trigger again)
    Test.startTest();
    lineItem.Quantity__c = 3;
    lineItem.Description__c = 'Updated Description';
    update lineItem;
    Test.stopTest();

    // ASSERT
    Opportunity updatedDeal = [SELECT Id, Line_Items__c FROM Opportunity WHERE Id = :testDeal.Id];
    System.assertNotEquals(null, updatedDeal.Line_Items__c, 'Line_Items__c should be updated by trigger after update');
    
    // Verify JSON content reflects the update
    List<Object> parsedItems = (List<Object>) JSON.deserializeUntyped(updatedDeal.Line_Items__c);
    Map<String, Object> jsonItem = (Map<String, Object>) parsedItems[0];
    System.assertEquals(3, (Decimal) jsonItem.get('Quantity'), 'Quantity should be updated in JSON');
    System.assertEquals('Updated Description', (String) jsonItem.get('Desc'), 'Description should be updated in JSON');
}

/**
 * @description Tests the DealLineItemTrigger on after undelete
 */
@isTest
static void testTriggerAfterUndelete() {
    // ARRANGE
    Account testAccount = new Account(Name = 'Test Account');
    insert testAccount;

    Opportunity testDeal = new Opportunity(
        Name = 'Test Deal for Undelete Trigger',
        AccountId = testAccount.Id,
        CloseDate = Date.today().addDays(30),
        StageName = 'Prospecting'
    );
    insert testDeal;

    Deal_Line_Item__c lineItem = new Deal_Line_Item__c(
        Name = 'Undelete Test Item',
        Description__c = 'To be undeleted',
        Quantity__c = 1,
        Unit_Cost__c = 15.00,
        Deal__c = testDeal.Id,
        QuickBooks_Id__c = 'QB-UNDELETE-TEST'
    );
    insert lineItem;

    // Delete first
    delete lineItem;
    Opportunity dealAfterDelete = [SELECT Id, Line_Items__c FROM Opportunity WHERE Id = :testDeal.Id];

    // ACT - Undelete the line item (should fire trigger)
    Test.startTest();
    undelete lineItem;
    Test.stopTest();

    // ASSERT
    Opportunity updatedDeal = [SELECT Id, Line_Items__c FROM Opportunity WHERE Id = :testDeal.Id];
    System.assertNotEquals(null, updatedDeal.Line_Items__c, 'Line_Items__c should be restored after undelete');
    
    List<Object> parsedItems = (List<Object>) JSON.deserializeUntyped(updatedDeal.Line_Items__c);
    System.assertEquals(1, parsedItems.size(), 'JSON should contain 1 line item after undelete');
}

/**
 * @description Tests that trigger handles bulk operations correctly
 */
@isTest
static void testTriggerBulkOperations() {
    // ARRANGE
    Account testAccount = new Account(Name = 'Test Account');
    insert testAccount;

    List<Opportunity> testDeals = new List<Opportunity>();
    for (Integer i = 1; i <= 5; i++) {
        testDeals.add(new Opportunity(
            Name = 'Bulk Trigger Deal ' + i,
            AccountId = testAccount.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Prospecting'
        ));
    }
    insert testDeals;

    List<Deal_Line_Item__c> lineItems = new List<Deal_Line_Item__c>();
    for (Opportunity deal : testDeals) {
        for (Integer i = 1; i <= 3; i++) {
            lineItems.add(new Deal_Line_Item__c(
                Name = 'Bulk Item ' + i,
                Description__c = 'Bulk Description ' + i,
                Quantity__c = i,
                Unit_Cost__c = i * 10.00,
                Deal__c = deal.Id,
                QuickBooks_Id__c = 'QB-BULK-' + deal.Name + '-' + i
            ));
        }
    }

    // ACT - Bulk insert (should fire trigger)
    Test.startTest();
    insert lineItems;
    Test.stopTest();

    // ASSERT
    List<Opportunity> updatedDeals = [
        SELECT Id, Line_Items__c 
        FROM Opportunity 
        WHERE Id IN :testDeals
    ];

    for (Opportunity deal : updatedDeals) {
        System.assertNotEquals(null, deal.Line_Items__c, 'Each deal should have JSON data after bulk insert');
        List<Object> parsedItems = (List<Object>) JSON.deserializeUntyped(deal.Line_Items__c);
        System.assertEquals(3, parsedItems.size(), 'Each deal should have 3 line items in JSON');
    }
}

/**
 * @description Tests that trigger handles line items without Deal__c reference gracefully
 */
@isTest
static void testTriggerLineItemWithoutDeal() {
    // ARRANGE
    Deal_Line_Item__c lineItem = new Deal_Line_Item__c(
        Name = 'Orphan Item',
        Description__c = 'No deal reference',
        Quantity__c = 1,
        Unit_Cost__c = 10.00,
        QuickBooks_Id__c = 'QB-ORPHAN'
        // Deal__c is null
    );

    // ACT - This should not throw an exception even though Deal__c is null
    Test.startTest();
    insert lineItem;
    Test.stopTest();

    // ASSERT - No exception should be thrown
    // The trigger should handle null Deal__c gracefully
    System.assert(true, 'Trigger should handle line items without Deal__c without errors');
}
}