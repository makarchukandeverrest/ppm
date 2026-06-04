public with sharing class ContractBidTriggerHandler extends TriggerHandler {
  List<Contract_Bid__c> newList;
  Map<Id, Contract_Bid__c> oldMap;

  public ContractBidTriggerHandler() {
    this.newList = (List<Contract_Bid__c>) Trigger.new;
    this.oldMap = (Map<Id, Contract_Bid__c>) Trigger.oldMap;
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