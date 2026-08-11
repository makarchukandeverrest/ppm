trigger ContractBidTrigger on Contract_Bid__c(before insert, after insert, after update) {
  TriggerHandler handler = new ContractBidTriggerHandler();
  handler.run();
}