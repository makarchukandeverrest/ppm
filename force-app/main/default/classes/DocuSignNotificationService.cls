public with sharing class DocuSignNotificationService {
  public static void handleEnvelopeStatusChange(
    List<ContentVersion> newVersions
  ) {
    // Detect sandbox safely
    Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;

    List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
    List<Task> tasksToInsert = new List<Task>();

    Set<Id> contentDocIds = new Set<Id>();
    for (ContentVersion c : newVersions) {
      contentDocIds.add(c.ContentDocumentId);
    }

    // Find Accounts via ContentDocumentLink
    List<ContentDocumentLink> links = [
      SELECT LinkedEntityId, ContentDocumentId
      FROM ContentDocumentLink
      WHERE ContentDocumentId IN :contentDocIds
    ];

    Map<Id, Id> contentDocToAccount = new Map<Id, Id>();
    Set<Id> accountIds = new Set<Id>();

    for (ContentDocumentLink l : links) {
      if (String.valueOf(l.LinkedEntityId).startsWith('001')) {
        contentDocToAccount.put(l.ContentDocumentId, l.LinkedEntityId);
        accountIds.add(l.LinkedEntityId);
      }
    }

    if (accountIds.isEmpty())
      return;

    // Load Active Stages from Custom Metadata
    Set<String> activeStages = new Set<String>();

    StageReferenceSettings__mdt settings = [
      SELECT Stage_Names__c
      FROM StageReferenceSettings__mdt
      WHERE DeveloperName = 'Active_Stages'
      LIMIT 1
    ];

    if (settings != null && String.isNotBlank(settings.Stage_Names__c)) {
      for (String s : settings.Stage_Names__c.split(',')) {
        activeStages.add(s.trim());
      }
    }

    if (activeStages.isEmpty())
      return;

    // Find Contract Bids with active stages
    List<Contract_Bid__c> bids = [
      SELECT Id, Name, Customer__c, Contract_Creator_Picklist__c, Stage__c
      FROM Contract_Bid__c
      WHERE Customer__c IN :accountIds AND Stage__c IN :activeStages
    ];

    Map<Id, Contract_Bid__c> accountToBid = new Map<Id, Contract_Bid__c>();
    Set<Id> creatorUserIds = new Set<Id>();
    for (Contract_Bid__c b : bids) {
      accountToBid.put(b.Customer__c, b);
      Id creatorUserId = ContractCreatorUserResolver.resolveUserId(
        b.Contract_Creator_Picklist__c
      );
      if (creatorUserId != null) {
        creatorUserIds.add(creatorUserId);
      }
    }

    Map<Id, User> creatorsById = creatorUserIds.isEmpty()
      ? new Map<Id, User>()
      : new Map<Id, User>(
          [SELECT Id, Email FROM User WHERE Id IN :creatorUserIds]
        );

    // Generate Tasks + Emails
    for (ContentVersion cv : newVersions) {
      Id accId = contentDocToAccount.get(cv.ContentDocumentId);
      if (accId == null || !accountToBid.containsKey(accId))
        continue;

      Contract_Bid__c bid = accountToBid.get(accId);
      Id creatorUserId = ContractCreatorUserResolver.resolveUserId(
        bid.Contract_Creator_Picklist__c
      );
      if (creatorUserId == null || !creatorsById.containsKey(creatorUserId))
        continue;

      User creator = creatorsById.get(creatorUserId);
      String status = cv.DocuSign_Envelope_Status__c;

      // Email (only PROD)
      if (!isSandbox && String.isNotBlank(creator.Email)) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ creator.Email });
        mail.setSubject(
          'DocuSign Envelope for Contract Bid "' +
            bid.Name +
            '" changed status to ' +
            status
        );
        mail.setPlainTextBody(
          'Hello,\n\n' +
            'The DocuSign envelope has changed status to "' +
            status +
            '".\n\n' +
            'Document: ' +
            cv.Title +
            '\n' +
            'Completed Date: ' +
            System.now() +
            '\n\n' +
            'Best regards,\nSalesforce System'
        );
        emailsToSend.add(mail);
      }

      // Task
      Task t = new Task();
      t.OwnerId = creatorUserId;
      t.WhatId = bid.Id;
      t.Subject = 'DocuSign Envelope status changed to ' + status;
      t.Description =
        'DocuSign envelope for "' +
        bid.Name +
        '" changed status to "' +
        status +
        '"';
      t.Status = 'Completed';
      t.Priority = 'Normal';
      t.ActivityDate = Date.today();

      tasksToInsert.add(t);
    }

    // Send Emails (PROD only)
    if (!emailsToSend.isEmpty() && !isSandbox) {
      Messaging.sendEmail(emailsToSend);
    }

    // Insert Tasks
    if (!tasksToInsert.isEmpty()) {
      insert tasksToInsert;
    }
  }
}
