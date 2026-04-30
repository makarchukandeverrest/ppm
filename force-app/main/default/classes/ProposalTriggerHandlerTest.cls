@isTest
private class ProposalTriggerHandlerTest {

    /**
     * @description On insert, stage is not driven by Is_Active__c here because ProposalStatusDefiner.updateStatus
     *              is not invoked from ProposalTriggerHandler.beforeInsert (customer/RM sync only).
     */
    @isTest
    static void testBeforeInsert_IsActiveTrue() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Opportunity activeProposal = new Opportunity(
            Name = 'Active Test Proposal',
            AccountId = testAccount.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft',
            Is_Active__c = true
        );

        Test.startTest();
        insert activeProposal;
        Test.stopTest();

        Opportunity insertedProposal = [SELECT Id, StageName, Is_Active__c FROM Opportunity WHERE Id = :activeProposal.Id];
        System.assertEquals('Draft', insertedProposal.StageName, 'Stage remains Draft until ProposalStatusDefiner.updateStatus runs elsewhere.');
        System.assertEquals(true, insertedProposal.Is_Active__c, 'Is_Active__c should remain true.');
    }
}