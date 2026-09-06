public with sharing class AccountCurrentCustomerUpdater {
  @TestVisible
  private static final String STAGE_CLOSED_LOST = 'Closed - LOST';

  public static void updateCustomers(List<Contract_Bid__c> wonBids) {
    Set<Id> customerIds = new Set<Id>();
    for (Contract_Bid__c bid : wonBids) {
      if (bid.Customer__c != null) {
        customerIds.add(bid.Customer__c);
      }
    }
    if (customerIds.isEmpty()) {
      return;
    }

    Map<Id, Account> existingById = new Map<Id, Account>(
      [SELECT Id, Contract_Periods__c FROM Account WHERE Id IN :customerIds]
    );

    Map<Id, Account> accountsById = new Map<Id, Account>();
    for (Contract_Bid__c bid : wonBids) {
      if (bid.Customer__c != null) {
        String existingPeriods = accountsById.containsKey(bid.Customer__c)
          ? accountsById.get(bid.Customer__c).Contract_Periods__c
          : existingById.get(bid.Customer__c)?.Contract_Periods__c;
        accountsById.put(
          bid.Customer__c,
          new Account(
            Id = bid.Customer__c,
            Current_Customer__c = true,
            Recent_Contract_Bid__c = bid.Id,
            Contract_Start_Date__c = bid.Contract_Start_Date__c,
            Contract_End_Date__c = bid.Contract_End_Date__c,
            Contract_Periods__c = String.isBlank(existingPeriods)
              ? bid.Contract_Year__c
              : existingPeriods + ';' + bid.Contract_Year__c
          )
        );
      }
    }
    updateAccounts(accountsById);
  }

  public static void clearCurrentCustomer(List<Contract_Bid__c> lostBids) {
    Map<Id, Account> accountsById = new Map<Id, Account>();
    for (Contract_Bid__c bid : lostBids) {
      if (bid.Customer__c != null) {
        accountsById.put(
          bid.Customer__c,
          new Account(Id = bid.Customer__c, Current_Customer__c = false)
        );
      }
    }
    updateAccounts(accountsById);
  }

  private static void updateAccounts(Map<Id, Account> accountsById) {
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