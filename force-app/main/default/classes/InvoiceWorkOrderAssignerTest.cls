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
    static void testAssignsWorkOrderWhenEligible() {
        // Gather invoices
        List<Invoice__c> invs = [
            SELECT Id, Proposal__c, Work_Order__c, WorkOrder_QuickBooks_Id__c
            FROM Invoice__c
            WHERE Name IN ('INV1','INV2','INV3','INV4')
            ORDER BY Name
        ];

        // Invoke method
        Test.startTest();
        InvoiceWorkOrderAssigner.assignWorkOrder(invs);
        Test.stopTest();

        // Re-query to assert post-update values
        Map<String, Invoice__c> byName = new Map<String, Invoice__c>([
            SELECT Id, Name, Proposal__c, Work_Order__c, WorkOrder_QuickBooks_Id__c
            FROM Invoice__c
            WHERE Name IN ('INV1','INV2','INV3','INV4')
        ]);

        // From setup we know:
        // - INV1 should now have Work_Order__c populated (prop1 has a WorkOrder)
        // - INV2 should remain null (prop2 has no WorkOrder)
        // - INV3 should remain null (no QB Id - ignored)
        // - INV4 should remain as-is (already had Work_Order__c set)
        System.debug( byName);
        System.assertNotEquals(null, byName.values()[0].Work_Order__c, 'INV1 should be linked to the WorkOrder');
        System.assertEquals(null, byName.values()[1].Work_Order__c, 'INV2 should remain null - its proposal has no WorkOrder');
        System.assertEquals(null, byName.values()[2].Work_Order__c, 'INV3 should remain null - it lacked a QuickBooks Id');
        System.assertNotEquals(null, byName.values()[3].Work_Order__c, 'INV4 was already linked and should remain linked');
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

    @IsTest
    static void testBulkSafetyWithMixedInvoices() {
        // Create additional proposals and workorders and a batch of invoices to simulate bulk processing
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Opportunity p3 = new Opportunity(Name = 'P3', AccountId = acc.Id, CloseDate = Date.today().addDays(2));
        Opportunity p4 = new Opportunity(Name = 'P4', AccountId = acc.Id, CloseDate = Date.today().addDays(2));
        insert new List<Opportunity>{ p3, p4 };

        WorkOrder wo3 = new WorkOrder(Subject = 'WO P3', Proposal__c = p3.Id);
        insert wo3;

        List<Invoice__c> moreInvs = new List<Invoice__c>();
        // 100 mixed invoices
        for (Integer i = 0; i < 100; i++) {
            Boolean hasQB = Math.mod(i, 2) == 0;
            Boolean useP3 = Math.mod(i, 3) == 0; // some map to p3 (has WO), others to p4 (no WO)

            moreInvs.add(new Invoice__c(
                Name = 'BULK-' + i,
                Proposal__c = useP3 ? p3.Id : p4.Id,
                WorkOrder_QuickBooks_Id__c = hasQB ? 'QB-' + i : null
            ));
        }
        insert moreInvs;

        // Shuffle a subset to include some already-set Work_Order__c
        List<Invoice__c> toSeed = [SELECT Id, Proposal__c FROM Invoice__c WHERE Name LIKE 'BULK-%' LIMIT 5];
        for (Invoice__c i : toSeed) {
            if (i.Proposal__c == p3.Id) {
                // link a few up-front (should be ignored by method)
                i.Work_Order__c = wo3.Id;
            }
        }
        if (!toSeed.isEmpty()) update toSeed;

        List<Invoice__c> input = [
            SELECT Id, Proposal__c, Work_Order__c, WorkOrder_QuickBooks_Id__c, Name
            FROM Invoice__c
            WHERE Name LIKE 'BULK-%'
        ];

        Test.startTest();
        InvoiceWorkOrderAssigner.assignWorkOrder(input);
        Test.stopTest();

        // Post assertions:
        // - For invoices tied to p3 and having QB Id and Work_Order__c was null initially, expect populated
        // - For p4 (no WorkOrder) or missing QB Id, expect null
        Map<Id, Invoice__c> re = new Map<Id, Invoice__c>([
            SELECT Id, Proposal__c, Work_Order__c, WorkOrder_QuickBooks_Id__c, Name
            FROM Invoice__c
            WHERE Name LIKE 'BULK-%'
        ]);

        Integer linked = 0, shouldStayNull = 0;
        for (Invoice__c inv : re.values()) {
            Boolean hasQB = inv.WorkOrder_QuickBooks_Id__c != null;
            Boolean isP3 = inv.Proposal__c == p3.Id;
            if (hasQB && isP3) {
                if (inv.Work_Order__c != null) linked++;
            } else {
                if (inv.Work_Order__c == null) shouldStayNull++;
            }
        }
        System.assert(linked > 0, 'Some BULK invoices mapped to P3 with QB Id should be linked');
        System.assert(shouldStayNull > 0, 'Invoices without WO on proposal or without QB Id should remain null');
    }
}