trigger DocuSignEnvelopeTrigger on dfsle__Envelope__c(
  after insert,
  after update
) {
  TriggerHandler handler = new DocuSignEnvelopeTriggerHandler();
  handler.run();
}
