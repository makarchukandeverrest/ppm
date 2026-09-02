public with sharing class AccountCurrentCustomerUpdater {
  @TestVisible
  private static final String STAGE_CLOSED_LOST = 'Closed - LOST';

  public static void updateCustomers(List<Contract_Bid__c> wonBids) {
    Map<Id, Account> accountsById = new Map<Id, Account>();
    for (Contract_Bid__c bid : wonBids) {
      if (bid.Customer__c != null) {
        accountsById.put(
          bid.Customer__c,
          new Account(
            Id = bid.Customer__c,
            Current_Customer__c = true,
            Recent_Contract_Bid__c = bid.Id,
            Contract_Start_Date__c = bid.Contract_Start_Date__c,
            Contract_End_Date__c = bid.Contract_End_Date__c
          )
        );
      }
    }
    if (!accountsById.isEmpty()) {
      update accountsById.values();
    }
  }

  public static void clearCurrentCustomerOnLost(List<Account> accounts, Map<Id, Account> oldMap) {
    if (accounts == null || oldMap == null) {
      return;
    }
    for (Account acc : accounts) {
      Account oldAcc = oldMap.get(acc.Id);
      if (oldAcc == null) {
        continue;
      }
      if (acc.Stage__c == STAGE_CLOSED_LOST && oldAcc.Stage__c != STAGE_CLOSED_LOST) {
        acc.Current_Customer__c = false;
      }
    }
  }
}