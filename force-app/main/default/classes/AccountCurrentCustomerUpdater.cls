public with sharing class AccountCurrentCustomerUpdater {
  public static void updateCustomers(List<Contract_Bid__c> wonBids) {
    Map<Id, Account> accountsById = new Map<Id, Account>();
    for (Contract_Bid__c bid : bidsToUpdate) {
      if (bid.Customer__c == null) {
        continue;
      }
      Account acc = new Account(
        Id = bid.Customer__c,
        Current_Customer__c = customerIsCurrent
      );
      if (customerIsCurrent) {
        acc.Recent_Contract_Bid__c = bid.Id;
        acc.Contract_Start_Date__c = bid.Contract_Start_Date__c;
        acc.Contract_End_Date__c = bid.Contract_End_Date__c;
      }
      accountsById.put(bid.Customer__c, acc);
    }
    if (!accountsById.isEmpty()) {
      update accountsById.values();
    }
  }
}