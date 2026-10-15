@IsTest
private class ContractBidActivityStampServiceTest {
  @IsTest
  static void stampsBidEmailsCallsEventsAndIgnoresDraftsAndEmailTasks() {
    Contract_Bid__c bid = insertBid('Information Verified');
    Datetime sentAt = clock(-4);
    Datetime sentLaterAt = clock(-1);
    Datetime receivedAt = clock(-2);

    Test.startTest();
    insert new List<EmailMessage>{
      email(bid.Id, false, sentAt, '3'),
      email(bid.Id, false, sentLaterAt, '3'),
      email(bid.Id, true, receivedAt, '3'),
      email(bid.Id, false, clock(-3), '5')
    };
    Task call = task(bid.Id, 'Call', 'Log a call');
    insert call;
    insert task(bid.Id, 'Email', 'Email task');
    insert event(bid.Id);
    Test.stopTest();

    call = [SELECT CreatedDate, TaskSubtype FROM Task WHERE Id = :call.Id];
    Task emailTask = [
      SELECT TaskSubtype
      FROM Task
      WHERE WhatId = :bid.Id AND Subject = 'Email task'
    ];
    Contract_Bid__c stamped = reload(bid.Id);

    System.assertEquals(sentLaterAt, stamped.Last_Email_Sent__c);
    System.assertEquals(receivedAt, stamped.Last_Email_Received__c);
    System.assertEquals(3, stamped.Email_Messages_Count__c);
    System.assertEquals(call.CreatedDate, stamped.Latest_Call_Log__c);
    Integer expectedTotal = emailTask.TaskSubtype == 'Email' ? 5 : 6;
    System.assertEquals(expectedTotal, stamped.Total_Activities_Count__c);
  }

  @IsTest
  static void accountActivityCountsOnlyWhileBidIsOpen() {
    Account customer = new Account(Name = 'Activity Customer');
    insert customer;
    Contract_Bid__c openBid = bid(
      customer.Id,
      'Information Verified',
      'Open Bid'
    );
    Contract_Bid__c closedBid = bid(customer.Id, 'Closed - LOST', 'Closed Bid');
    insert new List<Contract_Bid__c>{ openBid, closedBid };

    Datetime accountSentAt = clock(-2);
    Datetime bidReceivedAt = clock(-1);

    Test.startTest();
    insert new List<EmailMessage>{
      email(customer.Id, false, accountSentAt, '3'),
      email(openBid.Id, true, bidReceivedAt, '3')
    };
    insert new FeedItem(
      ParentId = customer.Id,
      Body = 'Account note',
      Type = 'TextPost'
    );
    Test.stopTest();

    Contract_Bid__c openStamped = reload(openBid.Id);
    Contract_Bid__c closedStamped = reload(closedBid.Id);

    System.assertEquals(accountSentAt, openStamped.Last_Email_Sent__c);
    System.assertEquals(bidReceivedAt, openStamped.Last_Email_Received__c);
    System.assertEquals(2, openStamped.Email_Messages_Count__c);
    System.assertEquals(2, openStamped.Total_Activities_Count__c);
    System.assertNotEquals(null, openStamped.Latest_Post__c);

    System.assertEquals(null, closedStamped.Email_Messages_Count__c);
    System.assertEquals(null, closedStamped.Total_Activities_Count__c);
    System.assertEquals(null, closedStamped.Latest_Post__c);
  }

  @IsTest
  static void movingAndRemovingActivityMovesTheStamp() {
    Contract_Bid__c source = insertBid('Information Verified');
    Contract_Bid__c target = insertBid('Contact Made');
    Datetime sentAt = clock(-1);

    EmailMessage message = email(source.Id, false, sentAt, '3');
    insert message;
    Task call = task(source.Id, 'Call', 'Move me');
    insert call;
    Event meeting = event(source.Id);
    insert meeting;

    System.assertEquals(1, reload(source.Id).Email_Messages_Count__c);
    System.assertEquals(3, reload(source.Id).Total_Activities_Count__c);

    Datetime sentLaterAt = clock(0);
    Test.startTest();
    message.MessageDate = sentLaterAt;
    update message;
    call.WhatId = target.Id;
    update call;
    meeting.WhatId = target.Id;
    update meeting;
    Test.stopTest();

    Contract_Bid__c sourceStamped = reload(source.Id);
    Contract_Bid__c targetStamped = reload(target.Id);
    System.assertEquals(sentLaterAt, sourceStamped.Last_Email_Sent__c);
    System.assertEquals(1, sourceStamped.Email_Messages_Count__c);
    System.assertEquals(1, sourceStamped.Total_Activities_Count__c);
    System.assertEquals(null, sourceStamped.Latest_Call_Log__c);
    System.assertEquals(0, targetStamped.Email_Messages_Count__c);
    System.assertEquals(2, targetStamped.Total_Activities_Count__c);
    System.assertNotEquals(null, targetStamped.Latest_Call_Log__c);
  }

  @IsTest
  static void deleteAndUndeleteRestoresEmailAndClearsPost() {
    Contract_Bid__c bid = insertBid('Information Verified');
    EmailMessage message = email(bid.Id, false, clock(-1), '3');
    insert message;
    FeedItem post = new FeedItem(
      ParentId = bid.Id,
      Body = 'Bid note',
      Type = 'TextPost'
    );
    insert post;
    System.assertEquals(1, reload(bid.Id).Email_Messages_Count__c);
    System.assertNotEquals(null, reload(bid.Id).Latest_Post__c);

    Test.startTest();
    delete message;
    delete post;
    System.assertEquals(0, reload(bid.Id).Email_Messages_Count__c);
    System.assertEquals(null, reload(bid.Id).Latest_Post__c);
    undelete message;
    Test.stopTest();

    Contract_Bid__c stamped = reload(bid.Id);
    System.assertEquals(1, stamped.Email_Messages_Count__c);
    System.assertNotEquals(null, stamped.Last_Email_Sent__c);
    System.assertEquals(null, stamped.Latest_Post__c);
  }

  @IsTest
  static void deleteAndUndeleteTaskAndEvent() {
    Contract_Bid__c bid = insertBid('Information Verified');
    Task call = task(bid.Id, 'Call', 'Delete me');
    insert call;
    Event meeting = event(bid.Id);
    insert meeting;
    System.assertEquals(2, reload(bid.Id).Total_Activities_Count__c);

    Test.startTest();
    delete new List<SObject>{ call, meeting };
    System.assertEquals(0, reload(bid.Id).Total_Activities_Count__c);
    undelete new List<SObject>{ call, meeting };
    Test.stopTest();

    System.assertEquals(2, reload(bid.Id).Total_Activities_Count__c);
  }

  @IsTest
  static void stageChangeStampsPreviousStageWithoutRecalculatingOnRename() {
    Contract_Bid__c bid = insertBid('Information Verified');

    Test.startTest();
    bid.Stage__c = 'Contact Made';
    update bid;
    Contract_Bid__c stamped = reload(bid.Id);
    System.assertEquals('Information Verified', stamped.Previous_Stage__c);
    System.assertNotEquals(null, stamped.Last_Stage_Change__c);

    Datetime stampedAt = stamped.Last_Stage_Change__c;
    bid.Name = 'Renamed Bid';
    update bid;
    Test.stopTest();

    stamped = reload(bid.Id);
    System.assertEquals('Information Verified', stamped.Previous_Stage__c);
    System.assertEquals(stampedAt, stamped.Last_Stage_Change__c);
  }

  @IsTest
  static void unrelatedRecordsDoNotStampTheBid() {
    Contract_Bid__c bid = insertBid('Information Verified');
    Account customer = [SELECT Id FROM Account WHERE Id = :bid.Customer__c];
    Opportunity proposal = new Opportunity(
      Name = 'Unrelated Proposal',
      AccountId = customer.Id,
      CloseDate = Date.today().addDays(30),
      StageName = 'Draft',
      Is_Active__c = true
    );
    insert proposal;

    Test.startTest();
    insert email(proposal.Id, false, clock(-1), '3');
    insert new Task(
      Subject = 'No parent',
      Status = 'Open',
      Priority = 'Normal'
    );
    insert new Event(
      Subject = 'No parent',
      StartDateTime = System.now(),
      EndDateTime = System.now().addHours(1)
    );
    EmailMessage bidEmail = email(bid.Id, false, clock(-1), '3');
    insert bidEmail;
    bidEmail.Subject = 'Subject only';
    update bidEmail;
    Test.stopTest();

    Contract_Bid__c stamped = reload(bid.Id);
    System.assertEquals(1, stamped.Email_Messages_Count__c);
    System.assertEquals(1, stamped.Total_Activities_Count__c);
  }

  private static Contract_Bid__c insertBid(String stage) {
    Account customer = new Account(Name = 'Customer ' + stage);
    insert customer;
    Contract_Bid__c bid = bid(customer.Id, stage, 'Bid ' + stage);
    insert bid;
    return bid;
  }

  private static Contract_Bid__c bid(Id customerId, String stage, String name) {
    return new Contract_Bid__c(
      Name = name,
      Customer__c = customerId,
      Stage__c = stage
    );
  }

  private static EmailMessage email(
    Id relatedToId,
    Boolean incoming,
    Datetime sentAt,
    String status
  ) {
    return new EmailMessage(
      RelatedToId = relatedToId,
      Incoming = incoming,
      MessageDate = sentAt,
      Status = status,
      Subject = 'Activity stamp',
      FromAddress = 'sender@example.com',
      ToAddress = 'recipient@example.com',
      TextBody = 'Body'
    );
  }

  private static Task task(Id whatId, String subtype, String subject) {
    return new Task(
      WhatId = whatId,
      Subject = subject,
      TaskSubtype = subtype,
      Status = 'Open',
      Priority = 'Normal'
    );
  }

  private static Event event(Id whatId) {
    return new Event(
      WhatId = whatId,
      Subject = 'Meeting',
      StartDateTime = System.now(),
      EndDateTime = System.now().addHours(1)
    );
  }

  private static Datetime clock(Integer dayOffset) {
    return Datetime.newInstance(
      Date.today().addDays(dayOffset),
      Time.newInstance(10, 0, 0, 0)
    );
  }

  private static Contract_Bid__c reload(Id bidId) {
    return [
      SELECT
        Last_Email_Sent__c,
        Last_Email_Received__c,
        Email_Messages_Count__c,
        Latest_Call_Log__c,
        Total_Activities_Count__c,
        Latest_Post__c,
        Previous_Stage__c,
        Last_Stage_Change__c
      FROM Contract_Bid__c
      WHERE Id = :bidId
    ];
  }
}
