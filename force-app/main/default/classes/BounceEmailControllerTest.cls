@IsTest
private class BounceEmailControllerTest {
  @TestSetup
  static void setupTestData() {
    // Create test Account
    Account testAccount = new Account(Name = 'Test Account');
    insert testAccount;

    // Create test Contact with bounced email
    Contact testContact = new Contact(
      FirstName = 'Test',
      LastName = 'Contact',
      Email = 'contact@example.com',
      AccountId = testAccount.Id
    );
    insert testContact;

    // Create Contract_Bid__c with valid stage for testAccount
    Contract_Bid__c testContract = new Contract_Bid__c(
      Name = 'Test Contract Bid',
      Customer__c = testAccount.Id,
      Stage__c = 'Information Verified'
    );
    insert testContract;
  }

  // Helper method to create unique test user for Regional Manager
  private static User createTestUser() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    String uniqueIdentifier =
      String.valueOf(Datetime.now().getTime()) + Crypto.getRandomInteger();

    return new User(
      Alias = 'test' + uniqueIdentifier.left(4),
      Email = 'testuser' + uniqueIdentifier + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'TestUser' + uniqueIdentifier.left(6),
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'testuser' + uniqueIdentifier + '@example.com.test'
    );
  }

  // Helper method to create EmailMessage record
  private static EmailMessage createEmailMessage(
    Id relatedToId,
    String toAddress
  ) {
    EmailMessage em = new EmailMessage();
    em.RelatedToId = relatedToId;
    em.ToAddress = toAddress;
    em.Subject = 'Test Email';
    em.TextBody = 'Test body';
    em.Status = '3'; // Bounced status
    return em;
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_ByAccountId() {
    // Get test data
    Account testAccount = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Account'
      LIMIT 1
    ];

    Test.startTest();

    // Create EmailMessage with RelatedToId pointing to Account
    EmailMessage bouncedEmail = createEmailMessage(
      testAccount.Id,
      'contact@example.com'
    );
    insert bouncedEmail;

    // Call handler method
    BounceEmailFromEmailMessageHandler.handle(
      new List<EmailMessage>{ bouncedEmail }
    );

    Test.stopTest();

    // Verify Contract_Bid__c stage was updated
    Contract_Bid__c updatedContract = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Name = 'Test Contract Bid'
      LIMIT 1
    ];
    System.assertEquals(
      'Need Contact Verification',
      updatedContract.Stage__c,
      'Contract Bid stage should be updated to "Need Contact Verification"'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_EmptyList() {
    Test.startTest();
    // Test with empty list
    BounceEmailFromEmailMessageHandler.handle(new List<EmailMessage>());
    Test.stopTest();

    // No assertions needed, just making sure no errors occur
    System.assert(true, 'Method should handle empty list without errors');
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_NoMatchingStage() {
    // Get test data
    Account testAcc = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Account'
      LIMIT 1
    ];

    // Create Contract_Bid__c with stage that is already 'Need Contact Verification'
    // Handler only updates contracts where Stage__c != 'Need Contact Verification'
    Contract_Bid__c nonMatchingContract = new Contract_Bid__c(
      Name = 'Non-Matching Contract',
      Customer__c = testAcc.Id,
      Stage__c = 'Need Contact Verification'
    );
    insert nonMatchingContract;

    Test.startTest();

    // Create EmailMessage with RelatedToId pointing to Account
    EmailMessage bouncedEmail = createEmailMessage(
      testAcc.Id,
      'contact@example.com'
    );
    insert bouncedEmail;

    BounceEmailFromEmailMessageHandler.handle(
      new List<EmailMessage>{ bouncedEmail }
    );

    Test.stopTest();

    // Verify contract with 'Need Contact Verification' stage was NOT updated
    Contract_Bid__c unchangedContract = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Name = 'Non-Matching Contract'
      LIMIT 1
    ];
    System.assertEquals(
      'Need Contact Verification',
      unchangedContract.Stage__c,
      'Contract Bid with "Need Contact Verification" stage should not be updated again'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_MultipleContacts() {
    // Get test data
    Account testAccount = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Account'
      LIMIT 1
    ];

    // Create another account
    Account anotherAccount = new Account(Name = 'Another Account');
    insert anotherAccount;

    // Create Contract_Bid__c for anotherAccount
    Contract_Bid__c anotherContract = new Contract_Bid__c(
      Name = 'Another Contract',
      Customer__c = anotherAccount.Id,
      Stage__c = 'Information Verified'
    );
    insert anotherContract;

    Test.startTest();

    // Create EmailMessages for both accounts
    EmailMessage bouncedEmail1 = createEmailMessage(
      testAccount.Id,
      'contact@example.com'
    );
    EmailMessage bouncedEmail2 = createEmailMessage(
      anotherAccount.Id,
      'another@example.com'
    );
    insert new List<EmailMessage>{ bouncedEmail1, bouncedEmail2 };

    BounceEmailFromEmailMessageHandler.handle(
      new List<EmailMessage>{ bouncedEmail1, bouncedEmail2 }
    );

    Test.stopTest();

    // Verify both contracts were updated
    List<Contract_Bid__c> updatedContracts = [
      SELECT Id, Stage__c, Name
      FROM Contract_Bid__c
      WHERE Stage__c = 'Need Contact Verification'
    ];
    System.assert(
      updatedContracts.size() >= 2,
      'Both contracts should be updated'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_NoMatchingAccounts() {
    // Create EmailMessage with no RelatedToId and email that doesn't match any Contact
    Test.startTest();

    EmailMessage bouncedEmail = createEmailMessage(null, 'orphan@example.com');
    insert bouncedEmail;

    BounceEmailFromEmailMessageHandler.handle(
      new List<EmailMessage>{ bouncedEmail }
    );

    Test.stopTest();

    // Verify no contracts were updated (handler should return early when no AccountIds found)
    List<Contract_Bid__c> updatedContracts = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Stage__c = 'Need Contact Verification'
    ];
    // Should be 0 since handler returns early when no AccountIds resolved
    System.assertEquals(
      0,
      updatedContracts.size(),
      'No contracts should be updated when no AccountIds can be resolved'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_ContactWithoutEmail() {
    // Get test account
    Account testAcc = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Account'
      LIMIT 1
    ];

    Test.startTest();

    // Create EmailMessage with RelatedToId pointing to Account (primary method)
    // This should work even without ToAddress
    EmailMessage bouncedEmail = createEmailMessage(testAcc.Id, null);
    insert bouncedEmail;

    BounceEmailFromEmailMessageHandler.handle(
      new List<EmailMessage>{ bouncedEmail }
    );

    Test.stopTest();

    // Should find account by RelatedToId
    Contract_Bid__c updatedContract = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Name = 'Test Contract Bid'
      LIMIT 1
    ];
    System.assertEquals(
      'Need Contact Verification',
      updatedContract.Stage__c,
      'Contract Bid should be updated when RelatedToId points to Account'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_ContactWithoutId() {
    // Create EmailMessage with null RelatedToId and no matching email
    Test.startTest();

    EmailMessage bouncedEmail = createEmailMessage(
      null,
      'nonexistent@example.com'
    );
    insert bouncedEmail;

    BounceEmailFromEmailMessageHandler.handle(
      new List<EmailMessage>{ bouncedEmail }
    );

    Test.stopTest();

    // Should handle gracefully without errors (returns early when no AccountIds found)
    System.assert(
      true,
      'Method should handle EmailMessage without RelatedToId and no matching email'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_WithRegionalManager() {
    // Create test user for Regional Manager
    User regionalManager = createTestUser();
    insert regionalManager;

    // Get test account and set Regional Manager
    Account testAcc = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Account'
      LIMIT 1
    ];
    testAcc.Regional_Manager__c = regionalManager.Id;
    update testAcc;

    // Note: CustomNotificationType cannot be created via DML in test classes
    // The method will handle its absence gracefully
    // If CustomNotificationType exists in org, notifications will be sent
    // If not, the method will continue without errors

    Test.startTest();

    // Create EmailMessage with RelatedToId pointing to Account
    EmailMessage bouncedEmail = createEmailMessage(
      testAcc.Id,
      'contact@example.com'
    );
    insert bouncedEmail;

    BounceEmailFromEmailMessageHandler.handle(
      new List<EmailMessage>{ bouncedEmail }
    );

    Test.stopTest();

    // Verify contract was updated
    Contract_Bid__c updatedContract = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Name = 'Test Contract Bid'
      LIMIT 1
    ];
    System.assertEquals(
      'Need Contact Verification',
      updatedContract.Stage__c,
      'Contract Bid stage should be updated'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_AccountWithoutRegionalManager() {
    // Get test account (should not have Regional Manager)
    Account testAcc = [
      SELECT Id, Regional_Manager__c
      FROM Account
      WHERE Name = 'Test Account'
      LIMIT 1
    ];
    // Ensure no Regional Manager
    testAcc.Regional_Manager__c = null;
    update testAcc;

    Test.startTest();

    // Create EmailMessage with RelatedToId pointing to Account
    EmailMessage bouncedEmail = createEmailMessage(
      testAcc.Id,
      'contact@example.com'
    );
    insert bouncedEmail;

    BounceEmailFromEmailMessageHandler.handle(
      new List<EmailMessage>{ bouncedEmail }
    );

    Test.stopTest();

    // Verify contract was still updated (notification might not be sent, but stage should change)
    Contract_Bid__c updatedContract = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Name = 'Test Contract Bid'
      LIMIT 1
    ];
    System.assertEquals(
      'Need Contact Verification',
      updatedContract.Stage__c,
      'Contract Bid stage should be updated even without Regional Manager'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_ByContractBidRelatedToId() {
    // Test that RelatedToId can point to Contract_Bid__c (not just Account)
    Account testAcc = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Account'
      LIMIT 1
    ];

    // Create Contract_Bid__c for testAcc
    Contract_Bid__c testContract = new Contract_Bid__c(
      Name = 'Contract Bid RelatedTo Test',
      Customer__c = testAcc.Id,
      Stage__c = 'Information Verified'
    );
    insert testContract;

    Test.startTest();

    // Create EmailMessage with RelatedToId pointing to Contract_Bid__c
    EmailMessage bouncedEmail = createEmailMessage(
      testContract.Id,
      'contact@example.com'
    );
    insert bouncedEmail;

    BounceEmailFromEmailMessageHandler.handle(
      new List<EmailMessage>{ bouncedEmail }
    );

    Test.stopTest();

    // Verify contract was updated (handler resolves Account via Contract_Bid__c.Customer__c)
    Contract_Bid__c updatedContract = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Name = 'Contract Bid RelatedTo Test'
      LIMIT 1
    ];
    System.assertEquals(
      'Need Contact Verification',
      updatedContract.Stage__c,
      'Contract Bid should be updated when RelatedToId points to Contract_Bid__c'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_FallbackByEmail() {
    // Test fallback mechanism: when RelatedToId is null, use Contact.Email from ToAddress
    Account testAcc = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Account'
      LIMIT 1
    ];

    Contact testContact = [
      SELECT Id, Email, AccountId
      FROM Contact
      WHERE LastName = 'Contact'
      LIMIT 1
    ];

    // Create Contract_Bid__c for testAcc
    Contract_Bid__c testContract = new Contract_Bid__c(
      Name = 'Fallback Email Test Contract',
      Customer__c = testAcc.Id,
      Stage__c = 'Information Verified'
    );
    insert testContract;

    Test.startTest();

    // Create EmailMessage with null RelatedToId but ToAddress matching Contact.Email
    EmailMessage bouncedEmail = createEmailMessage(null, testContact.Email);
    insert bouncedEmail;

    BounceEmailFromEmailMessageHandler.handle(
      new List<EmailMessage>{ bouncedEmail }
    );

    Test.stopTest();

    // Verify contract was updated via fallback (Contact.Email -> AccountId)
    Contract_Bid__c updatedContract = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Name = 'Fallback Email Test Contract'
      LIMIT 1
    ];
    System.assertEquals(
      'Need Contact Verification',
      updatedContract.Stage__c,
      'Contract Bid should be updated via fallback when RelatedToId is null but ToAddress matches Contact.Email'
    );
  }
}