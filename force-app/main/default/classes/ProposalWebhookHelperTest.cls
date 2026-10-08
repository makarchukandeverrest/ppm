@isTest
private class ProposalWebhookHelperTest {
  @isTest
  static void collectProposalIdsFromProposals_includesInsertAndWatchedUpdate() {
    Opportunity inserted = new Opportunity(
      Name = 'New Proposal',
      CloseDate = Date.today(),
      StageName = 'Draft'
    );
    inserted.Id = getFakeId(Opportunity.SObjectType, 1);

    Set<Id> insertIds = ProposalWebhookHelper.collectProposalIdsFromProposals(
      new List<Opportunity>{ inserted },
      null
    );
    System.assertEquals(
      1,
      insertIds.size(),
      'Insert should always be collected'
    );

    Opportunity oldProposal = new Opportunity(
      Id = inserted.Id,
      Name = 'New Proposal',
      CloseDate = Date.today(),
      StageName = 'Draft',
      Reference_Number__c = 'OLD'
    );
    Opportunity newProposal = oldProposal.clone(true, true, true, true);
    newProposal.Reference_Number__c = 'NEW';

    Set<Id> updateIds = ProposalWebhookHelper.collectProposalIdsFromProposals(
      new List<Opportunity>{ newProposal },
      new Map<Id, Opportunity>{ oldProposal.Id => oldProposal }
    );
    System.assertEquals(
      1,
      updateIds.size(),
      'Watched field change should be collected'
    );
  }

  @isTest
  static void collectProposalIdsFromProposals_skipsUnwatchedUpdate() {
    Id proposalId = getFakeId(Opportunity.SObjectType, 2);
    Opportunity oldProposal = new Opportunity(
      Id = proposalId,
      Name = 'Old Name',
      CloseDate = Date.today(),
      StageName = 'Draft'
    );
    Opportunity newProposal = oldProposal.clone(true, true, true, true);
    newProposal.Name = 'New Name';

    Set<Id> updateIds = ProposalWebhookHelper.collectProposalIdsFromProposals(
      new List<Opportunity>{ newProposal },
      new Map<Id, Opportunity>{ oldProposal.Id => oldProposal }
    );
    System.assertEquals(
      0,
      updateIds.size(),
      'Unwatched field change should be ignored'
    );
  }

  @isTest
  static void collectProposalIdsFromLineItems_includesParentOnWatchedChange() {
    Id proposalId = getFakeId(Opportunity.SObjectType, 3);
    Id lineItemId = getFakeId(Deal_Line_Item__c.SObjectType, 1);

    Deal_Line_Item__c oldItem = new Deal_Line_Item__c(
      Id = lineItemId,
      Name = 'Item',
      Quantity__c = 1,
      Deal__c = proposalId
    );
    Deal_Line_Item__c newItem = oldItem.clone(true, true, true, true);
    newItem.Quantity__c = 5;

    Set<Id> proposalIds = ProposalWebhookHelper.collectProposalIdsFromLineItems(
      new List<Deal_Line_Item__c>{ newItem },
      new Map<Id, Deal_Line_Item__c>{ oldItem.Id => oldItem }
    );
    System.assertEquals(true, proposalIds.contains(proposalId));
  }

  private static Id getFakeId(
    Schema.SObjectType sobjectType,
    Integer sequence
  ) {
    String prefix = sobjectType.getDescribe().getKeyPrefix();
    String suffix = String.valueOf(sequence).leftPad(12, '0');
    return Id.valueOf(prefix + suffix);
  }
}
