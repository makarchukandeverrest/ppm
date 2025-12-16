@IsTest
public class AccountFilesControllerTest {
  // ---------- Helpers ----------
  private static Account createTestAccount(String name, String email) {
    Account acc = new Account(Name = name);

    Contact con = new Contact(FirstName = 'Test Contact', Email = email);
    insert con;
    acc.Primary_Contact__c = con.Id;
    insert acc;
    return acc;
  }

  private static Contract_Bid__c createTestContract(
    Account acc,
    String stage,
    Boolean renewalClient
  ) {
    Contract_Bid__c contract = new Contract_Bid__c(
      Name = 'Test Contract',
      Customer__c = acc.Id,
      Stage__c = stage,
      Renewal_Client__c = renewalClient
    );
    insert contract;
    return contract;
  }

  private static ContentDocument createTestFile(
    Account acc,
    String title,
    String extension
  ) {
    ContentVersion cv = new ContentVersion(
      Title = title,
      PathOnClient = title + '.' + extension,
      VersionData = Blob.valueOf('Test file data'),
      To_Sent__c = false
    );
    insert cv;

    // Re-query ContentVersion to ensure ContentDocumentId is populated
    cv = [
      SELECT Id, ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cv.Id
      LIMIT 1
    ];

    // Now ContentDocumentId is guaranteed
    insert new ContentDocumentLink(
      ContentDocumentId = cv.ContentDocumentId,
      LinkedEntityId = acc.Id,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );

    return [
      SELECT Id, LatestPublishedVersionId
      FROM ContentDocument
      WHERE Id = :cv.ContentDocumentId
      LIMIT 1
    ];
  }

  // ---------- Tests ----------
  @IsTest(SeeAllData=true)
  static void testGetAccountsWithFiles_basic() {
    Account acc = createTestAccount('Acme Corp', 'acme@test.com');
    Contract_Bid__c contract = createTestContract(
      acc,
      'Contact Verified and Updated',
      false
    );
    ContentDocument doc = createTestFile(acc, 'Proposal', 'pdf');

    Test.startTest();
    List<AccountWithFiles> results = AccountFilesController.getAccountsWithFiles(
      null
    );
    Test.stopTest();
    for (AccountWithFiles a : results) {
      if (a.accountName == 'Acme Corp') {
        System.assertEquals(acc.Id, a.accountId, 'Account Id should match');
        System.assertEquals(
          acc.Name,
          a.accountName,
          'Account Name should match'
        );
        System.assertEquals(
          acc.Email__c,
          a.email,
          'Account Email should match'
        );
        System.assertEquals(
          contract.Id,
          a.contract.Id,
          'Contract should match'
        );
        System.assertEquals(
          false,
          a.newClient,
          'newClient should be true since Renewal_Client__c=false'
        );
        System.assert(!a.files.isEmpty(), 'Files list should not be empty');
        System.assertNotEquals(
          null,
          a.files[0].fileExtension,
          'File should have an extension set'
        );
      }
      System.debug(a);
    }

    System.assertNotEquals(
      0,
      results.size(),
      'Expected at least one account with files'
    );
  }

  @IsTest(SeeAllData=true)
  static void testGetAccountsWithFiles_excludedStage() {
    Account acc = createTestAccount('Test Filter', 'filter@test.com');
    createTestContract(acc, 'Closed - WON', false);

    Test.startTest();
    List<AccountWithFiles> results = AccountFilesController.getAccountsWithFiles(
      acc.Id
    );
    Test.stopTest();

    System.assertEquals(
      0,
      results.size(),
      'No results expected for excluded stages'
    );
  }

  @IsTest(SeeAllData=true)
  static void testGetAccountsWithFiles_contractWithoutFiles() {
    Account acc = createTestAccount('No File Acc', 'nofile@test.com');
    createTestContract(acc, 'Contract Sent via DocuSign', true); // Renewal_Client__c = true

    Test.startTest();
    List<AccountWithFiles> results = AccountFilesController.getAccountsWithFiles(
      acc.Id
    );
    Test.stopTest();

    // Contract exists but no file -> should not return anything
    System.assertEquals(
      0,
      results.size(),
      'No files means account should not be included'
    );
  }
}
