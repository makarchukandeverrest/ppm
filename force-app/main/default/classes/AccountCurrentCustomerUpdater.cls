public with sharing class AccountCurrentCustomerUpdater {
  public static void updateCustomers(List<Contract_Bid__c> bidsToUpdate, Boolean customerIsCurrent) {
    List<Account> accountsToUpdate = new List<Account>();
    for (Contract_Bid__c bid : bidsToUpdate) {
      if (bid.Customer__c != null) {
        accountsToUpdate.add(
          new Account(
            Id = bid.Customer__c,
            Current_Customer__c = customerIsCurrent,
            Recent_Contract_Bid__c = bid.Id,
            Contract_Start_Date__c = bid.Contract_Start_Date__c,
            Contract_End_Date__c = bid.Contract_End_Date__c
          )
        );
      }
    }
    if (!accountsToUpdate.isEmpty()) {
      update accountsToUpdate;
    }
  }
}