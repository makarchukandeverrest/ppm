@isTest
private class MassSendEmailBuilderTest {
  @isTest
  static void applyOutboundSenderIdentity_workOrderMailbox() {
    User me = [
      SELECT Id, Email, Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ];
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(new List<String>{ 'recipient@example.com' });
    mail.setSubject('WO sender');
    mail.setPlainTextBody('body');

    Test.startTest();
    MassSendEmailBuilder.applyOutboundSenderIdentity(mail, me, true);
    MassSendEmailBuilder.applyOutboundSenderIdentity(mail, me, false);
    Test.stopTest();

    System.assertNotEquals(null, mail.getReplyTo());
  }

  @isTest
  static void renderHelpers_and_placeholders() {
    Account acc = new Account(
      Name = 'MSB Acc',
      BillingStreet = '1 Main',
      BillingCity = 'Austin',
      BillingState = 'TX',
      BillingPostalCode = '78701',
      BillingCountry = 'USA'
    );
    insert acc;

    Service_Team_Member__c stm = new Service_Team_Member__c(
      Name = 'MSB STM',
      Email__c = 'msb.stm@example.com'
    );
    insert stm;

    WorkOrder wo = new WorkOrder(
      Subject = 'MSB WO',
      Status = 'New',
      Priority = 'Medium',
      AccountId = acc.Id,
      Service_Team_Member__c = stm.Id
    );
    insert wo;

    insert new Quick_Book_Work_Order_Line_Item__c(
      Name = 'Labor',
      Work_Order__c = wo.Id,
      Service_Team_Member__c = stm.Id,
      Description__c = 'Paint',
      Quantity__c = 1,
      Rate__c = 50,
      Amount__c = 50
    );

    String withLineItems = MassSendEmailBuilder.applyLineItemsPlaceholder(
      'Items: [LINE_ITEMS]',
      wo.Id,
      stm.Id
    );
    System.assert(
      withLineItems.contains('Paint') || withLineItems.contains('Labor'),
      withLineItems
    );

    String withAddress = MassSendEmailBuilder.applyAccountAddressPlaceholder(
      'Addr: [ACCOUNT_ADDRESS]',
      wo.Id,
      true
    );
    System.assert(withAddress.contains('Austin'), withAddress);

    System.assertEquals(
      'Hello',
      MassSendEmailBuilder.softenCaseMergeFailures('Hello')
    );
    System.assertEquals(
      null,
      MassSendEmailBuilder.prepareForRenderEmailTemplate(null, null)
    );

    MassSendEmailBuilder.loadNamedContractSendPdfCcEmails();
    MassSendEmailBuilder.resolveRegionalManagerEmailsByAccount(
      new Set<Id>{ acc.Id }
    );
    MassSendEmailBuilder.resolveLeadGeneratorEmailsByAccount(
      new Set<Id>{ acc.Id }
    );
    MassSendEmailBuilder.SelectedBidCc emptySelectedCc = MassSendEmailBuilder.resolveCcFromSelectedBids(
      new Set<Id>()
    );
    System.assertEquals(0, emptySelectedCc.leadOwnerEmailsByAccount.size());
    System.assertEquals(0, emptySelectedCc.leadGeneratorEmailsByAccount.size());

    List<String> stringOverloadCc = MassSendEmailBuilder.buildContractSendPdfCcAddresses(
      'to@example.com',
      'rm@example.com',
      'lg@example.com',
      new List<String>{ 'a@example.com', 'to@example.com' }
    );
    System.assertEquals(3, stringOverloadCc.size(), stringOverloadCc);
    System.assert(stringOverloadCc.contains('rm@example.com'));
    System.assert(stringOverloadCc.contains('lg@example.com'));
    System.assert(stringOverloadCc.contains('a@example.com'));
    System.assert(!stringOverloadCc.contains('to@example.com'));

    List<String> listOverloadCc = MassSendEmailBuilder.buildContractSendPdfCcAddresses(
      null,
      new List<String>{ 'rm@example.com' },
      new List<String>{ 'lg@example.com' },
      new List<String>{ 'a@example.com' }
    );
    System.assertEquals(3, listOverloadCc.size(), listOverloadCc);

    List<EmailTemplate> templates = [
      SELECT Id
      FROM EmailTemplate
      WHERE IsActive = TRUE
      LIMIT 1
    ];
    if (!templates.isEmpty()) {
      MassSendEmailBuilder.resolveEmailTemplateDeveloperName(templates[0].Id);
    }
  }

  @isTest
  static void buildEmail_parsedContent_workOrderMailbox() {
    Account acc = new Account(Name = 'MSB Build Acc');
    insert acc;
    Contact c = new Contact(
      LastName = 'MSB',
      Email = 'msb.build@example.com',
      AccountId = acc.Id
    );
    insert c;

    WorkOrder wo = new WorkOrder(
      Subject = 'MSB Build WO',
      Status = 'New',
      Priority = 'Medium',
      AccountId = acc.Id
    );
    insert wo;

    User me = [
      SELECT Id, Email, Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ];

    MassSendEmailBuilder.BuildRequest req = new MassSendEmailBuilder.BuildRequest();
    req.toAddresses = new List<String>{ c.Email };
    req.whatId = wo.Id;
    req.parsedContent = true;
    req.rowSubject = 'Subj';
    req.rowBody = '<p>Hello</p>';
    req.sendingUser = me;
    req.useWorkOrderMailbox = true;
    req.applyWorkOrderPlaceholders = false;

    Test.startTest();
    MassSendEmailBuilder.EmailBuildResult result = MassSendEmailBuilder.buildEmail(
      req
    );
    Test.stopTest();

    System.assertEquals(null, result.errorMessage, 'buildEmail should succeed');
    System.assertNotEquals(null, result.mail);
  }
}
