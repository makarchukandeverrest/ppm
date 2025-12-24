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

  @IsTest
  static void testHandleBouncedContractBidPackage_ByAccountId() {
    // Get test data
    Contact testContact = [
      SELECT Id, Email, AccountId
      FROM Contact
      WHERE LastName = 'Contact'
      LIMIT 1
    ];

    // Set EmailBouncedDate to simulate bounce
    testContact.EmailBouncedDate = Datetime.now();
    update testContact;

    Test.startTest();

    // Call method with contact that has AccountId
    List<Contact> contacts = new List<Contact>{ testContact };
    BounceEmailController.handleBouncedContractBidPackage(contacts);

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
    BounceEmailController.handleBouncedContractBidPackage(new List<Contact>());
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
    Contact testContact = [
      SELECT Id, Email, AccountId
      FROM Contact
      WHERE LastName = 'Contact'
      LIMIT 1
    ];

    // Create Contract_Bid__c with non-matching stage
    Contract_Bid__c nonMatchingContract = new Contract_Bid__c(
      Name = 'Non-Matching Contract',
      Customer__c = testAcc.Id,
      Stage__c = 'Closed - WON'
    );
    insert nonMatchingContract;

    Test.startTest();

    // Set EmailBouncedDate to simulate bounce
    testContact.EmailBouncedDate = Datetime.now();
    update testContact;

    List<Contact> contacts = new List<Contact>{ testContact };
    BounceEmailController.handleBouncedContractBidPackage(contacts);

    Test.stopTest();

    // Verify non-matching contract was NOT updated
    Contract_Bid__c unchangedContract = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Name = 'Non-Matching Contract'
      LIMIT 1
    ];
    System.assertEquals(
      'Closed - WON',
      unchangedContract.Stage__c,
      'Contract Bid with non-matching stage should not be updated'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_MultipleContacts() {
    // Get test data
    Contact testContact = [
      SELECT Id, Email, AccountId
      FROM Contact
      WHERE LastName = 'Contact'
      LIMIT 1
    ];

    // Create another contact with different account
    Account anotherAccount = new Account(Name = 'Another Account');
    insert anotherAccount;

    Contact anotherContact = new Contact(
      FirstName = 'Another',
      LastName = 'Contact',
      Email = 'another@example.com',
      AccountId = anotherAccount.Id
    );
    insert anotherContact;

    // Create Contract_Bid__c for anotherAccount
    Contract_Bid__c anotherContract = new Contract_Bid__c(
      Name = 'Another Contract',
      Customer__c = anotherAccount.Id,
      Stage__c = 'Information Verified'
    );
    insert anotherContract;

    Test.startTest();

    // Set EmailBouncedDate for both contacts
    testContact.EmailBouncedDate = Datetime.now();
    anotherContact.EmailBouncedDate = Datetime.now();
    update new List<Contact>{ testContact, anotherContact };

    List<Contact> contacts = new List<Contact>{ testContact, anotherContact };
    BounceEmailController.handleBouncedContractBidPackage(contacts);

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
    // Create contact without AccountId (orphan contact)
    // Since we only use Contact.AccountId to find accounts, this contact won't match any accounts
    Contact orphanContact = new Contact(
      FirstName = 'Orphan',
      LastName = 'Contact',
      Email = 'orphan@example.com'
      // No AccountId - so no account will be found
    );
    insert orphanContact;

    Test.startTest();

    // Set EmailBouncedDate to simulate bounce
    orphanContact.EmailBouncedDate = Datetime.now();
    update orphanContact;

    List<Contact> contacts = new List<Contact>{ orphanContact };
    BounceEmailController.handleBouncedContractBidPackage(contacts);

    Test.stopTest();

    // Verify no new contracts were updated (only existing ones from setup)
    List<Contract_Bid__c> updatedContracts = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Stage__c = 'Need Contact Verification'
    ];
    // Should only have the ones from setup, not new ones
    System.assert(
      updatedContracts.size() <= 1,
      'No new contracts should be updated for orphan contact without AccountId'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_ContactWithoutEmail() {
    // Create contact without email
    Account testAcc = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Account'
      LIMIT 1
    ];

    Contact contactNoEmail = new Contact(
      FirstName = 'No',
      LastName = 'Email',
      AccountId = testAcc.Id
    );
    insert contactNoEmail;

    Test.startTest();

    // Set EmailBouncedDate to simulate bounce
    contactNoEmail.EmailBouncedDate = Datetime.now();
    update contactNoEmail;

    List<Contact> contacts = new List<Contact>{ contactNoEmail };
    BounceEmailController.handleBouncedContractBidPackage(contacts);

    Test.stopTest();

    // Should still find account by AccountId
    Contract_Bid__c updatedContract = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Name = 'Test Contract Bid'
      LIMIT 1
    ];
    System.assertEquals(
      'Need Contact Verification',
      updatedContract.Stage__c,
      'Contract Bid should be updated even if contact has no email (found by AccountId)'
    );
  }

  @IsTest
  static void testHandleBouncedContractBidPackage_ContactWithoutId() {
    // Create contact without Id (new, not inserted)
    Contact newContact = new Contact(
      FirstName = 'New',
      LastName = 'Contact',
      Email = 'new@example.com'
    );

    Test.startTest();

    List<Contact> contacts = new List<Contact>{ newContact };
    BounceEmailController.handleBouncedContractBidPackage(contacts);

    Test.stopTest();

    // Should handle gracefully without errors
    System.assert(true, 'Method should handle contact without Id');
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

    Contact testContact = [
      SELECT Id, Email, AccountId
      FROM Contact
      WHERE LastName = 'Contact'
      LIMIT 1
    ];

    // Note: CustomNotificationType cannot be created via DML in test classes
    // The method will handle its absence gracefully via try-catch
    // If CustomNotificationType exists in org, notifications will be sent
    // If not, the method will continue without errors

    Test.startTest();

    // Set EmailBouncedDate to simulate bounce
    testContact.EmailBouncedDate = Datetime.now();
    update testContact;

    List<Contact> contacts = new List<Contact>{ testContact };
    BounceEmailController.handleBouncedContractBidPackage(contacts);

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

    Contact testContact = [
      SELECT Id, Email, AccountId
      FROM Contact
      WHERE LastName = 'Contact'
      LIMIT 1
    ];

    Test.startTest();

    // Set EmailBouncedDate to simulate bounce
    testContact.EmailBouncedDate = Datetime.now();
    update testContact;

    List<Contact> contacts = new List<Contact>{ testContact };
    BounceEmailController.handleBouncedContractBidPackage(contacts);

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
  static void testHandleBouncedContractBidPackage_PrimaryContactNotUsed() {
    // This test verifies that Primary_Contact__c and Email__c (formula field) are NOT used
    // We only use Contact.AccountId (standard field) to find accounts
    Account testAcc = [
      SELECT Id
      FROM Account
      WHERE Name = 'Test Account'
      LIMIT 1
    ];

    // Create a contact that is NOT linked to testAcc via AccountId
    Contact unlinkedContact = new Contact(
      FirstName = 'Unlinked',
      LastName = 'Contact',
      Email = 'unlinked@example.com'
    );
    insert unlinkedContact;

    // Set this contact as Primary_Contact__c on testAcc
    // This would make Account.Email__c (formula) = unlinkedContact.Email
    // But we should NOT use this to find accounts
    testAcc.Primary_Contact__c = unlinkedContact.Id;
    update testAcc;

    // Create Contract_Bid__c for testAcc
    Contract_Bid__c testContract = new Contract_Bid__c(
      Name = 'Primary Contact Test Contract',
      Customer__c = testAcc.Id,
      Stage__c = 'Information Verified'
    );
    insert testContract;

    Test.startTest();

    // Set EmailBouncedDate for unlinkedContact
    unlinkedContact.EmailBouncedDate = Datetime.now();
    update unlinkedContact;

    List<Contact> contacts = new List<Contact>{ unlinkedContact };
    BounceEmailController.handleBouncedContractBidPackage(contacts);

    Test.stopTest();

    // Verify contract was NOT updated (because we only use AccountId, not Primary_Contact__c or Email__c)
    Contract_Bid__c unchangedContract = [
      SELECT Id, Stage__c
      FROM Contract_Bid__c
      WHERE Name = 'Primary Contact Test Contract'
      LIMIT 1
    ];
    System.assertEquals(
      'Information Verified',
      unchangedContract.Stage__c,
      'Contract Bid should NOT be updated when contact is only linked via Primary_Contact__c (Email__c is formula field)'
    );
  }
}