trigger ContractBidTrigger on Contract_Bid__c(before insert, after insert, after update, before update) {
  TriggerHandler handler = new ContractBidTriggerHandler();
  handler.run();
}