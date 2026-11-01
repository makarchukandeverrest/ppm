public with sharing class UnifiedActivityPinService {
  public Map<Id, UnifiedActivityModels.PinnedActivityInfo> getPinnedActivities(
    Set<Id> recordIds
  ) {
    Map<Id, UnifiedActivityModels.PinnedActivityInfo> pinnedByActivityId = new Map<Id, UnifiedActivityModels.PinnedActivityInfo>();
    if (recordIds == null || recordIds.isEmpty()) {
      return pinnedByActivityId;
    }
    if (!Schema.sObjectType.Pinned_Feed_Item__c.isAccessible()) {
      return pinnedByActivityId;
    }

    Set<String> parentKeys = new Set<String>();
    for (Id recordId : recordIds) {
      if (recordId != null) {
        parentKeys.add(String.valueOf(recordId));
      }
    }
    if (parentKeys.isEmpty()) {
      return pinnedByActivityId;
    }

    for (Pinned_Feed_Item__c row : [
      SELECT Activity_Id__c, CreatedDate, CreatedBy.Name
      FROM Pinned_Feed_Item__c
      WHERE Parent_Id__c IN :parentKeys
      WITH USER_MODE
    ]) {
      if (String.isBlank(row.Activity_Id__c)) {
        continue;
      }
      try {
        Id activityId = (Id) row.Activity_Id__c;
        UnifiedActivityModels.PinnedActivityInfo info = new UnifiedActivityModels.PinnedActivityInfo();
        info.activityId = activityId;
        info.pinnedAt = row.CreatedDate;
        info.pinnedByName = row.CreatedBy != null ? row.CreatedBy.Name : null;
        pinnedByActivityId.put(activityId, info);
      } catch (Exception e) {
        System.debug(
          LoggingLevel.WARN,
          'Skipping invalid pinned Activity Id: ' + row.Activity_Id__c
        );
      }
    }
    return pinnedByActivityId;
  }

  public void setActivityPinned(
    Id activityId,
    Id contextRecordId,
    Boolean isPinned
  ) {
    if (activityId == null) {
      throw new UnifiedActivityException('activityId is required');
    }
    if (contextRecordId == null) {
      throw new UnifiedActivityException('contextRecordId is required');
    }
    if (isPinned == null) {
      throw new UnifiedActivityException('isPinned is required');
    }

    String activityKey = String.valueOf(activityId);
    String parentKey = String.valueOf(contextRecordId);

    if (isPinned == true) {
      pinActivity(activityKey, parentKey);
    } else {
      unpinActivity(activityKey);
    }
  }

  private void pinActivity(String activityKey, String parentKey) {
    if (!Schema.sObjectType.Pinned_Feed_Item__c.isCreateable()) {
      throw new AuraHandledException(
        'Insufficient permissions to pin activities'
      );
    }

    List<Pinned_Feed_Item__c> existing = [
      SELECT Id
      FROM Pinned_Feed_Item__c
      WHERE Activity_Id__c = :activityKey
      WITH USER_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return;
    }

    try {
      insert as user new Pinned_Feed_Item__c(
        Activity_Id__c = activityKey,
        Parent_Id__c = parentKey
      );
    } catch (DmlException e) {
      throw new AuraHandledException(
        String.isBlank(e.getDmlMessage(0))
          ? 'Unable to pin this activity.'
          : e.getDmlMessage(0)
      );
    }
  }

  private void unpinActivity(String activityKey) {
    if (!Schema.sObjectType.Pinned_Feed_Item__c.isDeletable()) {
      throw new AuraHandledException(
        'Insufficient permissions to unpin activities'
      );
    }

    List<Pinned_Feed_Item__c> existing = [
      SELECT Id
      FROM Pinned_Feed_Item__c
      WHERE Activity_Id__c = :activityKey
      WITH USER_MODE
      LIMIT 1
    ];
    if (existing.isEmpty()) {
      return;
    }

    try {
      delete as user existing;
    } catch (DmlException e) {
      throw new AuraHandledException(
        String.isBlank(e.getDmlMessage(0))
          ? 'Unable to unpin this activity.'
          : e.getDmlMessage(0)
      );
    }
  }
}
