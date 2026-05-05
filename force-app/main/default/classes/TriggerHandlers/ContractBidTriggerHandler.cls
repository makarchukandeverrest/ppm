public with sharing class ContractBidTriggerHandler extends TriggerHandler {
  List<Contract_Bid__c> newList;
  Map<Id, Contract_Bid__c> oldMap;

  public ContractBidTriggerHandler() {
    this.newList = (List<Contract_Bid__c>) Trigger.new;
    this.oldMap = (Map<Id, Contract_Bid__c>) Trigger.oldMap;
  }

  protected override void afterInsert() {
    List<Contract_Bid__c> wonBids = new List<Contract_Bid__c>();
    List<Contract_Bid__c> lostBids = new List<Contract_Bid__c>();
    for (Contract_Bid__c bid : this.newList) {
      if (bid.Stage__c == 'Closed - WON') {
        wonBids.add(bid);
      } else if (bid.Stage__c == 'Closed - LOST') {
        lostBids.add(bid);
      }
    }
    if (!wonBids.isEmpty()) {
      AccountCurrentCustomerUpdater.updateCustomers(wonBids, true);
    }
    if (!lostBids.isEmpty()) {
      AccountCurrentCustomerUpdater.updateCustomers(lostBids, false);
    }
  }

  protected override void afterUpdate() {
    List<Contract_Bid__c> wonBids = new List<Contract_Bid__c>();
    List<Contract_Bid__c> lostBids = new List<Contract_Bid__c>();
    for (Contract_Bid__c bid : this.newList) {
      if (
        bid.Stage__c == 'Closed - WON' &&
        oldMap.get(bid.Id).Stage__c != 'Closed - WON'
      ) {
        wonBids.add(bid);
      }else if (
        bid.Stage__c == 'Closed - LOST' &&
        oldMap.get(bid.Id).Stage__c != 'Closed - LOST'
      ) {
        lostBids.add(bid);
      }
    }
    if (!wonBids.isEmpty()) {
      AccountCurrentCustomerUpdater.updateCustomers(wonBids, true);
    }
    if (!lostBids.isEmpty()) {
      AccountCurrentCustomerUpdater.updateCustomers(lostBids, false);
    }
  }
}