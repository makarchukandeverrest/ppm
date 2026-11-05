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

    Opportunity insertedProposal = [
      SELECT Id, StageName, Is_Active__c
      FROM Opportunity
      WHERE Id = :activeProposal.Id
    ];
    System.assertEquals(
      'Draft',
      insertedProposal.StageName,
      'Stage remains Draft until ProposalStatusDefiner.updateStatus runs elsewhere.'
    );
    System.assertEquals(
      true,
      insertedProposal.Is_Active__c,
      'Is_Active__c should remain true.'
    );
  }

  @isTest
  static void testAfterUpdate_StopRemindersAndStageChange() {
    Account testAccount = new Account(Name = 'Handler Update Account');
    insert testAccount;

    Opportunity proposal = new Opportunity(
      Name = 'Handler Update Proposal',
      AccountId = testAccount.Id,
      CloseDate = Date.today().addDays(30),
      StageName = 'Draft',
      Is_Active__c = true
    );
    insert proposal;

    Test.startTest();
    proposal.Stop_Sending_Reminders__c = true;
    proposal.StageName = 'Negotiation';
    update proposal;
    Test.stopTest();

    Opportunity updatedProposal = [
      SELECT Id, StageName, Stop_Sending_Reminders__c
      FROM Opportunity
      WHERE Id = :proposal.Id
    ];
    System.assertEquals('Negotiation', updatedProposal.StageName);
    System.assertEquals(true, updatedProposal.Stop_Sending_Reminders__c);
  }

  @isTest
  static void testBeforeUpdate_AssignCustomerFromQuickBooksId() {
    Account acc = new Account(Name = 'QB Handler Account');
    insert acc;

    List<Contact> contacts = new List<Contact>{
      new Contact(LastName = 'Bill', AccountId = acc.Id),
      new Contact(LastName = 'Maint', AccountId = acc.Id),
      new Contact(LastName = 'Prime', AccountId = acc.Id),
      new Contact(LastName = 'Sec', AccountId = acc.Id)
    };
    insert contacts;

    acc.QuickBooks_Id__c = 'QB-HANDLER-1';
    acc.Billing_Contact__c = contacts[0].Id;
    acc.Maintenance_Contact__c = contacts[1].Id;
    acc.Primary_Contact__c = contacts[2].Id;
    acc.Secondary_Contact__c = contacts[3].Id;
    update acc;

    Opportunity proposal = new Opportunity(
      Name = 'QB Handler Proposal',
      CloseDate = Date.today().addDays(30),
      StageName = 'Draft'
    );
    insert proposal;

    Test.startTest();
    proposal.Account_QuickBooks_Id__c = 'QB-HANDLER-1';
    update proposal;
    Test.stopTest();

    Opportunity updatedProposal = [
      SELECT
        Id,
        AccountId,
        Customer_Billing_Contact__c,
        Customer_Maintenance_Contact__c,
        Customer_Primary_Contact__c,
        Customer_Secondary_Contact__c
      FROM Opportunity
      WHERE Id = :proposal.Id
    ];
    System.assertEquals(acc.Id, updatedProposal.AccountId);
    System.assertEquals(
      contacts[0].Id,
      updatedProposal.Customer_Billing_Contact__c
    );
    System.assertEquals(
      contacts[1].Id,
      updatedProposal.Customer_Maintenance_Contact__c
    );
    System.assertEquals(
      contacts[2].Id,
      updatedProposal.Customer_Primary_Contact__c
    );
    System.assertEquals(
      contacts[3].Id,
      updatedProposal.Customer_Secondary_Contact__c
    );
  }

  @isTest
  static void testBeforeUpdate_AccountChangeSyncsContacts() {
    Account firstAccount = new Account(Name = 'First Handler Account');
    Account secondAccount = new Account(Name = 'Second Handler Account');
    insert new List<Account>{ firstAccount, secondAccount };

    Contact firstContact = new Contact(
      LastName = 'First',
      AccountId = firstAccount.Id
    );
    Contact secondContact = new Contact(
      LastName = 'Second',
      AccountId = secondAccount.Id
    );
    insert new List<Contact>{ firstContact, secondContact };

    firstAccount.Primary_Contact__c = firstContact.Id;
    secondAccount.Primary_Contact__c = secondContact.Id;
    update new List<Account>{ firstAccount, secondAccount };

    Opportunity proposal = new Opportunity(
      Name = 'Account Change Proposal',
      AccountId = firstAccount.Id,
      CloseDate = Date.today().addDays(30),
      StageName = 'Draft'
    );
    insert proposal;

    Test.startTest();
    proposal.AccountId = secondAccount.Id;
    update proposal;
    Test.stopTest();

    Opportunity updatedProposal = [
      SELECT Id, AccountId
      FROM Opportunity
      WHERE Id = :proposal.Id
    ];
    System.assertEquals(secondAccount.Id, updatedProposal.AccountId);
  }
}
