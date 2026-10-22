public with sharing class ContractBidRequestStageService {
  @TestVisible
  private static final String REQUEST_SUBJECT = 'Request a Contract Bid';
  private static final String BID_QUALIFIED = 'Contact Made';
  private static final String CONTRACT_REQUESTED = 'Contract Requested';

  public static void moveToContractRequested(List<Task> tasks) {
    Set<Id> bidIds = new Set<Id>();
    for (Task taskRecord : tasks) {
      if (!isContractRequest(taskRecord)) {
        continue;
      }
      bidIds.add(taskRecord.WhatId);
    }
    if (bidIds.isEmpty()) {
      return;
    }

    List<Contract_Bid__c> bids = [
      SELECT Id
      FROM Contract_Bid__c
      WHERE Id IN :bidIds AND Stage__c = :BID_QUALIFIED
    ];
    for (Contract_Bid__c bid : bids) {
      bid.Stage__c = CONTRACT_REQUESTED;
    }
    if (!bids.isEmpty()) {
      update bids;
    }
  }

  private static Boolean isContractRequest(Task taskRecord) {
    return taskRecord.WhatId != null &&
      taskRecord.WhatId.getSObjectType() == Contract_Bid__c.SObjectType &&
      taskRecord.Subject == REQUEST_SUBJECT;
  }
}
