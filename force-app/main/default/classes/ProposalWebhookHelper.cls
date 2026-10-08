public without sharing class ProposalWebhookHelper {
  private static final List<SObjectField> PROPOSAL_WATCHED_FIELDS = new List<SObjectField>{
    Opportunity.Account_QuickBooks_Id__c,
    Opportunity.Date_Ordered__c,
    Opportunity.Reference_Number__c,
    Opportunity.Is_Active__c,
    Opportunity.Project_Order_No__c,
    Opportunity.Terms__c,
    Opportunity.CloseDate,
    Opportunity.Order_Taken_By__c,
    Opportunity.FOB__c,
    Opportunity.Description,
    Opportunity.Contact__c
  };

  private static final List<SObjectField> LINE_ITEM_WATCHED_FIELDS = new List<SObjectField>{
    Deal_Line_Item__c.Name,
    Deal_Line_Item__c.Description__c,
    Deal_Line_Item__c.Quantity__c,
    Deal_Line_Item__c.Unit_Cost__c,
    Deal_Line_Item__c.Total__c,
    Deal_Line_Item__c.Credit_Card_Fee__c,
    Deal_Line_Item__c.Deal__c
  };

  public static Set<Id> collectProposalIdsFromProposals(
    List<Opportunity> newList,
    Map<Id, Opportunity> oldMap
  ) {
    Set<Id> proposalIds = new Set<Id>();
    if (newList == null || newList.isEmpty()) {
      return proposalIds;
    }

    for (Opportunity proposal : newList) {
      Opportunity oldProposal = oldMap == null ? null : oldMap.get(proposal.Id);
      if (
        oldProposal == null ||
        hasChanged(proposal, oldProposal, PROPOSAL_WATCHED_FIELDS)
      ) {
        proposalIds.add(proposal.Id);
      }
    }
    return proposalIds;
  }

  public static Set<Id> collectProposalIdsFromLineItems(
    List<Deal_Line_Item__c> records,
    Map<Id, Deal_Line_Item__c> oldMap
  ) {
    Set<Id> proposalIds = new Set<Id>();
    if (records == null || records.isEmpty()) {
      return proposalIds;
    }

    for (Deal_Line_Item__c lineItem : records) {
      Deal_Line_Item__c oldLineItem = oldMap == null
        ? null
        : oldMap.get(lineItem.Id);
      if (
        oldLineItem == null ||
        hasChanged(lineItem, oldLineItem, LINE_ITEM_WATCHED_FIELDS)
      ) {
        if (lineItem.Deal__c != null) {
          proposalIds.add(lineItem.Deal__c);
        }
        if (oldLineItem != null && oldLineItem.Deal__c != null) {
          proposalIds.add(oldLineItem.Deal__c);
        }
      }
    }
    return proposalIds;
  }

  @TestVisible
  private static Boolean hasChanged(
    SObject currentRecord,
    SObject previousRecord,
    List<SObjectField> fields
  ) {
    for (SObjectField field : fields) {
      if (currentRecord.get(field) != previousRecord.get(field)) {
        return true;
      }
    }
    return false;
  }
}
