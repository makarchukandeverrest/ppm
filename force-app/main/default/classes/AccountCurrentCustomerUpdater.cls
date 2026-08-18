public with sharing class AccountCurrentCustomerUpdater {
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
}