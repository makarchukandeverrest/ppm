trigger ContractBidTrigger on Contract_Bid__c(after insert, after update) {
  TriggerHandler handler = new ContractBidTriggerHandler();
  handler.run();
}
