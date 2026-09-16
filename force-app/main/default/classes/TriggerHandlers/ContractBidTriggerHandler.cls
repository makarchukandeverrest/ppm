public with sharing class ContractBidTriggerHandler extends TriggerHandler {
  private static final String STAGE_CLOSED_WON = 'Closed - WON';
  private static final String STAGE_CLOSED_LOST = 'Closed - LOST';

  List<Contract_Bid__c> newList;
  Map<Id, Contract_Bid__c> oldMap;

  public ContractBidTriggerHandler() {
    this.newList = (List<Contract_Bid__c>) Trigger.new;
    this.oldMap = (Map<Id, Contract_Bid__c>) Trigger.oldMap;
  }

  protected override void beforeInsert() {
    ContractBidLabelsFiller.fillLabels(this.newList);
  }


  protected override void afterInsert() {
    updateCurrentCustomerAccounts();
    ContractBidLabelsFiller.replacePreviousYearLabels(this.newList);
  }

  protected override void afterUpdate() {
    updateCurrentCustomerAccounts();
  }

  private void updateCurrentCustomerAccounts() {
    List<Contract_Bid__c> wonBids = new List<Contract_Bid__c>();
    List<Contract_Bid__c> lostBids = new List<Contract_Bid__c>();

    for (Contract_Bid__c bid : this.newList) {
      if (stageChangedTo(bid, STAGE_CLOSED_WON)) {
        wonBids.add(bid);
      } else if (stageChangedTo(bid, STAGE_CLOSED_LOST)) {
        lostBids.add(bid);
      }
    }

    if (!lostBids.isEmpty()) {
      AccountCurrentCustomerUpdater.clearCurrentCustomer(lostBids);
    }
    if (!wonBids.isEmpty()) {
      AccountCurrentCustomerUpdater.updateCustomers(wonBids);
    }
  }

  private Boolean stageChangedTo(Contract_Bid__c bid, String targetStage) {
    String previousStage = this.oldMap != null
      ? this.oldMap.get(bid.Id)?.Stage__c
      : null;
    return bid.Stage__c == targetStage && previousStage != targetStage;
  }
}
