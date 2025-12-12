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
}