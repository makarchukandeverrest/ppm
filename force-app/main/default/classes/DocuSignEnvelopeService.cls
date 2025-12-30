public with sharing class DocuSignEnvelopeService {
  private static List<String> additionalFilesNames = new List<String>{
    'Recommendation Letter',
    'General References',
    'COI'
  };

  @AuraEnabled
  public static void sendEnvelopeWithSignature(String accountsWithFilesJSON) {
    // Deserialize the data
    List<AccountWithFiles> accountWithFilesList = (List<AccountWithFiles>) JSON.deserialize(
      accountsWithFilesJSON,
      List<AccountWithFiles>.class
    );

    List<HttpRequestWrapper> requestWrappers = new List<HttpRequestWrapper>();
    Set<Id> contractIds = new Set<Id>();
    List<Contract_Bid__c> contractsToUpdate = new List<Contract_Bid__c>();
    List<EmailMessage> emailMessages = new List<EmailMessage>();
    Set<Id> accountIds = new Set<Id>();

    // Collect account IDs for query
    for (AccountWithFiles acc : accountWithFilesList) {
      accountIds.add(acc.accountId);
    }

    // Get all related Contract_Bid__c records and users
    Map<Id, List<User>> accountToUsersMap = getAccountToUsersMap(accountIds);

    User romanUser = [
      SELECT Id, Name, Email
      FROM User
      WHERE Name = 'Roman Shestakov'
      LIMIT 1
    ]; //TODO make user dynamical in future

    for (AccountWithFiles acc : accountWithFilesList) {
      for (FileWrapper file : acc.files) {
        if (file.ToSent) {
          String base64Doc = file.VersionDataBase64;
          String recipientEmail = acc.email;
          String recipientName = acc.accountName;
          String title = file.Title;

          List<User> ccUsers = accountToUsersMap.get(acc.accountId);
          if (romanUser != null) {
            ccUsers.add(romanUser); // Always add Roman as CC
          }

          String body = buildEnvelopeRequestBody(
            base64Doc,
            title,
            recipientEmail,
            recipientName,
            acc.newClient,
            ccUsers,
            acc.accountId
          );

          HttpRequestWrapper w = new HttpRequestWrapper();
          w.endpoint = 'callout:ArtemDocuDevCredential/restapi/v2.1/accounts/78090461/envelopes';
          // DocuSign Dev Account ID 41191243 - Prod  78090461
          w.method = 'POST';
          w.body = body;
          w.headers = new Map<String, String>{
            'Content-Type' => 'application/json'
          };

          EmailMessage emailMessage = new EmailMessage();
          emailMessage.Status = '0'; // 0 = Draft, 3 = Sent
          emailMessage.RelatedToId = acc.contract.Id; // Contract_Bid__c Id instead of Opportunity
          emailMessage.FromAddress = UserInfo.getUserEmail();
          emailMessage.FromName = UserInfo.getName();
          emailMessage.Subject = 'Sent Contracts for ' + recipientName;

          // Specify recipients
          emailMessage.ToIds = new List<String>{ acc.accountId };
          emailMessage.ToAddress = recipientEmail;
          emailMessage.TextBody = file.ContentDocumentId;
          emailMessages.add(emailMessage);
          requestWrappers.add(w);

          // Update contract stage
          acc.contract.Stage__c = 'Contract Sent via DocuSign';
          if (!contractIds.contains(acc.contract.Id)) {
            contractIds.add(acc.contract.Id);
            contractsToUpdate.add(acc.contract);
          }
        }
      }
    }
    System.debug('requestWrappers ' + requestWrappers);
    // Start sending process
    if (!requestWrappers.isEmpty()) {
      Database.executeBatch(new BatchHttpSender(requestWrappers), 1);
    }

    // Send email messages
    if (!emailMessages.isEmpty()) {
      System.enqueueJob(new InsertEmailMessagesJob(emailMessages));
    }

    // Update contracts
    if (!contractsToUpdate.isEmpty()) {
      update contractsToUpdate;
    }
  }

  // New method to get users from Contract_Bid__c fields with deduplication
  private static Map<Id, List<User>> getAccountToUsersMap(Set<Id> accountIds) {
    Map<Id, List<User>> accountToUsersMap = new Map<Id, List<User>>();

    // Initialize map for all accountIds
    for (Id accountId : accountIds) {
      accountToUsersMap.put(accountId, new List<User>());
    }

    // Get active contract stages
    List<String> activeStages = getActiveContractStages();

    // Query Contract_Bid__c with related users
    List<Contract_Bid__c> contracts = [
      SELECT
        Id,
        Customer__c,
        Lead_Generator__c,
        Lead_Generator__r.Email,
        Lead_Generator__r.Name,
        Lead_Owner__c,
        Lead_Owner__r.Email,
        Lead_Owner__r.Name
      FROM Contract_Bid__c
      WHERE
        Customer__c IN :accountIds
        AND Stage__c IN :activeStages
        AND (Lead_Generator__c != NULL
        OR Lead_Owner__c != NULL)
    ];

    // Populate map with users (with deduplication)
    for (Contract_Bid__c contract : contracts) {
      List<User> users = accountToUsersMap.get(contract.Customer__c);
      Set<String> existingEmails = new Set<String>();

      // Collect existing emails to avoid duplicates
      for (User existingUser : users) {
        existingEmails.add(existingUser.Email.toLowerCase());
      }

      // Add Lead Generator if email exists and not already in list
      if (
        contract.Lead_Generator__c != null &&
        String.isNotBlank(contract.Lead_Generator__r.Email) &&
        !existingEmails.contains(contract.Lead_Generator__r.Email.toLowerCase())
      ) {
        users.add(contract.Lead_Generator__r);
        existingEmails.add(contract.Lead_Generator__r.Email.toLowerCase());
      }

      // Add Lead Owner if email exists and not already in list
      if (
        contract.Lead_Owner__c != null &&
        String.isNotBlank(contract.Lead_Owner__r.Email) &&
        !existingEmails.contains(contract.Lead_Owner__r.Email.toLowerCase())
      ) {
        users.add(contract.Lead_Owner__r);
        existingEmails.add(contract.Lead_Owner__r.Email.toLowerCase());
      }
    }

    return accountToUsersMap;
  }

  // Method to get active stages (extracted for reusability)
  private static List<String> getActiveContractStages() {
    Schema.DescribeFieldResult fieldResult = Contract_Bid__c.Stage__c.getDescribe();
    List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
    List<String> stagesToRemove = new List<String>{
      'Contact Made',
      'Conversation Started',
      'Client Showed Interest',
      'Proposal/Review',
      'Renewal',
      'Closed - WON',
      'Closed - LOST',
      'Contract Sent via DocuSign'
    };

    List<String> activeStages = new List<String>();
    for (Schema.PicklistEntry entry : picklistValues) {
      if (entry.isActive() && !stagesToRemove.contains(entry.getValue())) {
        activeStages.add(entry.getValue());
      }
    }

    return activeStages;
  }

  public static String buildEnvelopeRequestBody(
    String base64Doc,
    String docName,
    String email,
    String name,
    Boolean isNewCustomer,
    List<User> ccUsers,
    Id accountId
  ) {
    List<Object> documents = new List<Object>();

    // Conditionally add extra documents if new customer
    if (isNewCustomer) {
      List<ContentDocumentLink> contentLinks = [
        SELECT Id, ContentDocumentId
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :accountId
      ];
      List<Id> contentDocIds = new List<Id>();
      for (ContentDocumentLink l : contentLinks) {
        contentDocIds.add(l.ContentDocumentId);
      }

      List<ContentVersion> extraDocs = [
        SELECT Id, Title, VersionData
        FROM ContentVersion
        WHERE
          Title IN :additionalFilesNames
          OR (Title LIKE '%Welcome Letter%'
          AND ContentDocumentId IN :contentDocIds)
      ];

      // Separate welcome letter from other documents
      List<ContentVersion> welcomeLetters = new List<ContentVersion>();
      List<ContentVersion> otherDocs = new List<ContentVersion>();

      for (ContentVersion cv : extraDocs) {
        System.debug('Extra Doc Title: ' + cv.Title);
        if (cv.Title.contains('Welcome Letter')) {
          welcomeLetters.add(cv);
        } else {
          otherDocs.add(cv);
        }
      }
      System.debug('Welcome Letters: ' + welcomeLetters);
      // Add welcome letter first if exists
      Integer docCounter = 1;
      if (!welcomeLetters.isEmpty()) {
        documents.add(
          new Map<String, Object>{
            'documentBase64' => EncodingUtil.base64Encode(
              welcomeLetters[0].VersionData
            ),
            'name' => welcomeLetters[0].Title,
            'fileExtension' => 'pdf',
            'documentId' => String.valueOf(docCounter)
          }
        );
        docCounter++;
      }

      // Always add the main contract document
      documents.add(
        new Map<String, Object>{
          'documentBase64' => base64Doc,
          'name' => docName,
          'fileExtension' => 'pdf',
          'documentId' => String.valueOf(docCounter)
        }
      );
      docCounter++;

      // Add other additional documents
      for (ContentVersion c : otherDocs) {
        documents.add(
          new Map<String, Object>{
            'documentBase64' => EncodingUtil.base64Encode(c.VersionData),
            'name' => c.Title,
            'fileExtension' => 'pdf',
            'documentId' => String.valueOf(docCounter)
          }
        );
        docCounter++;
      }
    } else {
      // For existing customers, just add the main contract document as documentId 1
      documents.add(
        new Map<String, Object>{
          'documentBase64' => base64Doc,
          'name' => docName,
          'fileExtension' => 'pdf',
          'documentId' => '1'
        }
      );
    }

    // Create carbonCopies list from users with deduplication
    List<Object> carbonCopies = new List<Object>();
    if (ccUsers != null && !ccUsers.isEmpty()) {
      Integer recipientId = 2; // Start from 2 since 1 is the signer
      Set<String> processedEmails = new Set<String>();

      for (User ccUser : ccUsers) {
        if (
          String.isNotBlank(ccUser.Email) &&
          !processedEmails.contains(ccUser.Email.toLowerCase())
        ) {
          carbonCopies.add(
            new Map<String, Object>{
              'email' => ccUser.Email,
              'name' => ccUser.Name,
              'recipientId' => String.valueOf(recipientId)
            }
          );
          processedEmails.add(ccUser.Email.toLowerCase());
          recipientId++;
        }
      }
    }

    Map<String, Object> body = new Map<String, Object>{
      'emailSubject' => 'Please sign this document',
      'documents' => documents,
      'recipients' => new Map<String, Object>{
        'signers' => new List<Object>{
          new Map<String, Object>{
            'email' => email,
            'name' => name,
            'recipientId' => '1',
            'tabs' => new Map<String, Object>{
              'signHereTabs' => new List<Object>{
                new Map<String, Object>{
                  'anchorString' => 'Please initial page(s) 2, 3, 4 and 5 of this contract where indicated. ',
                  'anchorYOffset' => '-10',
                  'anchorUnits' => 'pixels',
                  'anchorXOffset' => '0'
                }
              },
              // Use DocuSign built-in Full Name tab instead of generic text field
              'fullNameTabs' => new List<Object>{
                new Map<String, Object>{
                  'anchorString' => 'Please initial page(s) 2, 3, 4 and 5 of this contract where indicated. ',
                  'anchorYOffset' => '20',
                  'anchorUnits' => 'pixels',
                  'anchorXOffset' => '-40',
                  'name' => 'Full Name',
                  'tabLabel' => 'full_name'
                }
              },
              'dateSignedTabs' => new List<Object>{
                new Map<String, Object>{
                  'anchorString' => 'Please initial page(s) 2, 3, 4 and 5 of this contract where indicated. ',
                  'anchorYOffset' => '20',
                  'anchorUnits' => 'pixels',
                  'anchorXOffset' => '120',
                  'name' => 'Date Signed',
                  'tabLabel' => 'date_signed',
                  'value' => ''
                }
              },
              'initialHereTabs' => new List<Object>{
                new Map<String, Object>{
                  'anchorString' => 'Initial(s)',
                  'anchorUnits' => 'pixels',
                  'anchorXOffset' => '40',
                  'anchorYOffset' => '10',
                  'anchorMatchWholeWord' => true,
                  'anchorCaseSensitive' => true,
                  'anchorIgnoreIfNotPresent' => true,
                  'scaleValue' => '0.6'
                }
              }
            }
          }
        },
        'carbonCopies' => carbonCopies
      },
      'status' => 'sent'
    };

    return JSON.serialize(body);
  }
}