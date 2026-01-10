@IsTest
private class InvoiceWorkOrderAssignerTest {
    @TestSetup
    static void setup() {
        // Minimal data graph: Account -> Proposal__c -> WorkOrder, plus a few Invoices
        Account acc = new Account(Name = 'Test Acc');
        insert acc;

        // Create two proposals
        Opportunity prop1 = new Opportunity(
            Name = 'P1',
            AccountId = acc.Id,
            CloseDate = Date.today().addDays(2)
        );
        Opportunity prop2 = new Opportunity(
            Name = 'P2',
            AccountId = acc.Id,
            CloseDate = Date.today().addDays(2)
        );
        insert new List<Opportunity>{ prop1, prop2 };

        // Create WorkOrder on prop1 only
        WorkOrder wo1 = new WorkOrder(
            Subject = 'WO P1',
            Proposal__c = prop1.Id
        );
        insert wo1;

        // Invoices:
        // - inv1: has QB Id, null Work_Order__c, proposal with WorkOrder (should be linked)
        // - inv2: has QB Id, null Work_Order__c, proposal without WorkOrder (should remain null)
        // - inv3: missing QB Id, null Work_Order__c (should be ignored)
        // - inv4: has QB Id, already linked Work_Order__c (should be ignored / not updated)

        Invoice__c inv1 = new Invoice__c(
            Name = 'INV1',
            Proposal__c = prop1.Id,
            WorkOrder_QuickBooks_Id__c = 'QB-1'
        );
        Invoice__c inv2 = new Invoice__c(
            Name = 'INV2',
            Proposal__c = prop2.Id,
            WorkOrder_QuickBooks_Id__c = 'QB-2'
        );
        Invoice__c inv3 = new Invoice__c(
            Name = 'INV3',
            Proposal__c = prop1.Id
            // WorkOrder_QuickBooks_Id__c null - should be ignored
        );
        Invoice__c inv4 = new Invoice__c(
            Name = 'INV4',
            Proposal__c = prop1.Id,
            WorkOrder_QuickBooks_Id__c = 'QB-4',
            Work_Order__c = wo1.Id // already set - should be ignored
        );
        insert new List<Invoice__c>{ inv1, inv2, inv3, inv4 };
    }

    @IsTest
    static void testNoUpdateWhenNoEligibleInvoices() {
        // Prepare a list where nothing should qualify:
        // Take only invoices that either lack QB Id or already have Work_Order__c
        List<Invoice__c> invs = [
            SELECT Id, Proposal__c, Work_Order__c, WorkOrder_QuickBooks_Id__c, Name
            FROM Invoice__c
            WHERE Name IN ('INV3','INV4')
        ];

        // Capture current values to assert no change
        Map<Id, Id> beforeWorkOrder = new Map<Id, Id>();
        for (Invoice__c i : invs) beforeWorkOrder.put(i.Id, i.Work_Order__c);

        Test.startTest();
        InvoiceWorkOrderAssigner.assignWorkOrder(invs);
        Test.stopTest();

        // Ensure values remain unchanged
        for (Invoice__c i : [
            SELECT Id, Work_Order__c FROM Invoice__c WHERE Id IN :beforeWorkOrder.keySet()
        ]) {
            System.assertEquals(beforeWorkOrder.get(i.Id), i.Work_Order__c, 'No changes expected for non-eligible invoices');
        }
    }

}