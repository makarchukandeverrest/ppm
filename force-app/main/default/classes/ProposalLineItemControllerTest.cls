@isTest
private class ProposalLineItemControllerTest {
  @TestSetup
  static void setupTestData() {
    Opportunity opp = new Opportunity(
      Name = 'Test Opportunity',
      CloseDate = Date.today(),
      StageName = 'Prospecting',
      Sales_Tax__c = 0.08
    );
    Database.insert(opp);

    List<Deal_Line_Item__c> lineItems = new List<Deal_Line_Item__c>();
    lineItems.add(
      new Deal_Line_Item__c(
        Name = 'Item 1',
        Deal__c = opp.Id,
        Description__c = 'Test Item 1',
        Quantity__c = 2,
        Unit_Cost__c = 100,
        Total__c = 200,
        Tax__c = '16'
      )
    );
    lineItems.add(
      new Deal_Line_Item__c(
        Name = 'Item 2',
        Deal__c = opp.Id,
        Description__c = 'Test Item 2',
        Quantity__c = 1,
        Unit_Cost__c = 50,
        Total__c = 50,
        Tax__c = '4'
      )
    );
    Database.insert(lineItems);
  }

  @isTest
  static void testGetProposalLineItems() {
    Opportunity opp = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Test Opportunity'
      LIMIT 1
    ];

    Test.startTest();
    List<Deal_Line_Item__c> result = ProposalLineItemController.getProposalLineItems(
      opp.Id
    );
    Test.stopTest();

    System.assertEquals(2, result.size());
    for (Deal_Line_Item__c item : result) {
      System.assertEquals(opp.Id, item.Deal__c);
      System.assertNotEquals(null, item.Name);
      System.assertNotEquals(null, item.Description__c);
      System.assertNotEquals(null, item.Quantity__c);
      System.assertNotEquals(null, item.Unit_Cost__c);
      System.assertNotEquals(null, item.Total__c);
      System.assertNotEquals(null, item.Tax__c);
      System.assertEquals(0.08, item.Deal__r.Sales_Tax__c);
    }
  }

  @isTest
  static void testGetProposalLineItemsNoItems() {
    Opportunity newOpp = new Opportunity(
      Name = 'Empty Opportunity',
      CloseDate = Date.today(),
      StageName = 'Prospecting',
      Sales_Tax__c = 0.07
    );
    Database.insert(newOpp);

    Test.startTest();
    List<Deal_Line_Item__c> result = ProposalLineItemController.getProposalLineItems(
      newOpp.Id
    );
    Test.stopTest();

    System.assertEquals(0, result.size());
  }

  @isTest
  static void testUpdateProposalLineItems() {
    List<Deal_Line_Item__c> items = [
      SELECT
        Id,
        Name,
        Description__c,
        Quantity__c,
        Unit_Cost__c,
        Total__c,
        Tax__c
      FROM Deal_Line_Item__c
    ];
    for (Deal_Line_Item__c item : items) {
      item.Quantity__c = 5;
      item.Total__c = item.Quantity__c * item.Unit_Cost__c;
      item.Tax__c = String.valueOf(item.Total__c * 0.08);
    }

    Test.startTest();
    ProposalLineItemController.updateProposalLineItems(items);
    Test.stopTest();

    List<Deal_Line_Item__c> updatedItems = [
      SELECT Quantity__c, Total__c, Tax__c, Unit_Cost__c
      FROM Deal_Line_Item__c
      WHERE Id IN :items
    ];
    for (Deal_Line_Item__c item : updatedItems) {
      System.assertEquals(5, item.Quantity__c);
      System.assertEquals(item.Quantity__c * item.Unit_Cost__c, item.Total__c);
      System.assertEquals(String.valueOf(item.Total__c * 0.08), item.Tax__c);
    }
  }

  @isTest
  static void testCreateProposalLineItems() {
    Opportunity opp = [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Test Opportunity'
      LIMIT 1
    ];
    List<Deal_Line_Item__c> newItems = new List<Deal_Line_Item__c>();
    newItems.add(
      new Deal_Line_Item__c(
        Name = 'New Item',
        Deal__c = opp.Id,
        Description__c = 'New Test Item',
        Quantity__c = 3,
        Unit_Cost__c = 75,
        Total__c = 225,
        Tax__c = '18'
      )
    );

    Test.startTest();
    List<Id> createdIds = ProposalLineItemController.createProposalLineItems(
      newItems
    );
    Test.stopTest();

    System.assertEquals(1, createdIds.size());
    Deal_Line_Item__c createdItem = [
      SELECT Name, Description__c, Quantity__c, Unit_Cost__c, Total__c, Tax__c
      FROM Deal_Line_Item__c
      WHERE Id = :createdIds[0]
    ];
    System.assertEquals('New Item', createdItem.Name);
    System.assertEquals('New Test Item', createdItem.Description__c);
    System.assertEquals(3, createdItem.Quantity__c);
    System.assertEquals(75, createdItem.Unit_Cost__c);
    System.assertEquals(225, createdItem.Total__c);
    System.assertEquals('18', createdItem.Tax__c);
  }

  @isTest
  static void testCreateProposalLineItemsEmptyList() {
    Test.startTest();
    List<Id> createdIds = ProposalLineItemController.createProposalLineItems(
      new List<Deal_Line_Item__c>()
    );
    Test.stopTest();

    System.assertEquals(0, createdIds.size());
  }

  @isTest
  static void testDeleteProposalLineItems() {
    List<Id> itemIds = new List<Id>();
    for (Deal_Line_Item__c item : [SELECT Id FROM Deal_Line_Item__c]) {
      itemIds.add(item.Id);
    }

    Test.startTest();
    ProposalLineItemController.deleteProposalLineItems(itemIds);
    Test.stopTest();

    List<Deal_Line_Item__c> remainingItems = [
      SELECT Id
      FROM Deal_Line_Item__c
      WHERE Id IN :itemIds
    ];
    System.assertEquals(0, remainingItems.size());
  }
}