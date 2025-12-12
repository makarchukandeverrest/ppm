@isTest
private class WorkOrderTriggerHandlerTest {

    // TEST SETUP - Create all necessary test data
    @testSetup
    static void setupTestData() {
        // 1. Create Accounts (to be linked by WorkOrderCustomerAssigner)
        List<Account> testAccounts = new List<Account>{
            new Account(Name = 'Test Customer A'),
            new Account(Name = 'Test Customer B')
        };
        insert testAccounts;

        // 2. Create Proposals (Opportunities) with Reference Numbers (to be linked by WorkOrderCustomerAssigner)
        List<Opportunity> testProposals = new List<Opportunity>();
        // Create opportunities with different reference numbers for different tests
        testProposals.add(new Opportunity(
            Name = 'Test Proposal 13974',
            AccountId = testAccounts[0].Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft',
            Is_Active__c = true,
            Reference_Number__c = '13974'
        ));
        testProposals.add(new Opportunity(
            Name = 'Test Proposal 13971', 
            AccountId = testAccounts[0].Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft',
            Is_Active__c = true,
            Reference_Number__c = '13971'
        ));
        insert testProposals;

        // 3. Ensure standard pricebook is active (required for WorkOrder)
        Pricebook2 standardPricebook = new Pricebook2(
            Id = Test.getStandardPricebookId(),
            IsActive = true
        );
        update standardPricebook;
    }

    /**
     * @description Tests the BEFORE INSERT logic: Customer and Proposal linking by WorkOrderCustomerAssigner.
     */
    @isTest
    static void testBeforeInsert_CustomerAndProposalLinking() {
        // ARRANGE - Get data from setup
        Account testCustomerA = [SELECT Id, Name FROM Account WHERE Name = 'Test Customer A' LIMIT 1];
        Opportunity testProposal = [SELECT Id, Reference_Number__c FROM Opportunity WHERE Reference_Number__c = '13974' LIMIT 1];
        
        System.debug('Looking for proposal with reference: 13974');
        System.debug('Found proposal: ' + testProposal.Id + ' with ref: ' + testProposal.Reference_Number__c);

        WorkOrder woWithCustomerAndProposal = new WorkOrder(
            Subject = 'WO With Links',
            Pricebook2Id = Test.getStandardPricebookId(),
            Duration = 60,
            StartDate = System.now(),
            Quick_Books_Customer_Name__c = 'Test Customer A: Some Other Info',
            // Format must be: "Word1 Word2" where Word2 is the reference number
            Quickbooks_Memo__c = 'Estimate 13974' // "13974" is the second word
        );

        WorkOrder woWithNoLinks = new WorkOrder(
            Subject = 'WO With No Links',
            Pricebook2Id = Test.getStandardPricebookId(),
            Duration = 60,
            StartDate = System.now(),
            Quick_Books_Customer_Name__c = 'Non-Existent Customer',
            Quickbooks_Memo__c = 'Estimate BAD-REF' // Non-existent reference
        );

        List<WorkOrder> workOrdersToInsert = new List<WorkOrder>{ woWithCustomerAndProposal, woWithNoLinks };

        // ACT
        Test.startTest();
        insert workOrdersToInsert;
        Test.stopTest();

        // DEBUG: Check what actually got linked
        Map<Id, WorkOrder> insertedWorkOrders = new Map<Id, WorkOrder>([
            SELECT Id, AccountId, Proposal__c, Quickbooks_Memo__c,
                   Proposal__r.Reference_Number__c, Proposal__r.Name
            FROM WorkOrder
            WHERE Id IN :workOrdersToInsert
        ]);

        for (WorkOrder wo : insertedWorkOrders.values()) {
            System.debug('WO: ' + wo.Id + ' | Memo: ' + wo.Quickbooks_Memo__c + ' | Proposal: ' + wo.Proposal__c + ' | Proposal Ref: ' + wo.Proposal__r?.Reference_Number__c);
        }

        // ASSERT
        WorkOrder linkedWO = insertedWorkOrders.get(woWithCustomerAndProposal.Id);
        System.assertEquals(testCustomerA.Id, linkedWO.AccountId, 'WorkOrder should be linked to the correct Account by name.');
        System.assertEquals(testProposal.Id, linkedWO.Proposal__c, 'WorkOrder should be linked to the correct Proposal by reference number. Expected: ' + testProposal.Id + ', Actual: ' + linkedWO.Proposal__c);

        // Verify the second WO was NOT linked
        WorkOrder unlinkedWO = insertedWorkOrders.get(woWithNoLinks.Id);
        System.assertEquals(null, unlinkedWO.AccountId, 'WorkOrder should not be linked to a non-existent Account.');
        System.assertEquals(null, unlinkedWO.Proposal__c, 'WorkOrder should not be linked to a non-existent Proposal.');
    }

    /**
     * @description Tests the COMPLETE flow: BEFORE insert (linking) and AFTER insert (line items + status update).
     */
    @isTest
    static void testCompleteFlow_FromLinkToStatusUpdate() {
        // ARRANGE - Get data from setup
        Account testCustomer = [SELECT Id, Name FROM Account WHERE Name = 'Test Customer A' LIMIT 1];
        // FIX: Changed to 13971 which exists in the new setup
        Opportunity testProposal = [SELECT Id, StageName, Reference_Number__c FROM Opportunity WHERE Reference_Number__c = '13971' LIMIT 1];
        System.assertEquals('Pending', testProposal.StageName, 'Proposal should start with initial stage.');

        String validLineItemsJson = '[{' +
            '"Id": "QB-12345",' +
            '"IsItemGroup": false,' +
            '"ItemId": "ITEM-001",' +
            '"ItemName": "Test Service",' +
            '"Desc": "Test Description for Line Item",' +
            '"Quantity": 1,' +
            '"Rate": 100.00,' +
            '"Amount": 100.00,' +
            '"SalesTaxCodeId": "TAX-1",' +
            '"SalesTaxCodeName": "Taxable",' +
            '"Invoiced": 0,' +
            '"IsManuallyClosed": false' +
        '}]';

        WorkOrder testWorkOrder = new WorkOrder(
            Subject = 'Test Complete Flow WO',
            Pricebook2Id = Test.getStandardPricebookId(),
            Duration = 60,
            StartDate = System.now(),
            Quick_Books_Customer_Name__c = 'Test Customer A: QB Customer ID',
            // FIX: Use the correct reference number that exists
            Quickbooks_Memo__c = 'Estimate 13971', // "13971" is the second word
            Quick_Books_Line_Items__c = validLineItemsJson
        );

        // ACT
        Test.startTest();
        insert testWorkOrder;
        Test.stopTest();

        // ASSERT
        // 1. Verify BEFORE INSERT logic: Links were made
        WorkOrder insertedWO = [SELECT Id, AccountId, Proposal__c, Proposal__r.Reference_Number__c 
                               FROM WorkOrder WHERE Id = :testWorkOrder.Id];
        System.assertEquals(testCustomer.Id, insertedWO.AccountId, 'WorkOrder should be auto-linked to the correct Customer.');
        System.assertEquals(testProposal.Id, insertedWO.Proposal__c, 'WorkOrder should be auto-linked to the correct Proposal. Expected: ' + testProposal.Id + ', Actual: ' + insertedWO.Proposal__c);

        // 2. Verify AFTER INSERT logic: Line item was created (WorkOrderLineItemCreator)
        List<Quick_Book_Work_Order_Line_Item__c> lineItems = [
            SELECT Id FROM Quick_Book_Work_Order_Line_Item__c WHERE Work_Order__c = :testWorkOrder.Id
        ];
        System.assertEquals(1, lineItems.size(), 'Line item should be created from JSON.');

        // 3. Verify AFTER INSERT logic: Proposal status was updated (ProposalStatusDefiner)
        Opportunity updatedProposal = [SELECT Id, StageName FROM Opportunity WHERE Id = :testProposal.Id];
        System.assertEquals('Approved - WO Issued', updatedProposal.StageName, 'Proposal stage should be updated by the trigger.');
    }

    // ... (Keep all other test methods the same, but ensure they use existing reference numbers)
    
    /**
     * @description Tests the positive scenario for WorkOrderLineItemCreator with valid JSON.
     * UPDATED: Use existing reference number 13974
     */
    @isTest
    static void testAfterInsert_WithValidLineItemsJson() {
        // ARRANGE - Get data from setup
        Account testAcc = [SELECT Id FROM Account LIMIT 1];
        Opportunity testProposal = [SELECT Id FROM Opportunity WHERE Reference_Number__c = '13974' LIMIT 1];

        String validLineItemsJson = '[{' +
            '"Id": "QB-12345",' +
            '"IsItemGroup": false,' +
            '"ItemId": "ITEM-001",' +
            '"ItemName": "Test Service",' +
            '"Desc": "Test Description for Line Item",' +
            '"Quantity": 2,' +
            '"Rate": 150.00,' +
            '"Amount": 300.00,' +
            '"SalesTaxCodeId": "TAX-1",' +
            '"SalesTaxCodeName": "Taxable",' +
            '"Invoiced": 0,' +
            '"IsManuallyClosed": false' +
        '}]';

        WorkOrder testWorkOrder = new WorkOrder(
            Subject = 'Test WorkOrder with Line Items',
            AccountId = testAcc.Id,
            Proposal__c = testProposal.Id, // Manually link since we're testing line items, not parsing
            Pricebook2Id = Test.getStandardPricebookId(),
            Duration = 60,
            StartDate = System.now(),
            Quick_Books_Line_Items__c = validLineItemsJson
        );

        // ACT
        Test.startTest();
        insert testWorkOrder;
        Test.stopTest();

        // ASSERT
        List<Quick_Book_Work_Order_Line_Item__c> createdLineItems = [
            SELECT Id, Name, Work_Order__c, Description__c, Quantity__c, Rate__c, Amount__c, Quick_Books_Id__c
            FROM Quick_Book_Work_Order_Line_Item__c
            WHERE Work_Order__c = :testWorkOrder.Id
        ];

        System.assertEquals(1, createdLineItems.size(), 'Exactly one line item should be created from the JSON.');

        Quick_Book_Work_Order_Line_Item__c lineItem = createdLineItems[0];
        System.assertEquals('Test Service', lineItem.Name, 'Line Item Name should match JSON.');
        System.assertEquals('Test Description for Line Item', lineItem.Description__c, 'Line Item Description should match JSON.');
        System.assertEquals(2, lineItem.Quantity__c, 'Line Item Quantity should match JSON.');
        System.assertEquals(150.00, lineItem.Rate__c, 'Line Item Rate should match JSON.');
        System.assertEquals(300.00, lineItem.Amount__c, 'Line Item Amount should match JSON.');
        System.assertEquals('QB-12345', lineItem.Quick_Books_Id__c, 'Line Item QuickBooks Id should match JSON.');
        System.assertEquals(testWorkOrder.Id, lineItem.Work_Order__c, 'Line Item should be linked to the correct Work Order.');
    }
}