@isTest
private class ProposalWebhookServiceTest {
  private class WebhookMock implements HttpCalloutMock {
    private final String expectedPathFragment;

    private WebhookMock(String expectedPathFragment) {
      this.expectedPathFragment = expectedPathFragment;
    }

    public HTTPResponse respond(HTTPRequest request) {
      System.assertEquals('POST', request.getMethod());
      System.assert(
        request.getEndpoint().contains(expectedPathFragment),
        'Endpoint should target expected Skyvia webhook'
      );
      System.assertNotEquals(
        null,
        request.getBody(),
        'Webhook body should be present'
      );

      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody('{"ok":true}');
      return response;
    }
  }

  @isTest
  static void sendProposalInserts_postsToInsertWebhook() {
    Test.setMock(
      HttpCalloutMock.class,
      new WebhookMock('salesforce_proposal_insert')
    );

    Account account = new Account(Name = 'Webhook Account Insert');
    insert account;

    Opportunity proposal = new Opportunity(
      Name = 'Webhook Proposal Insert',
      AccountId = account.Id,
      CloseDate = Date.today().addDays(10),
      StageName = 'Draft',
      Is_Active__c = true,
      Reference_Number__c = 'REF-INS'
    );
    insert proposal;

    Test.startTest();
    ProposalWebhookService.sendProposalInserts(new Set<Id>{ proposal.Id });
    Test.stopTest();
  }

  @isTest
  static void sendProposalUpdates_postsToUpdateWebhook() {
    Test.setMock(HttpCalloutMock.class, new WebhookMock('salesforce_proposal'));

    Account account = new Account(Name = 'Webhook Account');
    insert account;

    Opportunity proposal = new Opportunity(
      Name = 'Webhook Proposal',
      AccountId = account.Id,
      CloseDate = Date.today().addDays(10),
      StageName = 'Draft',
      Is_Active__c = true,
      Reference_Number__c = 'REF-100'
    );
    insert proposal;

    insert new Deal_Line_Item__c(
      Name = 'Item A',
      Description__c = 'Desc',
      Quantity__c = 1,
      Unit_Cost__c = 10,
      Total__c = 10,
      Credit_Card_Fee__c = '1.5',
      Deal__c = proposal.Id
    );

    Test.startTest();
    ProposalWebhookService.sendProposalUpdates(new Set<Id>{ proposal.Id });
    Test.stopTest();
  }

  @isTest
  static void buildPayload_includesCreditCardFee() {
    Account account = new Account(
      Name = 'Payload Customer',
      QuickBooks_Id__c = 'QB-ACC-FROM-CUSTOMER'
    );
    Opportunity proposal = new Opportunity(
      Name = 'Payload Proposal',
      Description = 'Memo',
      CloseDate = Date.today(),
      Is_Active__c = true,
      Account_QuickBooks_Id__c = 'QB-ACC-ON-PROPOSAL-IGNORED',
      Reference_Number__c = 'R1',
      Project_Order_No__c = 'PO1',
      Terms__c = 'Net 15',
      Order_Taken_By__c = 'Rep',
      FOB__c = 'Origin',
      Date_Ordered__c = Date.today()
    );
    proposal.putSObject(Opportunity.AccountId, account);

    Deal_Line_Item__c lineItem = new Deal_Line_Item__c(
      Name = 'Fee Item',
      Description__c = 'Line desc',
      Quantity__c = 1,
      Unit_Cost__c = 100,
      Total__c = 100,
      Credit_Card_Fee__c = '3.00'
    );

    ProposalWebhookService.ProposalWebhookPayload payload = ProposalWebhookService.buildPayload(
      proposal,
      new List<Deal_Line_Item__c>{ lineItem }
    );

    System.assertEquals(
      'QB-ACC-FROM-CUSTOMER',
      payload.accountQuickBooksId,
      'Should take QuickBooks Id from Customer Account, not Proposal field'
    );
    System.assertEquals('Payload Customer', payload.customerName);
    System.assertEquals(1, payload.items.size());
    System.assertEquals('3.00', payload.items[0].creditCardFee);
    System.assertEquals('Fee Item', payload.items[0].name);
  }

  @isTest
  static void buildPayload_insertAddsOneEmptyItemWhenNoLineItems() {
    Opportunity proposal = new Opportunity(
      Name = 'Empty Items Proposal',
      CloseDate = Date.today(),
      Is_Active__c = true
    );

    ProposalWebhookService.ProposalWebhookPayload payload = ProposalWebhookService.buildPayload(
      proposal,
      new List<Deal_Line_Item__c>(),
      true
    );

    System.assertEquals(
      1,
      payload.items.size(),
      'Insert should send one placeholder item when Proposal has no line items'
    );
    System.assertEquals('SERVICE WORK:SERVICES:F105', payload.items[0].name);
    System.assertEquals(1, payload.items[0].quantity);
    System.assertEquals(0, payload.items[0].unitCost);
    System.assertEquals(0, payload.items[0].total);
  }
}
