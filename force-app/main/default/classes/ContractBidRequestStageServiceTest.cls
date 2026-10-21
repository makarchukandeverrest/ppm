@IsTest
private class ContractBidRequestStageServiceTest {
  @IsTest
  static void requestTaskMovesBidQualifiedToContractRequested() {
    User leadUser = createLeadUser();

    System.runAs(leadUser) {
      Contract_Bid__c bid = insertBid();

      Test.startTest();
      insert new Task(
        Subject = ContractBidRequestStageService.REQUEST_SUBJECT,
        WhatId = bid.Id,
        Status = 'Not Started'
      );
      Test.stopTest();

      bid = [SELECT Stage__c FROM Contract_Bid__c WHERE Id = :bid.Id];
      System.assertEquals('Contract Requested', bid.Stage__c);
    }
  }

  @IsTest
  static void otherTaskLeavesBidQualified() {
    Contract_Bid__c bid = insertBid();

    Test.startTest();
    insert new Task(
      Subject = 'Verify contact info',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    Test.stopTest();

    bid = [SELECT Stage__c FROM Contract_Bid__c WHERE Id = :bid.Id];
    System.assertEquals('Contact Made', bid.Stage__c);
  }

  @IsTest
  static void taskLifecycleCoversTrigger() {
    Contract_Bid__c bid = insertBid();
    Account otherCustomer = new Account(Name = 'Other Request Customer');
    insert otherCustomer;
    Contract_Bid__c otherBid = new Contract_Bid__c(
      Name = 'Other Request Bid',
      Customer__c = otherCustomer.Id,
      Stage__c = 'Contact Made'
    );
    insert otherBid;

    Task taskRecord = new Task(
      Subject = 'Verify contact info',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    insert taskRecord;

    Test.startTest();
    taskRecord.WhatId = otherBid.Id;
    update taskRecord;
    delete taskRecord;
    undelete taskRecord;
    Test.stopTest();

    bid = [SELECT Stage__c FROM Contract_Bid__c WHERE Id = :bid.Id];
    System.assertEquals('Contact Made', bid.Stage__c);
  }

  private static User createLeadUser() {
    Profile adminProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    String uniqueName =
      'lead.stage.' +
      DateTime.now().getTime() +
      '@example.com';
    User leadUser = new User(
      Alias = 'ldstage',
      Email = uniqueName,
      EmailEncodingKey = 'UTF-8',
      LastName = 'LeadStage',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = adminProfile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = uniqueName
    );
    insert leadUser;
    insert new PermissionSetAssignment(
      AssigneeId = leadUser.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Change_Bid_Stage_Lead'
        LIMIT 1
      ]
      .Id
    );
    return leadUser;
  }

  private static Contract_Bid__c insertBid() {
    Account customer = new Account(Name = 'Request Stage Customer');
    insert customer;
    Contact primaryContact = new Contact(
      LastName = 'Primary',
      AccountId = customer.Id
    );
    insert primaryContact;
    customer.Primary_Contact__c = primaryContact.Id;
    update customer;

    Management_Company__c company = new Management_Company__c(
      Name = 'Request Stage Company'
    );
    insert company;

    Contract_Bid__c bid = new Contract_Bid__c(
      Name = 'Request Stage Bid',
      Customer__c = customer.Id,
      Management_Company__c = company.Id,
      Stage__c = 'Contact Made',
      Info_Verified__c = true
    );
    insert bid;
    return bid;
  }
}
