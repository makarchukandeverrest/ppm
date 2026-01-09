@isTest
private class ProposalTriggerHandlerTest {

    /**
     * @description Tests that when Is_Active__c is true, StageName is set to 'Pending'
     */
    @isTest
    static void testBeforeInsert_IsActiveTrue() {
        // ARRANGE
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Opportunity activeProposal = new Opportunity(
            Name = 'Active Test Proposal',
            AccountId = testAccount.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft', // Initial value that should be changed
            Is_Active__c = true // This should trigger 'Pending' status
        );

        // ACT
        Test.startTest();
        insert activeProposal;
        Test.stopTest();

        // ASSERT
        Opportunity insertedProposal = [SELECT Id, StageName, Is_Active__c FROM Opportunity WHERE Id = :activeProposal.Id];
        System.assertEquals('Pending', insertedProposal.StageName, 'StageName should be set to "Pending" when Is_Active__c is true.');
        System.assertEquals(true, insertedProposal.Is_Active__c, 'Is_Active__c should remain true.');
    }
}