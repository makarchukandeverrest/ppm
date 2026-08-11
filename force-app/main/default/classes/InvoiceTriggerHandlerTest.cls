@isTest
private class InvoiceTriggerHandlerTest {

    // TEST SETUP - Create all necessary test data
    @testSetup
    static void setupTestData() {
        // 1. Create Accounts
        List<Account> testAccounts = new List<Account>{
            new Account(Name = 'Test Customer A'),
            new Account(Name = 'Test Customer B'),
            new Account(Name = 'Contract Customer'),
            new Account(Name = 'Service Customer')
        };
        insert testAccounts;

        // 2. Create Proposals (Opportunities) with QuickBooks Ids and Reference Numbers
        List<Opportunity> testProposals = new List<Opportunity>();
        testProposals.add(new Opportunity(
            Name = 'Test Proposal QB-001',
            AccountId = testAccounts[0].Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft',
            Is_Active__c = true,
            QuickBooks_Id__c = 'QB-PROP-001',
            Reference_Number__c = '1111'
        ));
        testProposals.add(new Opportunity(
            Name = 'Test Proposal QB-002', 
            AccountId = testAccounts[1].Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft',
            Is_Active__c = true,
            QuickBooks_Id__c = 'QB-PROP-002',
            Reference_Number__c = '2222'
        ));
        testProposals.add(new Opportunity(
            Name = 'Test Proposal No QB Id',
            AccountId = testAccounts[2].Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft',
            Is_Active__c = true,
            Reference_Number__c = '3333' // No QuickBooks_Id__c
        ));
        insert testProposals;

        // 3. Create WorkOrders with QuickBooks Ids
        List<WorkOrder> testWorkOrders = new List<WorkOrder>();
        testWorkOrders.add(new WorkOrder(
            Subject = 'Test WO QB-001',
            AccountId = testAccounts[0].Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Duration = 60,
            StartDate = System.now(),
            Quick_Books_Id__c = 'QB-WO-001'
        ));
        testWorkOrders.add(new WorkOrder(
            Subject = 'Test WO QB-002',
            AccountId = testAccounts[1].Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Duration = 60,
            StartDate = System.now(),
            Quick_Books_Id__c = 'QB-WO-002'
        ));
        insert testWorkOrders;
    }

    /**
     * @description Tests linking by Proposal_QuickBooks_Id__c (primary method)
     */
    @isTest
    static void testLinkByProposalQuickBooksId() {
        // ARRANGE
        Opportunity testProposal = [SELECT Id, QuickBooks_Id__c FROM Opportunity WHERE QuickBooks_Id__c = 'QB-PROP-001' LIMIT 1];

        Invoice__c invoice = new Invoice__c(
            Name = 'Test Customer A: Invoice 001',
            Proposal_QuickBooks_Id__c = 'QB-PROP-001', // This should link to the proposal
            Amount__c = 1000.00,
            Due_Date__c = Date.today()
        );

        // ACT
        Test.startTest();
        insert invoice;
        Test.stopTest();

        // ASSERT
        Invoice__c insertedInvoice = [SELECT Id, Proposal__c, Customer__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(testProposal.Id, insertedInvoice.Proposal__c, 'Should be linked to proposal by QuickBooks Id');
        System.assertNotEquals(null, insertedInvoice.Customer__c, 'Should be linked to customer by name');
    }

    /**
     * @description Tests linking by Memo__c reference number when Proposal_QuickBooks_Id__c is blank
     */
    @isTest
    static void testLinkByMemoReferenceNumber() {
        // ARRANGE
        Opportunity testProposal = [SELECT Id, Reference_Number__c FROM Opportunity WHERE Reference_Number__c = '2222' LIMIT 1];

        Invoice__c invoice = new Invoice__c(
            Name = 'Test Customer B: Invoice 002',
            // Proposal_QuickBooks_Id__c is blank - should use Memo
            WorkOrder_QuickBooks_Id__c = 'QB-WO-002', // Required for this path
            Memo__c = 'Estimate 2222: Some description', // This should be parsed
            Amount__c = 2000.00,
            Due_Date__c = Date.today()
        );

        // ACT
        Test.startTest();
        insert invoice;
        Test.stopTest();

        // ASSERT
        Invoice__c insertedInvoice = [SELECT Id, Proposal__c, Work_Order__c, Customer__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(testProposal.Id, insertedInvoice.Proposal__c, 'Should be linked to proposal by memo reference number');
        System.assertNotEquals(null, insertedInvoice.Work_Order__c, 'Should be linked to work order');
        System.assertNotEquals(null, insertedInvoice.Customer__c, 'Should be linked to customer');
    }

    /**
     * @description Tests linking WorkOrder by QuickBooks Id
     */
    @isTest
    static void testLinkWorkOrderByQuickBooksId() {
        // ARRANGE
        WorkOrder testWorkOrder = [SELECT Id, Quick_Books_Id__c FROM WorkOrder WHERE Quick_Books_Id__c = 'QB-WO-001' LIMIT 1];

        Invoice__c invoice = new Invoice__c(
            Name = 'Test Customer A: Invoice 003',
            WorkOrder_QuickBooks_Id__c = 'QB-WO-001', // This should link to work order
            Amount__c = 1500.00,
            Due_Date__c = Date.today()
        );

        // ACT
        Test.startTest();
        insert invoice;
        Test.stopTest();

        // ASSERT
        Invoice__c insertedInvoice = [SELECT Id, Work_Order__c, Customer__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(testWorkOrder.Id, insertedInvoice.Work_Order__c, 'Should be linked to work order by QuickBooks Id');
        System.assertNotEquals(null, insertedInvoice.Customer__c, 'Should be linked to customer');
    }

    /**
     * @description Tests customer linking by name patterns (contains colon)
     */
    @isTest
    static void testCustomerLinkingWithColon() {
        // ARRANGE
        Account testCustomer = [SELECT Id, Name FROM Account WHERE Name = 'Test Customer A' LIMIT 1];

        Invoice__c invoice = new Invoice__c(
            Name = 'Test Customer A: Monthly Service', // Contains colon
            Amount__c = 500.00,
            Due_Date__c = Date.today()
        );

        // ACT
        Test.startTest();
        insert invoice;
        Test.stopTest();

        // ASSERT
        Invoice__c insertedInvoice = [SELECT Id, Customer__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(testCustomer.Id, insertedInvoice.Customer__c, 'Should be linked to customer by name with colon');
    }

    /**
     * @description Tests customer linking by name patterns (contains "Contract")
     */
    @isTest
    static void testCustomerLinkingWithContract() {
        // ARRANGE
        Account testCustomer = [SELECT Id, Name FROM Account WHERE Name = 'Contract Customer' LIMIT 1];

        Invoice__c invoice = new Invoice__c(
            Name = 'Contract Customer: Annual Contract', // Contains "Contract"
            Amount__c = 5000.00,
            Due_Date__c = Date.today()
        );

        // ACT
        Test.startTest();
        insert invoice;
        Test.stopTest();

        // ASSERT
        Invoice__c insertedInvoice = [SELECT Id, Customer__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(testCustomer.Id, insertedInvoice.Customer__c, 'Should be linked to customer by name with "Contract"');
    }

    /**
     * @description Tests customer linking by name patterns (contains "Service")
     */
    @isTest
    static void testCustomerLinkingWithService() {
        // ARRANGE
        Account testCustomer = [SELECT Id, Name FROM Account WHERE Name = 'Service Customer' LIMIT 1];

        Invoice__c invoice = new Invoice__c(
            Name = 'Service Customer: Premium Service', // Contains "Service"
            Amount__c = 750.00,
            Due_Date__c = Date.today()
        );

        // ACT
        Test.startTest();
        insert invoice;
        Test.stopTest();

        // ASSERT
        Invoice__c insertedInvoice = [SELECT Id, Customer__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(testCustomer.Id, insertedInvoice.Customer__c, 'Should be linked to customer by name with "Service"');
    }

    /**
     * @description Tests scenario where no linking is possible (all fields blank)
     */
    @isTest
    static void testNoLinkingPossible() {
        // ARRANGE
        Invoice__c invoice = new Invoice__c(
            Name = 'Unknown Customer', // No matching account
            // All linking fields are blank
            Amount__c = 100.00,
            Due_Date__c = Date.today()
        );

        // ACT
        Test.startTest();
        insert invoice;
        Test.stopTest();

        // ASSERT
        Invoice__c insertedInvoice = [SELECT Id, Proposal__c, Work_Order__c, Customer__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(null, insertedInvoice.Proposal__c, 'Should not be linked to proposal');
        System.assertEquals(null, insertedInvoice.Work_Order__c, 'Should not be linked to work order');
        System.assertEquals(null, insertedInvoice.Customer__c, 'Should not be linked to customer');
    }

    /**
     * @description Tests error handling when exception occurs
     */
    @isTest
    static void testErrorHandling() {
        // ARRANGE - This will cause exception because of the update statement
        // We'll use a trigger handler test to verify error handling
        Invoice__c invoice = new Invoice__c(
            Name = 'Test: Invoice',
            Amount__c = 100.00,
            Due_Date__c = Date.today()
        );

        // ACT & ASSERT - Should not throw exception due to try-catch
        Test.startTest();
        try {
            insert invoice;
            System.assert(true, 'Should handle errors gracefully');
        } catch (Exception e) {
            System.assert(false, 'Should not propagate exceptions: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testLinkByLinkedTxnJsonArray() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE QuickBooks_Id__c = 'QB-PROP-001' LIMIT 1];
        WorkOrder wo = [SELECT Id FROM WorkOrder WHERE Quick_Books_Id__c = 'QB-WO-001' LIMIT 1];

        Invoice__c invoice = new Invoice__c(
            Name = 'Test Customer A: Invoice LinkedTxn',
            Quickbooks_LinkedTxn_JSON__c = '[{"TxnType":"Estimate","TxnID":"QB-PROP-001"},{"TxnType":"SalesOrder","TxnId":"QB-WO-001"}]',
            Amount__c = 100,
            Due_Date__c = Date.today()
        );

        Test.startTest();
        insert invoice;
        Test.stopTest();

        Invoice__c inserted = [SELECT Proposal__c, Work_Order__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(opp.Id, inserted.Proposal__c, 'Should link proposal from JSON array');
        System.assertEquals(wo.Id, inserted.Work_Order__c, 'Should link work order from JSON array');
    }

    @isTest
    static void testLinkByLinkedTxnMap() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE QuickBooks_Id__c = 'QB-PROP-002' LIMIT 1];

        Invoice__c invoice = new Invoice__c(
            Name = 'Test Customer B: Invoice LinkedTxn Map',
            Quickbooks_LinkedTxn_JSON__c = '{"LinkedTxn":[{"TxnType":"Estimate","TxnId":"QB-PROP-002"}]}',
            Amount__c = 100,
            Due_Date__c = Date.today()
        );

        Test.startTest();
        insert invoice;
        Test.stopTest();

        Invoice__c inserted = [SELECT Proposal__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(opp.Id, inserted.Proposal__c, 'Should link proposal from JSON map');
    }

    @isTest
    static void testLinkByCustomerQuickBooksId() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Customer A' LIMIT 1];
        acc.QuickBooks_Id__c = 'QB-CUST-001';
        update acc;

        Invoice__c invoice = new Invoice__c(
            Name = 'Some Invoice',
            Customer_Quickbooks_Id__c = 'Customer: QB-CUST-001',
            Amount__c = 100,
            Due_Date__c = Date.today()
        );

        Test.startTest();
        insert invoice;
        Test.stopTest();

        Invoice__c inserted = [SELECT Customer__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(acc.Id, inserted.Customer__c, 'Should link customer by QuickBooks Id with colon');
    }

    @isTest
    static void testLinkByCustomerQuickBooksIdWithoutColon() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Customer B' LIMIT 1];
        acc.QuickBooks_Id__c = 'QB-CUST-002';
        update acc;

        Invoice__c invoice = new Invoice__c(
            Name = 'Another Invoice',
            Customer_Quickbooks_Id__c = 'QB-CUST-002',
            Amount__c = 100,
            Due_Date__c = Date.today()
        );

        Test.startTest();
        insert invoice;
        Test.stopTest();

        Invoice__c inserted = [SELECT Customer__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(acc.Id, inserted.Customer__c, 'Should link customer by QuickBooks Id without colon');
    }

    @isTest
    static void testLinkBySinglePartialNameMatch() {
        Account partial = new Account(Name = 'Acme Corporation');
        insert partial;

        Invoice__c invoice = new Invoice__c(
            Name = 'Acme Corp: Invoice',
            Amount__c = 100,
            Due_Date__c = Date.today()
        );

        Test.startTest();
        insert invoice;
        Test.stopTest();

        Invoice__c inserted = [SELECT Customer__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(partial.Id, inserted.Customer__c, 'Should link by single partial name match');
    }

    @isTest
    static void testHandlesInvalidLinkedTxnJson() {
        Invoice__c invoice = new Invoice__c(
            Name = 'Test Customer A: Invoice Invalid JSON',
            Quickbooks_LinkedTxn_JSON__c = 'not-json',
            Amount__c = 100,
            Due_Date__c = Date.today()
        );

        Test.startTest();
        insert invoice;
        Test.stopTest();

        Invoice__c inserted = [SELECT Id, Proposal__c, Work_Order__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(null, inserted.Proposal__c);
        System.assertEquals(null, inserted.Work_Order__c);
    }

    @isTest
    static void testLinkByMemoReferenceNumberWithoutEstimatePrefix() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Reference_Number__c = '3333' LIMIT 1];

        Invoice__c invoice = new Invoice__c(
            Name = 'Contract Customer: Invoice',
            Memo__c = 'Ref 3333',
            Amount__c = 100,
            Due_Date__c = Date.today()
        );

        Test.startTest();
        insert invoice;
        Test.stopTest();

        Invoice__c inserted = [SELECT Proposal__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(opp.Id, inserted.Proposal__c, 'Should link by reference number without Estimate prefix');
    }
}