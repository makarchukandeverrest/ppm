public with sharing class ProposalLineItemController {
  @AuraEnabled(cacheable=true)
  public static List<Deal_Line_Item__c> getProposalLineItems(Id proposalId) {
    return [
      SELECT
        Id,
        Name,
        Description__c,
        Quantity__c,
        Unit_Cost__c,
        Total__c,
        Tax__c,
        Deal__r.Sales_Tax__c,
        Not_Id_Name__c
      FROM Deal_Line_Item__c
      WHERE Deal__c = :proposalId
    ];
  }

  @AuraEnabled
  public static void updateProposalLineItems(List<Deal_Line_Item__c> items) {
    try {
      if (items != null && !items.isEmpty()) {
        Database.update(items);
      }
    } catch (Exception e) {
      throw new AuraHandledException(
        'Failed to update proposal line items: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled
  public static List<Id> createProposalLineItems(
    List<Deal_Line_Item__c> items
  ) {
    try {
      if (items != null && !items.isEmpty()) {
        Database.insert(items);
        return new List<Id>(new Map<Id, Deal_Line_Item__c>(items).keySet());
      }
      return new List<Id>();
    } catch (Exception e) {
      throw new AuraHandledException(
        'Failed to create proposal line items: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled
  public static void deleteProposalLineItems(List<Id> ids) {
    try {
      if (ids != null && !ids.isEmpty()) {
        List<Deal_Line_Item__c> itemsToDelete = [
          SELECT Id
          FROM Deal_Line_Item__c
          WHERE Id IN :ids
        ];
        if (!itemsToDelete.isEmpty()) {
          Database.delete(itemsToDelete);
        }
      }
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error deleting proposal line items: ' + e.getMessage()
      );
    }
  }
}