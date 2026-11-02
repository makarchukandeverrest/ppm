public with sharing class DocuSignEnvelopeTriggerHandler extends TriggerHandler {
  private static final String ENVELOPE_STATUS_SENT = 'Sent';

  List<dfsle__Envelope__c> newList;
  Map<Id, dfsle__Envelope__c> oldMap;

  public DocuSignEnvelopeTriggerHandler() {
    this.newList = (List<dfsle__Envelope__c>) Trigger.new;
    this.oldMap = (Map<Id, dfsle__Envelope__c>) Trigger.oldMap;
  }

  protected override void afterInsert() {
    ContractBidSendCleanupService.completeOpenFollowUpTasks(
      collectContractBidIds(null)
    );
  }

  protected override void afterUpdate() {
    ContractBidSendCleanupService.completeOpenFollowUpTasks(
      collectContractBidIds(this.oldMap)
    );
  }

  private Set<Id> collectContractBidIds(
    Map<Id, dfsle__Envelope__c> previousById
  ) {
    Set<Id> bidIds = new Set<Id>();
    for (dfsle__Envelope__c envelope : this.newList) {
      if (envelope.Status__c != ENVELOPE_STATUS_SENT) {
        continue;
      }
      dfsle__Envelope__c oldEnvelope = previousById == null
        ? null
        : previousById.get(envelope.Id);
      if (
        oldEnvelope != null &&
        oldEnvelope.Status__c == ENVELOPE_STATUS_SENT
      ) {
        continue;
      }
      if (String.isBlank(envelope.dfsle__SourceId__c)) {
        continue;
      }
      try {
        Id sourceId = Id.valueOf(envelope.dfsle__SourceId__c);
        if (sourceId.getSObjectType() == Contract_Bid__c.SObjectType) {
          bidIds.add(sourceId);
        }
      } catch (Exception ex) {
        // ignore non-Id source values
      }
    }
    return bidIds;
  }
}
