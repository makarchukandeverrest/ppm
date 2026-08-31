public with sharing class ContractBidTriggerHandler extends TriggerHandler {
  List<Contract_Bid__c> newList;
  Map<Id, Contract_Bid__c> oldMap;

  public ContractBidTriggerHandler() {
    this.newList = (List<Contract_Bid__c>) Trigger.new;
    this.oldMap = (Map<Id, Contract_Bid__c>) Trigger.oldMap;
  }

  protected override void beforeInsert() {
    for (Contract_Bid__c bid : this.newList) {
      clearRestrictedFieldsOnCreate(bid);
    }
    ContractBidLabelsFiller.fillLabels(this.newList);
  }

  private static void clearRestrictedFieldsOnCreate(Contract_Bid__c bid) {
    bid.Bid_Number__c = null;
    bid.Version__c = null;
    bid.Contract_Start_Date__c = null;
    bid.Contract_End_Date__c = null;
    bid.Sent_Contract_Date__c = null;
    bid.Lost_Reason__c = null;
    bid.Additional_Comments__c = null;
    bid.EBD_Due_Date__c = null;
    bid.Due_Date__c = null;
  }
  protected override void afterInsert() {
    List<Contract_Bid__c> wonBids = new List<Contract_Bid__c>();
    for (Contract_Bid__c bid : this.newList) {
      if (bid.Stage__c == 'Closed - WON') {
        wonBids.add(bid);
      }
    }
    if (!wonBids.isEmpty()) {
      AccountCurrentCustomerUpdater.updateCustomers(wonBids);
    }
    ContractBidLabelsFiller.replacePreviousYearLabels(this.newList);
  }

  protected override void afterUpdate() {
    List<Contract_Bid__c> wonBids = new List<Contract_Bid__c>();
    for (Contract_Bid__c bid : this.newList) {
      if (
        bid.Stage__c == 'Closed - WON' &&
        oldMap.get(bid.Id).Stage__c != 'Closed - WON'
      ) {
        wonBids.add(bid);
      }
    }
    if (!wonBids.isEmpty()) {
      AccountCurrentCustomerUpdater.updateCustomers(wonBids);
    }
  }
}