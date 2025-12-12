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
        Rate__c
      FROM Quick_Book_Work_Order_Line_Item__c
      WHERE Work_Order__c = :workOrderId
    ];
  }
}