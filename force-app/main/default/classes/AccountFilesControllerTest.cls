@IsTest
public class AccountFilesControllerTest {

    // ---------- Helpers ----------

    /**
     * Creates a test user with a unique alias suffix
     */
    private static User createUser(String aliasSuffix) {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE UserType = 'Standard'
            LIMIT 1
        ];

        String uniqueId = String.valueOf(Datetime.now().getTime()) + Crypto.getRandomInteger();
        String trimmedAlias = (aliasSuffix + uniqueId).left(8);

        User u = new User(
            FirstName         = 'Test',
            LastName          = 'User' + uniqueId.left(6),
            Alias             = trimmedAlias,
            Email             = trimmedAlias + '@test.com',
            Username          = trimmedAlias + uniqueId + '@test.com',
            CommunityNickname = trimmedAlias + uniqueId,
            TimeZoneSidKey    = 'America/New_York',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = p.Id
        );
        insert u;
        return u;
    }

    private static Supervisor__c createSupervisor(String nameSuffix) {
        String uniqueId = String.valueOf(Datetime.now().getTime()) + Crypto.getRandomInteger();
        Supervisor__c sup = new Supervisor__c(
            Name = 'Sup ' + nameSuffix + ' ' + uniqueId.left(6),
            Last_Name__c = 'Ln' + uniqueId.left(6)
        );
        insert sup;
        return sup;
    }

    /**
     * Gets a valid county picklist value dynamically
     */
    private static String getValidCountyValue() {
        Schema.DescribeFieldResult fieldResult = Account.County__c.getDescribe();
        List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
        
        if (picklistValues != null && !picklistValues.isEmpty()) {
            // Return the first active picklist value
            for (Schema.PicklistEntry entry : picklistValues) {
                if (entry.isActive()) {
                    return entry.getValue();
                }
            }
        }
        
        // Fallback if no picklist values found (shouldn't happen in real org)
        return null;
    }

    /**
     * Gets multiple valid county picklist values
     */
    private static List<String> getValidCountyValues(Integer count) {
        Schema.DescribeFieldResult fieldResult = Account.County__c.getDescribe();
        List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
        List<String> validCounties = new List<String>();
        
        if (picklistValues != null && !picklistValues.isEmpty()) {
            for (Schema.PicklistEntry entry : picklistValues) {
                if (entry.isActive() && validCounties.size() < count) {
                    validCounties.add(entry.getValue());
                }
            }
        }
        
        return validCounties;
    }

    private static Account createTestAccount(
        String name,
        Id regionalManagerId,
        Id supervisorId,
        String county
    ) {
        Account acc = new Account(
            Name                = name,
            Regional_Manager__c = regionalManagerId,
            Supervisor_Lookup__c = supervisorId,
            County__c           = county
        );
        insert acc;
        return acc;
    }

    /**
     * Creates a test Contract_Bid__c record
     */
    private static Contract_Bid__c createTestContract(
        Account acc,
        String stage,
        Boolean renewalClient
    ) {
        Contract_Bid__c contract = new Contract_Bid__c(
            Customer__c      = acc.Id,
            Stage__c         = stage,
            Renewal_Client__c = renewalClient
        );
        insert contract;
        return contract;
    }

    /**
     * Builds a file title that passes getAccountsWithFiles ContentVersion filters.
     */
    private static String buildContractFileTitle(String suffix) {
        return 'Contract ' + Date.today().year() + ' ' + suffix;
    }

    /**
     * Creates a test file (ContentVersion) linked to an Account
     */
    private static ContentDocument createTestFile(
        Account acc,
        String title,
        String fileExtension
    ) {
        return createTestFile(acc.Id, title, fileExtension);
    }

    /**
     * Creates a test file (ContentVersion) linked to a Contract Bid
     */
    private static ContentDocument createTestFile(
        Contract_Bid__c contract,
        String title,
        String fileExtension
    ) {
        return createTestFile(contract.Id, title, fileExtension);
    }

    private static ContentDocument createTestFile(
        Id linkedEntityId,
        String title,
        String fileExtension
    ) {
        return createTestFile(linkedEntityId, title, fileExtension, true);
    }

    private static ContentDocument createTestFile(
        Id linkedEntityId,
        String title,
        String fileExtension,
        Boolean includeYearInTitle
    ) {
        String fileTitle = includeYearInTitle ? buildContractFileTitle(title) : title;
        ContentVersion cv = new ContentVersion(
            Title           = fileTitle,
            PathOnClient    = fileTitle + '.' + fileExtension,
            VersionData     = Blob.valueOf('Test PDF Content'),
            IsMajorVersion  = true
        );
        insert cv;

        // Query back to get ContentDocumentId
        ContentVersion insertedCV = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = insertedCV.ContentDocumentId,
            LinkedEntityId    = linkedEntityId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert cdl;

        // Return ContentDocument
        return [
            SELECT Id, Title
            FROM ContentDocument
            WHERE Id = :insertedCV.ContentDocumentId
            LIMIT 1
        ];
    }

    // ---------- Tests for getFilterOptions ----------

    @IsTest
    static void testGetFilterOptions_basic() {
        // Setup
        User rm = createUser('RM');
        Supervisor__c sup = createSupervisor('SUP');

        // Get active stages from metadata
        StageReferenceSettings__mdt stageRef = StageReferenceSettings__mdt.getInstance('Active_Stages');
        System.assertNotEquals(null, stageRef, 'Active_Stages metadata should exist');
        System.assertNotEquals(null, stageRef.Stage_Names__c, 'Stage_Names__c should not be null');
        
        String firstActiveStage = stageRef.Stage_Names__c.split(',')[0].trim();

        // Get a valid county value from picklist
        String testCounty = getValidCountyValue();
        System.assertNotEquals(null, testCounty, 'At least one valid county picklist value should exist');

        Account acc = createTestAccount('Filter Acc', rm.Id, sup.Id, testCounty);
        createTestContract(acc, firstActiveStage, false);

        Test.startTest();
        AccountFilesController.FilterOptions options = AccountFilesController.getFilterOptions();
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, options, 'FilterOptions should not be null');
        System.assertNotEquals(null, options.regionalManagers, 'Regional managers list should not be null');
        System.assertNotEquals(null, options.counties, 'Counties list should not be null');
        System.assertNotEquals(null, options.supervisors, 'Supervisors list should not be null');

        // Verify county is present
        Boolean foundCounty = false;
        for (AccountFilesController.PicklistOption opt : options.counties) {
            if (opt.value == testCounty) {
                foundCounty = true;
                break;
            }
        }
        System.assert(foundCounty, 'County from account should be present in filter options');
    }

    @IsTest
    static void testGetAccountsWithFiles_filtersByRegionalManagerCountySupervisor() {
        // Setup
        User rm1 = createUser('RM1');
        User rm2 = createUser('RM2');
        Supervisor__c sup1 = createSupervisor('SUP1');

        // Get active stages
        StageReferenceSettings__mdt stageRef = StageReferenceSettings__mdt.getInstance('Active_Stages');
        String firstActiveStage = stageRef.Stage_Names__c.split(',')[0].trim();

        // Get valid counties
        List<String> validCounties = getValidCountyValues(2);
        System.assert(validCounties.size() >= 2, 'At least two valid county picklist values should exist');
        String county1 = validCounties[0];
        String county2 = validCounties.size() > 1 ? validCounties[1] : validCounties[0];

        Account acc1 = createTestAccount('Acc 1', rm1.Id, sup1.Id, county1);
        Account acc2 = createTestAccount('Acc 2', rm2.Id, sup1.Id, county2);

        Contract_Bid__c c1 = createTestContract(acc1, firstActiveStage, false);
        Contract_Bid__c c2 = createTestContract(acc2, firstActiveStage, false);

        createTestFile(acc1, 'Proposal1', 'pdf');
        createTestFile(acc2, 'Proposal2', 'pdf');

        Test.startTest();
        List<AccountWithFiles> results = AccountFilesController.getAccountsWithFiles(
            null,          // recordId
            rm1.Id,        // regionalManagerId
            county1,       // county
            null,          // customerName
            sup1.Id,       // supervisorId
            null           // contractYear
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Only one account should match all filters');
        System.assertEquals(acc1.Id, results[0].accountId, 'Filtered account should be acc1');
    }

    @IsTest
    static void testGetAccountsWithFiles_excludedStage() {
        // Setup - Get active and excluded stages
        StageReferenceSettings__mdt stageRef = StageReferenceSettings__mdt.getInstance('Active_Stages');
        List<String> activeStages = new List<String>();
        for (String s : stageRef.Stage_Names__c.split(',')) {
            activeStages.add(s.trim());
        }

        // Get all available stages from picklist
        Schema.DescribeFieldResult fieldResult = Contract_Bid__c.Stage__c.getDescribe();
        List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
        
        String excludedStage = null;
        for (Schema.PicklistEntry entry : picklistValues) {
            if (entry.isActive() && !activeStages.contains(entry.getValue())) {
                excludedStage = entry.getValue();
                break;
            }
        }

        // If no excluded stage found, skip this test
        if (excludedStage == null) {
            return;
        }

        String testCounty = getValidCountyValue();
        Account acc = createTestAccount('Test Filter', null, null, testCounty);
        createTestContract(acc, excludedStage, false);

        Test.startTest();
        List<AccountWithFiles> results = AccountFilesController.getAccountsWithFiles(
            null, null, null, null, null, null
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'No results expected for excluded stages');
    }

    @IsTest
    static void testGetAccountsWithFiles_contractWithoutFiles() {
        // Setup
        StageReferenceSettings__mdt stageRef = StageReferenceSettings__mdt.getInstance('Active_Stages');
        String firstActiveStage = stageRef.Stage_Names__c.split(',')[0].trim();

        String testCounty = getValidCountyValue();
        Account acc = createTestAccount('No File Acc', null, null, testCounty);
        createTestContract(acc, firstActiveStage, true); // Renewal_Client__c = true
        // Note: No file created, so account should not appear in results

        Test.startTest();
        List<AccountWithFiles> results = AccountFilesController.getAccountsWithFiles(
            null, null, null, null, null, null
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'No files means account should not be included');
    }

    @IsTest
    static void testGetAccountsWithFiles_customerNameFilter() {
        // Setup
        StageReferenceSettings__mdt stageRef = StageReferenceSettings__mdt.getInstance('Active_Stages');
        String firstActiveStage = stageRef.Stage_Names__c.split(',')[0].trim();

        String county = getValidCountyValue();

        Account acc1 = createTestAccount('Acme Ukraine', null, null, county);
        Account acc2 = createTestAccount('Other Customer', null, null, county);

        createTestContract(acc1, firstActiveStage, false);
        createTestContract(acc2, firstActiveStage, false);

        createTestFile(acc1, 'Proposal1', 'pdf');
        createTestFile(acc2, 'Proposal2', 'pdf');

        Test.startTest();
        List<AccountWithFiles> results = AccountFilesController.getAccountsWithFiles(
            null,
            null,
            null,
            'Acme',  // partial name
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Only accounts matching name filter should be returned');
        System.assertEquals(acc1.Id, results[0].accountId, 'Account name filter should match Acme Ukraine');
    }

    @IsTest
    static void testGetAccountsWithFiles_filesFromContractBid() {
        StageReferenceSettings__mdt stageRef = StageReferenceSettings__mdt.getInstance('Active_Stages');
        String firstActiveStage = stageRef.Stage_Names__c.split(',')[0].trim();
        String testCounty = getValidCountyValue();

        Account acc = createTestAccount('Contract Bid File Acc', null, null, testCounty);
        Contract_Bid__c contract = createTestContract(acc, firstActiveStage, false);
        createTestFile(contract, 'ProposalFromBid', 'pdf');

        Test.startTest();
        List<AccountWithFiles> results = AccountFilesController.getAccountsWithFiles(
            null, null, null, 'Contract Bid File Acc', null, null
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Account should be returned when files are on Contract Bid');
        System.assertEquals(acc.Id, results[0].accountId, 'Files from Contract Bid should map to Customer Account');
        System.assertEquals(1, results[0].files.size(), 'Contract Bid file should be included');
        System.assert(
            results[0].files[0].Title.contains('ProposalFromBid'),
            'Returned file should be the one linked to Contract Bid'
        );
    }

    @IsTest
    static void testGetAccountsWithFiles_combinesAccountAndContractBidFiles() {
        StageReferenceSettings__mdt stageRef = StageReferenceSettings__mdt.getInstance('Active_Stages');
        String firstActiveStage = stageRef.Stage_Names__c.split(',')[0].trim();
        String testCounty = getValidCountyValue();

        Account acc = createTestAccount('Combined Files Acc', null, null, testCounty);
        Contract_Bid__c contract = createTestContract(acc, firstActiveStage, false);
        createTestFile(acc, 'FromAccount', 'pdf');
        createTestFile(contract, 'FromBid', 'pdf');

        Test.startTest();
        List<AccountWithFiles> results = AccountFilesController.getAccountsWithFiles(
            null, null, null, 'Combined Files Acc', null, null
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One account should be returned');
        System.assertEquals(2, results[0].files.size(), 'Files from Account and Contract Bid should be combined');
    }

    @IsTest
    static void testGetAccountsWithFiles_contractBidFileDoesNotRequireYear() {
        StageReferenceSettings__mdt stageRef = StageReferenceSettings__mdt.getInstance('Active_Stages');
        String firstActiveStage = stageRef.Stage_Names__c.split(',')[0].trim();
        String county = getValidCountyValue();

        Account acc = createTestAccount('Bid No Year Acc', null, null, county);
        Contract_Bid__c contract = createTestContract(acc, firstActiveStage, false);
        createTestFile(contract.Id, 'Contract Without Year From Bid', 'pdf', false);

        Test.startTest();
        List<AccountWithFiles> results = AccountFilesController.getAccountsWithFiles(
            null, null, null, 'Bid No Year Acc', null, null
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Contract Bid file without year should still be returned');
        System.assertEquals(1, results[0].files.size(), 'Yearless Contract Bid file should be included');
        System.assertEquals(
            'Contract Without Year From Bid',
            results[0].files[0].Title,
            'Returned file should keep the Contract Bid title without a year'
        );
    }

    @IsTest
    static void testGetAccountsWithFiles_accountFileStillRequiresYear() {
        StageReferenceSettings__mdt stageRef = StageReferenceSettings__mdt.getInstance('Active_Stages');
        String firstActiveStage = stageRef.Stage_Names__c.split(',')[0].trim();
        String county = getValidCountyValue();

        Account acc = createTestAccount('Account No Year Acc', null, null, county);
        createTestContract(acc, firstActiveStage, false);
        createTestFile(acc.Id, 'Contract Without Year From Account', 'pdf', false);

        Test.startTest();
        List<AccountWithFiles> results = AccountFilesController.getAccountsWithFiles(
            null, null, null, 'Account No Year Acc', null, null
        );
        Test.stopTest();

        System.assertEquals(
            0,
            results.size(),
            'Account files without the contract year in the title should still be excluded'
        );
    }

    @IsTest
    static void testGetAccountsWithFiles_filtersBySelectedRecordIds() {
        StageReferenceSettings__mdt stageRef = StageReferenceSettings__mdt.getInstance('Active_Stages');
        String firstActiveStage = stageRef.Stage_Names__c.split(',')[0].trim();
        String county = getValidCountyValue();

        Account acc1 = createTestAccount('Selected Bid Acc 1', null, null, county);
        Account acc2 = createTestAccount('Selected Bid Acc 2', null, null, county);

        Contract_Bid__c selectedBid = createTestContract(acc1, firstActiveStage, false);
        createTestContract(acc2, firstActiveStage, false);

        createTestFile(acc1, 'Proposal1', 'pdf');
        createTestFile(acc2, 'Proposal2', 'pdf');

        Test.startTest();
        List<AccountWithFiles> selectedOnly = AccountFilesController.getAccountsWithFiles(
            new List<Id>{ selectedBid.Id },
            null,
            null,
            null,
            null,
            null
        );
        List<AccountWithFiles> allActive = AccountFilesController.getAccountsWithFiles(
            new List<Id>(),
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(1, selectedOnly.size(), 'Only the selected Contract Bid should be returned');
        System.assertEquals(acc1.Id, selectedOnly[0].accountId, 'Selected bid should map to acc1');

        Set<Id> allAccountIds = new Set<Id>();
        for (AccountWithFiles row : allActive) {
            allAccountIds.add(row.accountId);
        }
        System.assert(allAccountIds.contains(acc1.Id), 'Empty selection should still include acc1');
        System.assert(allAccountIds.contains(acc2.Id), 'Empty selection should still include acc2');
    }
}