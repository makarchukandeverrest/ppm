public inherited sharing class ProposalCustomerAssigner {
  private static final String LOG = 'ProposalCustomerAssigner';

  public static void assignCustomer(List<Opportunity> opps) {
    System.debug(
      LOG + ': assignCustomer start, opportunityCount=' + opps.size()
    );

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

    System.debug(LOG + ': distinct Account_QuickBooks_Id__c count=' + qbIds.size() + ', values=' + String.valueOf(qbIds));

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

    System.debug(LOG + ': Account query returned rows=' + accounts.size());

    Map<String, Account> accountByQbId = new Map<String, Account>();

    for (Account a : accounts) {
      if (a.QuickBooks_Id__c != null) {
        accountByQbId.put(a.QuickBooks_Id__c, a);
      }
    }

    System.debug(LOG + ': accountByQbId size=' + accountByQbId.size());

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
        opp.AccountId = matched.Id;

        opp.Customer_Billing_Contact__c = matched.Billing_Contact__c;

        opp.Customer_Maintenance_Contact__c = matched.Maintenance_Contact__c;

        opp.Customer_Primary_Contact__c = matched.Primary_Contact__c;

        opp.Customer_Secondary_Contact__c = matched.Secondary_Contact__c;

        assigned++;
        System.debug(
          LOG +
            ': assigned AccountId=' +
            matched.Id +
            ' for Account_QuickBooks_Id__c=' +
            opp.Account_QuickBooks_Id__c +
            (opp.Id != null ? ', OpportunityId=' + opp.Id : ', OpportunityId=(before insert)')
        );
      } else {
        noMatchingAccount++;
        System.debug(
          LoggingLevel.WARN,
          LOG +
            ': no Account with QuickBooks_Id__c=' +
            opp.Account_QuickBooks_Id__c +
            (opp.Id != null ? ', OpportunityId=' + opp.Id : ', OpportunityId=(before insert)')
        );
      }
    }

    System.debug(
      LOG +
        ': assignCustomer end, assigned=' +
        assigned +
        ', skippedNoAccountQbId=' +
        skippedNoQb +
        ', noMatchingAccount=' +
        noMatchingAccount
    );
  }
}