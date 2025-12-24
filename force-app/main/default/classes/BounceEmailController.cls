public with sharing class BounceEmailController {

  public static void handleBouncedContractBidPackage(List<Contact> contacts) {
    System.debug('=== BounceEmailController.handleBouncedContractBidPackage START ===');

    if (contacts == null || contacts.isEmpty()) {
      System.debug('No contacts received');
      return;
    }

    System.debug('Incoming contacts size: ' + contacts.size());

    Set<Id> contactIds = new Set<Id>();
    Set<Id> accountsId = new Set<Id>();

    for (Contact c : contacts) {
      System.debug('Processing Contact: ' + c.Id + ' AccountId=' + c.AccountId);
      if (c.Id != null) {
        contactIds.add(c.Id);
      }
    }

    System.debug('Collected ContactIds: ' + contactIds);

    if (contactIds.isEmpty()) {
      System.debug('No ContactIds collected');
      return;
    }

    List<Contact> contactsWithAccount = [
      SELECT Id, AccountId
      FROM Contact
      WHERE Id IN :contactIds AND AccountId != NULL
    ];

    System.debug('Contacts with AccountId: ' + contactsWithAccount.size());

    for (Contact c : contactsWithAccount) {
      accountsId.add(c.AccountId);
    }

    System.debug('Collected AccountIds: ' + accountsId);

    if (!accountsId.isEmpty()) {
      changeContractBidStage(accountsId);
      notifyManagersForContacts(accountsId);
    } else {
      System.debug('No AccountIds found → skipping stage update & notification');
    }

    System.debug('=== BounceEmailController.handleBouncedContractBidPackage END ===');
  }

  private static void changeContractBidStage(Set<Id> accountsId) {
    System.debug('--- changeContractBidStage START ---');
    System.debug('AccountIds: ' + accountsId);

    if (accountsId == null || accountsId.isEmpty()) {
      System.debug('No AccountIds received');
      return;
    }

    List<Contract_Bid__c> contractBids = [
      SELECT Id, Name, Stage__c, Customer__c
      FROM Contract_Bid__c
      WHERE
        Customer__c IN :accountsId
        AND (Stage__c = 'Information Verified'
        OR Stage__c = 'Contract Bid Package Sent')
    ];

    System.debug('ContractBids found for update: ' + contractBids.size());

    if (contractBids.isEmpty()) {
      System.debug('No ContractBids in target stages');
      return;
    }

    for (Contract_Bid__c c : contractBids) {
      System.debug('Updating ContractBid ' + c.Id + ' Stage from ' + c.Stage__c);
      c.Stage__c = 'Need Contact Verification';
    }

    try {
      update contractBids;
      System.debug('ContractBids updated successfully');
    } catch (DmlException e) {
      System.debug('ERROR updating ContractBids: ' + e.getMessage());
    }

    System.debug('--- changeContractBidStage END ---');
  }

  private static void notifyManagersForContacts(Set<Id> accountIds) {
    System.debug('--- notifyManagersForContacts START ---');
    System.debug('AccountIds: ' + accountIds);

    if (accountIds == null || accountIds.isEmpty()) {
      System.debug('No AccountIds received');
      return;
    }

    try {
      CustomNotificationType notificationType = [
        SELECT Id, DeveloperName
        FROM CustomNotificationType
        WHERE DeveloperName = 'Bounced_Email'
        LIMIT 1
      ];

      System.debug('NotificationType Id: ' + notificationType.Id);

      List<Account> accounts = [
        SELECT Id, Regional_Manager__c, Name
        FROM Account
        WHERE Id IN :accountIds AND Regional_Manager__c != NULL
      ];

      System.debug('Accounts with Regional Manager: ' + accounts.size());

      if (accounts.isEmpty()) {
        System.debug('No accounts with Regional Manager found');
        return;
      }

      Set<String> notificationKeys = new Set<String>();

      for (Account acc : accounts) {
        System.debug(
          'Account ' + acc.Id +
          ' Name=' + acc.Name +
          ' RM=' + acc.Regional_Manager__c
        );

        String key = acc.Id + '_' + acc.Regional_Manager__c;
        if (notificationKeys.contains(key)) {
          System.debug('Duplicate notification skipped for key ' + key);
          continue;
        }

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setTitle('Email Bounced');
        notification.setBody('Email bounced for account: ' + acc.Name);
        notification.setNotificationTypeId(notificationType.Id);
        notification.setTargetId(acc.Id);

        try {
          notification.send(new Set<String>{ acc.Regional_Manager__c });
          notificationKeys.add(key);
          System.debug('Notification sent to RM ' + acc.Regional_Manager__c);
        } catch (Exception ex) {
          System.debug('ERROR sending notification: ' + ex.getMessage());
        }
      }
    } catch (Exception e) {
      System.debug('ERROR in notifyManagersForContacts: ' + e.getMessage());
    }

    System.debug('--- notifyManagersForContacts END ---');
  }
}