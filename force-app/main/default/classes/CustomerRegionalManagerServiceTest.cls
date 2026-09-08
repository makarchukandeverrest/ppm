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

    // ───────────────────────────────────────────────────
    //  WorkOrder owner assignment
    // ───────────────────────────────────────────────────
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

    // ───────────────────────────────────────────────────
    //  Invoice owner assignment
    // ───────────────────────────────────────────────────
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

    // ───────────────────────────────────────────────────
    //  Account change cascades to WO + Invoice + Proposals
    // ───────────────────────────────────────────────────
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

    // ───────────────────────────────────────────────────
    //  Proposal RM sync on insert
    // ───────────────────────────────────────────────────
    @IsTest
    static void testSyncProposalRMFromCustomer_Insert() {
        User rm = getRegionalManagerUser();

        Account acc = new Account(
            Name               = 'RM Sync Customer',
            Regional_Manager__c = rm.Id
        );
        insert acc;

        // Simulate a before-insert: create Opportunity in memory, set AccountId,
        // then call the service. In a real trigger the field is set in-memory.
        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name      = 'Proposal RM Test',
                StageName = 'Proposal Created / Ready for review',
                CloseDate = Date.today().addDays(30),
                AccountId = acc.Id
            )
        };

        Test.startTest();
        CustomerRegionalManagerService.syncProposalRMFromCustomer(opps);
        Test.stopTest();

        System.assertEquals(
            rm.Id,
            opps[0].Regional_Manager__c,
            'Proposal Regional_Manager__c should be set from Customer on insert'
        );
        System.assertEquals(
            rm.Id,
            opps[0].OwnerId,
            'Proposal OwnerId should be set from Customer Regional Manager on insert'
        );
    }

    // ───────────────────────────────────────────────────
    //  Proposal RM manual override prevention
    // ───────────────────────────────────────────────────
    @IsTest
    static void testPreventProposalRMOverride() {
        User rm = getRegionalManagerUser();

        Account acc = new Account(
            Name               = 'Override Test Customer',
            Regional_Manager__c = rm.Id
        );
        insert acc;

        Opportunity opp = new Opportunity(
            Name      = 'Override Proposal',
            StageName = 'Proposal Created / Ready for review',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id,
            Regional_Manager__c = rm.Id
        );
        insert opp;

        // Build old map snapshot
        Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>{
            opp.Id => opp.clone(true, true, true, true)
        };

        // Simulate manual override: set RM to null (a different value)
        opp.Regional_Manager__c = null;

        Test.startTest();
        CustomerRegionalManagerService.preventProposalRMOverride(
            new List<Opportunity>{ opp }, oldMap
        );
        Test.stopTest();

        System.assertEquals(
            rm.Id,
            opp.Regional_Manager__c,
            'Regional_Manager__c should be reset to Customer RM after manual override attempt'
        );
    }

    // ───────────────────────────────────────────────────
    //  Account RM change → open Proposals update RM + Owner
    // ───────────────────────────────────────────────────
    @IsTest
    static void testAccountRMChange_OpenProposals() {
        User rm = getRegionalManagerUser();

        Account acc = new Account(
            Name               = 'Open Proposal Customer',
            Regional_Manager__c = rm.Id
        );
        insert acc;

        Opportunity openOpp = new Opportunity(
            Name      = 'Open Proposal',
            StageName = 'Proposal Created / Ready for review',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id
        );
        insert openOpp;

        Test.startTest();
        CustomerRegionalManagerService.assignOwnerByCustomer(new List<Account>{ acc });
        Test.stopTest();

        Opportunity oppAfter = [
            SELECT Id, OwnerId, Regional_Manager__c
            FROM Opportunity
            WHERE Id = :openOpp.Id
        ];

        System.assertEquals(
            rm.Id,
            oppAfter.OwnerId,
            'Open Proposal OwnerId should be updated to new RM'
        );
    }

    // ───────────────────────────────────────────────────
    //  Account RM change → closed Proposals update Owner only
    // ───────────────────────────────────────────────────
    @IsTest
    static void testAccountRMChange_ClosedProposals() {
        User rm = getRegionalManagerUser();

        Account acc = new Account(
            Name               = 'Closed Proposal Customer',
            Regional_Manager__c = rm.Id
        );
        insert acc;

        // Create a closed proposal (must be truly closed in the org)
        Opportunity closedOpp = new Opportunity(
            Name      = 'Closed Proposal',
            StageName = 'Closed Won',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id,
            Regional_Manager__c = null   // deliberately different from acc RM
        );
        insert closedOpp;

        // Snapshot before
        Opportunity before = [
            SELECT Id, Regional_Manager__c
            FROM Opportunity
            WHERE Id = :closedOpp.Id
        ];

        Test.startTest();
        CustomerRegionalManagerService.assignOwnerByCustomer(new List<Account>{ acc });
        Test.stopTest();

        Opportunity oppAfter = [
            SELECT Id, OwnerId, Regional_Manager__c
            FROM Opportunity
            WHERE Id = :closedOpp.Id
        ];

        System.assertEquals(
            rm.Id,
            oppAfter.OwnerId,
            'Closed Proposal OwnerId should still be updated to new RM'
        );
        System.assertEquals(
            before.Regional_Manager__c,
            oppAfter.Regional_Manager__c,
            'Closed Proposal Regional_Manager__c should NOT be changed'
        );
    }

    @IsTest
    static void testSyncCaseRMFromCustomer_Insert() {
        User rm = getRegionalManagerUser();

        Account acc = new Account(
            Name = 'Case RM Sync Customer',
            Regional_Manager__c = rm.Id
        );
        insert acc;

        List<Case> cases = new List<Case>{
            new Case(
                Subject = 'Case RM Service Insert',
                AccountId = acc.Id,
                Status = 'New',
                Origin = 'Web'
            )
        };

        Test.startTest();
        CustomerRegionalManagerService.syncCaseRMFromCustomer(cases);
        Test.stopTest();

        System.assertEquals(
            rm.Id,
            cases[0].Regional_Manager__c,
            'Case Regional_Manager__c should be set from Account'
        );
    }

    @IsTest
    static void testAccountRMChange_UpdatesRelatedCases() {
        User rm = getRegionalManagerUser();
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        User otherRm = new User(
            Alias = 'rm2',
            Email = 'rm2@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'OtherRM',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            Username = 'rm2' + String.valueOf(Datetime.now().getTime()) + '@ppm.test',
            ProfileId = standardProfile.Id
        );
        insert otherRm;

        Test.startTest();
        Account acc = new Account(
            Name = 'Case Cascade Customer',
            Regional_Manager__c = rm.Id
        );
        insert acc;

        Case relatedCase = new Case(
            Subject = 'Related Case',
            AccountId = acc.Id,
            Status = 'New',
            Origin = 'Web'
        );
        insert relatedCase;

        acc.Regional_Manager__c = otherRm.Id;
        update acc;
        Test.stopTest();

        Case caseAfter = [
            SELECT Id, Regional_Manager__c
            FROM Case
            WHERE Id = :relatedCase.Id
        ];
        System.assertEquals(
            otherRm.Id,
            caseAfter.Regional_Manager__c,
            'Case Regional Manager should stay in sync when Account RM changes'
        );
    }
}