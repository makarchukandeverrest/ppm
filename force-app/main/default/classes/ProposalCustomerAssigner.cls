public inherited sharing class ProposalCustomerAssigner {
  private static final String LOG = 'ProposalCustomerAssigner';

  public static void assignCustomer(List<Opportunity> opps) {

    Set<String> qbIds = new Set<String>();

    for (Opportunity opp : opps) {
      if (opp.Account_QuickBooks_Id__c != null) {
        qbIds.add(opp.Account_QuickBooks_Id__c);
      }
    }

    if (qbIds.isEmpty()) {
      System.debug(
        LOG + ': no Account_QuickBooks_Id__c on any opportunity, exiting'
      );
      return;
    }

    List<Account> accounts = [
      SELECT
        Id,
        QuickBooks_Id__c,
        Billing_Contact__c,
        Maintenance_Contact__c,
        Primary_Contact__c,
        Secondary_Contact__c
      FROM Account
      WHERE QuickBooks_Id__c IN :qbIds
    ];

    Map<String, Account> accountByQbId = new Map<String, Account>();

    for (Account a : accounts) {
      if (a.QuickBooks_Id__c != null) {
        accountByQbId.put(a.QuickBooks_Id__c, a);
      }
    }

    Integer assigned = 0;
    Integer skippedNoQb = 0;
    Integer noMatchingAccount = 0;

    for (Opportunity opp : opps) {
      if (opp.Account_QuickBooks_Id__c == null) {
        skippedNoQb++;
        continue;
      }

      Account matched = accountByQbId.get(opp.Account_QuickBooks_Id__c);

      if (matched != null) {
        if (opp.AccountId == null) {
          opp.AccountId = matched.Id;
        }
        if (opp.Customer_Billing_Contact__c == null) {
          opp.Customer_Billing_Contact__c = matched.Billing_Contact__c;
        }
        if (opp.Customer_Maintenance_Contact__c == null) {
          opp.Customer_Maintenance_Contact__c = matched.Maintenance_Contact__c;
        }
        if (opp.Customer_Primary_Contact__c == null) {
          opp.Customer_Primary_Contact__c = matched.Primary_Contact__c;
        }
        if (opp.Customer_Secondary_Contact__c == null) {
          opp.Customer_Secondary_Contact__c = matched.Secondary_Contact__c;
        }

        assigned++;
      } else {
        noMatchingAccount++;
      }
    }
  }
}