public with sharing class ContractCreatorUserResolver {
  private static Map<String, Id> cache;

  @AuraEnabled(cacheable=true)
  public static Id resolveUserId(String picklistValue) {
    return String.isBlank(picklistValue)
      ? null
      : getMap().get(picklistValue.trim());
  }

  public static String resolvePicklistValue(Id userId) {
    if (userId == null) {
      return null;
    }
    for (String value : getMap().keySet()) {
      if (getMap().get(value) == userId) {
        return value;
      }
    }
    return null;
  }

  private static Map<String, Id> getMap() {
    if (cache != null) {
      return cache;
    }
    cache = new Map<String, Id>();
    for (
      Contract_Creator_User_Map__mdt row : Contract_Creator_User_Map__mdt.getAll()
        .values()
    ) {
      if (
        String.isBlank(row.Picklist_Value__c) || String.isBlank(row.Username__c)
      ) {
        continue;
      }
      String username = row.Username__c.trim();
      String likePattern = username + '.%';
      List<User> users = [
        SELECT Id
        FROM User
        WHERE
          IsActive = TRUE
          AND (Username = :username
          OR Username LIKE :likePattern
          OR Email = :username)
        LIMIT 1
      ];
      if (!users.isEmpty()) {
        cache.put(row.Picklist_Value__c.trim(), users[0].Id);
      }
    }
    return cache;
  }

  @TestVisible
  private static void clearCache() {
    cache = null;
  }
}
