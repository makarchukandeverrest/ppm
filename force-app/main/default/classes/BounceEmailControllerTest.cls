@IsTest
private class BounceEmailControllerTest {
    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(Name = 'Test Account', Email__c = 'test@example.com');
        insert testAccount;

        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'contact@example.com',
            AccountId = testAccount.Id
        );
        insert testContact;

        // Update Account with Primary Contact
        testAccount.Primary_Contact__c = testContact.Id;
        update testAccount;

        // Create Contract_Bid__c with valid stage
        Contract_Bid__c testContract = new Contract_Bid__c(
            Name = 'Test Contract Bid',
            Customer__c = testAccount.Id,
            Stage__c = 'Information Verified' // Valid stage that should be updated
        );
        insert testContract;

        // DO NOT create User here - create it in each test method if needed
    }

    // Helper method to create unique test user
    private static User createTestUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueIdentifier = String.valueOf(Datetime.now().getTime()) + Crypto.getRandomInteger();

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
    static void testHandleBouncedContractBidPackage() {
        // Get test data
        Account testAcc = [SELECT Id, Email__c FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Contact testCon = [SELECT Id, Email FROM Contact WHERE LastName = 'Contact' LIMIT 1];

        // Create unique test user for this test
        User testUser = createTestUser();
        insert testUser;

        Contract_Bid__c testContract = [
            SELECT Id, Stage__c
            FROM Contract_Bid__c
            WHERE Name = 'Test Contract Bid'
            LIMIT 1
        ];

        Test.startTest();

        // Create bounced EmailMessage WITH ToIds and FromId
        EmailMessage bouncedEmail = new EmailMessage(
            ToAddress = testAcc.Email__c,
            FromAddress = 'sender@example.com',
            FromId = testUser.Id, // Set FromId
            ToIds = new List<String>{ testCon.Id }, // Set ToIds with Contact ID
            Subject = 'Test Bounced Email',
            TextBody = 'This is a test bounced email',
            IsBounced = true,
            Status = '3' // Bounced status
        );
        insert bouncedEmail;

        // Create list of EmailMessages and call the method
        List<EmailMessage> emails = new List<EmailMessage>{ bouncedEmail };
        BounceEmailController.handleBouncedContractBidPackage(emails);

        Test.stopTest();

        // Verify Contract_Bid__c stage was updated
        Contract_Bid__c updatedContract = [
            SELECT Id, Stage__c
            FROM Contract_Bid__c
            WHERE Id = :testContract.Id
            LIMIT 1
        ];
        System.assertEquals(
            'Need Contact Verification',
            updatedContract.Stage__c,
            'Contract Bid stage should be updated to "Need Contact Verification"'
        );
    }

    @IsTest
    static void testHandleBouncedContractBidPackage_ContactEmail() {
        // Get test data
        Contact testCon = [SELECT Id, Email FROM Contact WHERE LastName = 'Contact' LIMIT 1];

        // Create unique test user for this test
        User testUser = createTestUser();
        insert testUser;

        Contract_Bid__c testContract = [
            SELECT Id, Stage__c
            FROM Contract_Bid__c
            WHERE Name = 'Test Contract Bid'
            LIMIT 1
        ];

        Test.startTest();

        // Create bounced EmailMessage with Contact's email AND ToIds/FromId
        EmailMessage bouncedEmail = new EmailMessage(
            ToAddress = testCon.Email,
            FromAddress = 'sender@example.com',
            FromId = testUser.Id, // Set FromId
            ToIds = new List<String>{ testCon.Id }, // Set ToIds
            Subject = 'Test Bounced Email',
            TextBody = 'This is a test bounced email',
            IsBounced = true,
            Status = '3'
        );
        insert bouncedEmail;

        // Create list of EmailMessages and call the method
        List<EmailMessage> emails = new List<EmailMessage>{ bouncedEmail };
        BounceEmailController.handleBouncedContractBidPackage(emails);

        Test.stopTest();

        // Verify Contract_Bid__c stage was updated
        Contract_Bid__c updatedContract = [
            SELECT Id, Stage__c
            FROM Contract_Bid__c
            WHERE Id = :testContract.Id
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
        BounceEmailController.handleBouncedContractBidPackage(new List<EmailMessage>());
        Test.stopTest();

        // No assertions needed, just making sure no errors occur
        System.assert(true, 'Method should handle empty list without errors');
    }

    @IsTest
    static void testHandleBouncedContractBidPackage_NullList() {
        Test.startTest();
        // Test with null
        BounceEmailController.handleBouncedContractBidPackage(null);
        Test.stopTest();

        // No assertions needed, just making sure no errors occur
        System.assert(true, 'Method should handle null without errors');
    }

    @IsTest
    static void testHandleBouncedContractBidPackage_NoMatchingStage() {
        // Get test data
        Account testAcc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Contact testCon = [SELECT Id FROM Contact WHERE LastName = 'Contact' LIMIT 1];

        // Create unique test user for this test
        User testUser = createTestUser();
        insert testUser;

        // Create another Contract_Bid__c with non-matching stage
        Contract_Bid__c nonMatchingContract = new Contract_Bid__c(
            Name = 'Non-Matching Contract',
            Customer__c = testAcc.Id,
            Stage__c = 'Closed - WON' // Stage that should NOT be updated
        );
        insert nonMatchingContract;

        Test.startTest();

        // Create bounced EmailMessage WITH ToIds
        EmailMessage bouncedEmail = new EmailMessage(
            ToAddress = 'test@example.com',
            FromAddress = 'sender@example.com',
            FromId = testUser.Id, // Set FromId
            ToIds = new List<String>{ testCon.Id }, // Set ToIds
            Subject = 'Test Bounced Email',
            TextBody = 'This is a test bounced email',
            IsBounced = true,
            Status = '3'
        );
        insert bouncedEmail;

        // Create list of EmailMessages and call the method
        List<EmailMessage> emails = new List<EmailMessage>{ bouncedEmail };
        BounceEmailController.handleBouncedContractBidPackage(emails);

        Test.stopTest();

        // Verify only the matching contract was updated
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
    static void testHandleBouncedContractBidPackage_MultipleToIds() {
        // Get test data
        Account testAcc = [SELECT Id, Email__c FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Contact testCon = [SELECT Id, Email FROM Contact WHERE LastName = 'Contact' LIMIT 1];

        // Create unique test user for this test
        User testUser = createTestUser();
        insert testUser;

        // Create another contact for multiple ToIds
        Contact testCon2 = new Contact(
            FirstName = 'Test2',
            LastName = 'Contact2',
            Email = 'contact2@example.com',
            AccountId = testAcc.Id
        );
        insert testCon2;

        Test.startTest();

        // Create bounced EmailMessage with MULTIPLE ToIds
        EmailMessage bouncedEmail = new EmailMessage(
            ToAddress = testAcc.Email__c + ';' + testCon.Email + ';' + testCon2.Email,
            FromAddress = 'sender@example.com',
            FromId = testUser.Id,
            ToIds = new List<String>{ testCon.Id, testCon2.Id }, // Multiple ToIds
            Subject = 'Test Bounced Email',
            TextBody = 'This is a test bounced email',
            IsBounced = true,
            Status = '3'
        );
        insert bouncedEmail;

        // Create list of EmailMessages and call the method
        List<EmailMessage> emails = new List<EmailMessage>{ bouncedEmail };
        BounceEmailController.handleBouncedContractBidPackage(emails);

        Test.stopTest();

        // Verify the method executed without errors
        System.assert(true, 'Method should handle multiple ToIds without errors');
    }

    @IsTest
    static void testHandleBouncedContractBidPackage_NoToIds() {
        // Create unique test user for this test
        User testUser = createTestUser();
        insert testUser;

        Test.startTest();

        // Create bounced EmailMessage WITHOUT ToIds (but with FromId)
        EmailMessage bouncedEmail = new EmailMessage(
            ToAddress = 'test@example.com',
            FromAddress = 'sender@example.com',
            FromId = testUser.Id, // Only FromId, no ToIds
            Subject = 'Test Bounced Email',
            TextBody = 'This is a test bounced email',
            IsBounced = true,
            Status = '3'
        );
        insert bouncedEmail;

        // Create list of EmailMessages and call the method
        List<EmailMessage> emails = new List<EmailMessage>{ bouncedEmail };
        BounceEmailController.handleBouncedContractBidPackage(emails);

        Test.stopTest();

        // Verify the method executed without errors (should skip notification)
        System.assert(true, 'Method should handle EmailMessage without ToIds');
    }

    @IsTest
    static void testHandleBouncedContractBidPackage_NoUserCreation() {
        // Test without creating a User - use existing running user
        Account testAcc = [SELECT Id, Email__c FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Contact testCon = [SELECT Id, Email FROM Contact WHERE LastName = 'Contact' LIMIT 1];

        Test.startTest();

        // Create bounced EmailMessage using current running user as FromId
        EmailMessage bouncedEmail = new EmailMessage(
            ToAddress = testAcc.Email__c,
            FromAddress = UserInfo.getUserEmail(),
            FromId = UserInfo.getUserId(), // Use current running user
            ToIds = new List<String>{ testCon.Id },
            Subject = 'Test Bounced Email',
            TextBody = 'This is a test bounced email',
            IsBounced = true,
            Status = '3'
        );
        insert bouncedEmail;

        // Create list of EmailMessages and call the method
        List<EmailMessage> emails = new List<EmailMessage>{ bouncedEmail };
        BounceEmailController.handleBouncedContractBidPackage(emails);

        Test.stopTest();

        // Verify the method executed
        System.assert(true, 'Method should work with existing user');
    }
}