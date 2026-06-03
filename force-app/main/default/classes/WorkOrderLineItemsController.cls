public with sharing class WorkOrderLineItemsController {
  @AuraEnabled(cacheable=true)
  public static List<Quick_Book_Work_Order_Line_Item__c> getWorkOrderLineItems(Id workOrderId) {
    return [
      SELECT
        Id,
        Name,
        Amount__c,
        Description__c,
        Quantity__c,
        Rate__c,
        Service_Team_Member__c,
        Service_Team_Member__r.Name
      FROM Quick_Book_Work_Order_Line_Item__c
      WHERE Work_Order__c = :workOrderId
      ORDER BY Name
    ];
  }

  @AuraEnabled(cacheable=true)
  public static List<Service_Team_Member__c> getServiceTeamMembers() {
    return [
      SELECT Id, Name
      FROM Service_Team_Member__c
      ORDER BY Name
      LIMIT 5000
    ];
  }

  @AuraEnabled
  public static SaveAssignmentsResult saveServiceTeamMemberAssignments(
    Id workOrderId,
    List<Id> lineItemIds,
    List<Id> serviceTeamMemberIds
  ) {
    SaveAssignmentsResult result = new SaveAssignmentsResult();
    result.errors = new List<String>();
    result.successCount = 0;
    result.failureCount = 0;

    if (workOrderId == null) {
      result.allSucceeded = false;
      result.errors.add('Work Order Id is missing.');
      result.failureCount = 1;
      return result;
    }

    if (lineItemIds == null || lineItemIds.isEmpty()) {
      result.allSucceeded = false;
      result.errors.add('No line items were sent to save.');
      result.failureCount = 1;
      return result;
    }

    if (
      serviceTeamMemberIds == null ||
      lineItemIds.size() != serviceTeamMemberIds.size()
    ) {
      result.allSucceeded = false;
      result.errors.add(
        'Assignment payload is invalid. Expected one Service Team Member value per line item.'
      );
      result.failureCount = lineItemIds.size();
      return result;
    }

    Set<Id> uniqueLineItemIds = new Set<Id>(lineItemIds);
    Map<Id, Quick_Book_Work_Order_Line_Item__c> lineItemsById = new Map<Id, Quick_Book_Work_Order_Line_Item__c>(
      [
        SELECT Id, Service_Team_Member__c, Name
        FROM Quick_Book_Work_Order_Line_Item__c
        WHERE Work_Order__c = :workOrderId AND Id IN :uniqueLineItemIds
      ]
    );

    List<Quick_Book_Work_Order_Line_Item__c> toUpdate = new List<Quick_Book_Work_Order_Line_Item__c>();
    for (Integer i = 0; i < lineItemIds.size(); i++) {
      Id lineItemId = lineItemIds[i];
      Id newMemberId = serviceTeamMemberIds[i];

      if (lineItemId == null) {
        result.failureCount++;
        result.errors.add('Row ' + (i + 1) + ': line item Id is missing.');
        continue;
      }

      Quick_Book_Work_Order_Line_Item__c existing = lineItemsById.get(lineItemId);
      if (existing == null) {
        result.failureCount++;
        result.errors.add(
          String.valueOf(lineItemId) +
            ' is not on this Work Order or is not accessible.'
        );
        continue;
      }

      if (existing.Service_Team_Member__c == newMemberId) {
        continue;
      }

      toUpdate.add(
        new Quick_Book_Work_Order_Line_Item__c(
          Id = existing.Id,
          Service_Team_Member__c = newMemberId
        )
      );
    }

    if (toUpdate.isEmpty()) {
      result.allSucceeded = result.failureCount == 0;
      if (result.allSucceeded) {
        result.errors.add(
          'No changes were detected. The selected values may already match what is saved.'
        );
        result.allSucceeded = false;
        result.failureCount = lineItemIds.size();
      }
      return result;
    }

    Database.SaveResult[] saveResults = Database.update(toUpdate, false);
    for (Integer i = 0; i < saveResults.size(); i++) {
      Quick_Book_Work_Order_Line_Item__c row = toUpdate[i];
      if (saveResults[i].isSuccess()) {
        result.successCount++;
      } else {
        result.failureCount++;
        String rowLabel = lineItemsById.get(row.Id)?.Name ?? String.valueOf(row.Id);
        for (Database.Error err : saveResults[i].getErrors()) {
          result.errors.add(rowLabel + ': ' + err.getMessage());
        }
      }
    }

    result.allSucceeded = result.failureCount == 0 && result.successCount > 0;
    return result;
  }

  public class SaveAssignmentsResult {
    @AuraEnabled
    public Integer successCount;
    @AuraEnabled
    public Integer failureCount;
    @AuraEnabled
    public List<String> errors;
    @AuraEnabled
    public Boolean allSucceeded;
  }
}
