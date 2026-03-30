public with sharing class AccountCurrentCustomerUpdater {
  public static void updateCustomers(List<Contract_Bid__c> wonBids) {
    List<Account> accountsToUpdate = new List<Account>();
    for (Contract_Bid__c bid : wonBids) {
      System.debug('bid: ' + bid);
      System.debug('bid.Customer__c: ' + bid.Customer__c);
      if (bid.Customer__c != null) {
        accountsToUpdate.add(
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
    System.debug('accountsToUpdate: ' + accountsToUpdate);
    if (!accountsToUpdate.isEmpty()) {
      update accountsToUpdate;
    }
  }
}