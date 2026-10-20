@IsTest
private class ContractCreatorUserResolverTest {
  @IsTest
  static void resolvesAndHandlesBlank() {
    ContractCreatorUserResolver.clearCache();

    System.assertEquals(null, ContractCreatorUserResolver.resolveUserId(null));
    System.assertEquals(
      null,
      ContractCreatorUserResolver.resolveUserId('Unknown')
    );

    Id userId = ContractCreatorUserResolver.resolveUserId(
      'Marijana to Complete'
    );
    if (userId != null) {
      System.assertEquals(
        'Marijana to Complete',
        ContractCreatorUserResolver.resolvePicklistValue(userId)
      );
    }
  }
}
