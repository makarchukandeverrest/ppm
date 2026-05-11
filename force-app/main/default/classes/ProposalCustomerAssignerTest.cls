@isTest
private class ProposalCustomerAssignerTest {

  @isTest
  static void testAssignCustomer_PopulatesAccountAndContactLookupsFromMatchingAccount() {
    Account acc = new Account(Name = 'Customer For Assigner');
    insert acc;

    List<Contact> cs = new List<Contact>{
      new Contact(LastName = 'Bill', AccountId = acc.Id),
      new Contact(LastName = 'Maint', AccountId = acc.Id),
      new Contact(LastName = 'Prime', AccountId = acc.Id),
      new Contact(LastName = 'Sec', AccountId = acc.Id)
    };
    insert cs;

    acc.QuickBooks_Id__c = 'QB-ASSIGN-ALL-1';
    acc.Billing_Contact__c = cs[0].Id;
    acc.Maintenance_Contact__c = cs[1].Id;
    acc.Primary_Contact__c = cs[2].Id;
    acc.Secondary_Contact__c = cs[3].Id;
    update acc;

    acc = [
      SELECT
        Id,
        QuickBooks_Id__c,
        Billing_Contact__c,
        Maintenance_Contact__c,
        Primary_Contact__c,
        Secondary_Contact__c
      FROM Account
      WHERE Id = :acc.Id
    ];

    Opportunity opp = new Opportunity(
      Name = 'Opp All Nulls',
      CloseDate = Date.today().addDays(30),
      StageName = 'Draft',
      Account_QuickBooks_Id__c = 'QB-ASSIGN-ALL-1'
    );

    Test.startTest();
    ProposalCustomerAssigner.assignCustomer(new List<Opportunity>{ opp });
    Test.stopTest();

    System.assertEquals(acc.Id, opp.AccountId);
    System.assertEquals(acc.Billing_Contact__c, opp.Customer_Billing_Contact__c);
    System.assertEquals(acc.Maintenance_Contact__c, opp.Customer_Maintenance_Contact__c);
    System.assertEquals(acc.Primary_Contact__c, opp.Customer_Primary_Contact__c);
    System.assertEquals(acc.Secondary_Contact__c, opp.Customer_Secondary_Contact__c);
  }

  @isTest
  static void testAssignCustomer_OnlyFillsNullTargetFields() {
    Account acc = new Account(Name = 'Customer For Partial');
    insert acc;

    List<Contact> cs = new List<Contact>{
      new Contact(LastName = 'B1', AccountId = acc.Id),
      new Contact(LastName = 'B2', AccountId = acc.Id)
    };
    insert cs;

    acc.QuickBooks_Id__c = 'QB-ASSIGN-PART-1';
    acc.Billing_Contact__c = cs[0].Id;
    acc.Maintenance_Contact__c = cs[1].Id;
    acc.Primary_Contact__c = cs[0].Id;
    acc.Secondary_Contact__c = cs[1].Id;
    update acc;

    acc = [
      SELECT
        Id,
        QuickBooks_Id__c,
        Billing_Contact__c,
        Maintenance_Contact__c,
        Primary_Contact__c,
        Secondary_Contact__c
      FROM Account
      WHERE Id = :acc.Id
    ];

    // AccountId + billing already set on the opportunity: those if (== null) branches are skipped
    Opportunity opp = new Opportunity(
      Name = 'Opp Partial',
      CloseDate = Date.today().addDays(40),
      StageName = 'Draft',
      AccountId = acc.Id,
      Customer_Billing_Contact__c = cs[0].Id,
      Account_QuickBooks_Id__c = 'QB-ASSIGN-PART-1'
    );

    Test.startTest();
    ProposalCustomerAssigner.assignCustomer(new List<Opportunity>{ opp });
    Test.stopTest();

    System.assertEquals(acc.Id, opp.AccountId);
    System.assertEquals(cs[0].Id, opp.Customer_Billing_Contact__c);
    System.assertEquals(acc.Maintenance_Contact__c, opp.Customer_Maintenance_Contact__c);
    System.assertEquals(acc.Primary_Contact__c, opp.Customer_Primary_Contact__c);
    System.assertEquals(acc.Secondary_Contact__c, opp.Customer_Secondary_Contact__c);
  }

  @isTest
  static void testAssignCustomer_NoQuickBooksIdOnOpportunity_NoOp() {
    Account acc = new Account(Name = 'Unused', QuickBooks_Id__c = 'QB-NONE');
    insert acc;

    Opportunity opp = new Opportunity(
      Name = 'No QB Id',
      CloseDate = Date.today().addDays(30),
      StageName = 'Draft'
    );

    Test.startTest();
    ProposalCustomerAssigner.assignCustomer(new List<Opportunity>{ opp });
    Test.stopTest();

    System.assertEquals(null, opp.AccountId);
  }

  @isTest
  static void testAssignCustomer_NoMatchingAccount_NoAssignment() {
    Opportunity opp = new Opportunity(
      Name = 'No Match',
      CloseDate = Date.today().addDays(30),
      StageName = 'Draft',
      Account_QuickBooks_Id__c = 'QB-DOES-NOT-EXIST'
    );

    Test.startTest();
    ProposalCustomerAssigner.assignCustomer(new List<Opportunity>{ opp });
    Test.stopTest();

    System.assertEquals(null, opp.AccountId);
  }
}
