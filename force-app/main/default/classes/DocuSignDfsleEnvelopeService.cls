public with sharing class DocuSignDfsleEnvelopeService {

    private static final String ANCHOR_MAIN =
        'Please initial page(s) 2, 3, 4 and 5 of this contract where indicated. ';

    private static final String ENVELOPE_EMAIL_SUBJECT = 'Please sign this document';

    private static final String ENVELOPE_EMAIL_BODY_INTRO =
        'I am sending you this request for your electronic signature, please review and electronically sign by following the link. Additional reference documents:';

    private static final List<String> NEW_CUSTOMER_RESOURCE_LABELS = new List<String>{
        'Recommendation Letter',
        'General References',
        'COI'
    };

    private static final Map<String, String> NEW_CUSTOMER_RESOURCE_URL_BY_LABEL = new Map<String, String>{
        'COI' => Document_Link__mdt.getInstance('COI').Sharing_Link__c,
        'Recommendation Letter' => Document_Link__mdt.getInstance('Recommendation_Letter').Sharing_Link__c,
        'General References' => Document_Link__mdt.getInstance('General_References').Sharing_Link__c
    };

    public class SendResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String envelopeId;
        @AuraEnabled public String message;
    }

    @TestVisible
    public static Boolean FORCE_RESOLVE_DOCUSIGN_ID_IN_TEST = false;

    @AuraEnabled
    public static void sendEnvelopeWithSignature(String accountsWithFilesJSON) {
        if (String.isBlank(accountsWithFilesJSON)) {
            return;
        }

        List<AccountWithFiles> accountWithFilesList = (List<AccountWithFiles>) JSON.deserialize(
            accountsWithFilesJSON,
            List<AccountWithFiles>.class
        );

        Set<Id> accountIds = new Set<Id>();
        Set<Id> mainContentVersionIds = new Set<Id>();
        List<Contract_Bid__c> contractsToUpdate = new List<Contract_Bid__c>();
        Set<Id> contractIds = new Set<Id>();
        List<EmailMessage> emailMessages = new List<EmailMessage>();

        for (AccountWithFiles acc : accountWithFilesList) {
            if (acc == null) continue;
            if (acc.accountId != null) accountIds.add(acc.accountId);
            if (acc.files == null) continue;
            for (FileWrapper file : acc.files) {
                if (file != null && file.ToSent == true && file.Id != null) {
                    mainContentVersionIds.add(file.Id);
                }
            }
        }

        Map<Id, List<User>> accountToUsersMap = getAccountToUsersMap(accountIds);

        User romanUser;
        try {
            romanUser = [SELECT Id, Name, Email FROM User WHERE Name = 'Roman Shestakov' LIMIT 1];
        } catch (Exception ex) {
            romanUser = null;
        }

        Map<Id, ContentVersion> cvById = new Map<Id, ContentVersion>();
        if (!mainContentVersionIds.isEmpty()) {
            cvById = new Map<Id, ContentVersion>([
                SELECT Id
                FROM ContentVersion
                WHERE Id IN :mainContentVersionIds
            ]);
        }

        for (AccountWithFiles acc : accountWithFilesList) {
            if (acc == null || acc.files == null) continue;
            if (acc.contract == null || acc.contract.Id == null) continue;
            if (String.isBlank(acc.email) || String.isBlank(acc.accountName)) continue;

            List<User> ccUsers = accountToUsersMap.containsKey(acc.accountId)
                ? accountToUsersMap.get(acc.accountId)
                : new List<User>();
            if (ccUsers == null) ccUsers = new List<User>();
            if (romanUser != null) {
                ccUsers.add(romanUser);
            }

            for (FileWrapper file : acc.files) {
                if (file == null || file.ToSent != true || file.Id == null) continue;
                if (!cvById.containsKey(file.Id)) continue;

                sendEnvelope(
                    acc.contract.Id,
                    file.Id,
                    acc.email,
                    acc.accountName,
                    acc.newClient == true,
                    acc.accountId,
                    ccUsers,
                    acc.reminderValue,
                    acc.daysBeforeExpires
                );


                acc.contract.Stage__c = 'Contract Sent via DocuSign';
                if (!contractIds.contains(acc.contract.Id)) {
                    contractIds.add(acc.contract.Id);
                    contractsToUpdate.add(acc.contract);
                }

                EmailMessage emailMessage = new EmailMessage();
                emailMessage.Status      = '0'; // Draft
                emailMessage.RelatedToId = acc.contract.Id;
                emailMessage.FromAddress = UserInfo.getUserEmail();
                emailMessage.FromName    = UserInfo.getName();
                emailMessage.Subject     = 'Sent Contracts for ' + acc.accountName;
                emailMessage.ToIds       = new String[]{ acc.accountId };
                emailMessage.ToAddress   = acc.email;
                emailMessage.TextBody    = String.valueOf(file.ContentDocumentId);
                emailMessages.add(emailMessage);
            }
        }

        if (!emailMessages.isEmpty()) {
            System.enqueueJob(new InsertEmailMessagesJob(emailMessages));
        }
        if (!contractsToUpdate.isEmpty()) {
            update contractsToUpdate;
        }
    }


    public static String sendEnvelope(
        Id contractBidId,
        Id mainContentVersionId,
        String signerEmail,
        String signerName,
        Boolean isNewCustomer,
        Id accountId,
        List<User> ccUsers,
        String reminderValue,
        String daysBeforeExpires
    ) {
        List<Id> documentCvIds = getContentVersionIdsForEnvelope(
            mainContentVersionId,
            isNewCustomer,
            accountId
        );

        dfsle.Envelope env = dfsle.EnvelopeService.getEmptyEnvelope(
            new dfsle.Entity(contractBidId)
        );

        String envelopeEmailBody = buildEnvelopeEmailBody(isNewCustomer);
        if (String.isNotBlank(envelopeEmailBody)) {
            env = env.withEmail(ENVELOPE_EMAIL_SUBJECT, envelopeEmailBody);
        }

        List<dfsle.Document> docs = dfsle.DocumentService.getDocuments(
            ContentVersion.SObjectType,
            new Set<Id>(documentCvIds)
        );
        env = env.withDocuments(docs);
        env = env.withRecipients(
            buildRecipients(contractBidId, signerEmail, signerName, ccUsers)
        );
        env = env.withOptions(buildEnvelopeOptions(contractBidId, reminderValue, daysBeforeExpires));

        String envelopeId;
        if (Test.isRunningTest() && FORCE_RESOLVE_DOCUSIGN_ID_IN_TEST == true) {
            envelopeId = resolveDocuSignEnvelopeId(null, contractBidId);
        } else if (Test.isRunningTest()) {
            envelopeId = 'TEST-DFSLE-ENVELOPE';
        } else {
            dfsle.Envelope sent = dfsle.EnvelopeService.sendEnvelope(env, true);
            envelopeId = resolveDocuSignEnvelopeId(sent, contractBidId);
        }

        if (String.isNotBlank(envelopeId)) {
            update new ContentVersion(
                Id = mainContentVersionId,
                DocuSign_Envelope_Id__c = envelopeId.toUpperCase(),
                To_Sent__c = false
            );
        }

        return envelopeId;
    }

    @TestVisible
    private static List<Id> getContentVersionIdsForEnvelope(
        Id mainContentVersionId,
        Boolean isNewCustomer,
        Id accountId
    ) {
        List<Id> cvIds = new List<Id>();

        if (!isNewCustomer) {
            cvIds.add(mainContentVersionId);
            return cvIds;
        }

        List<ContentDocumentLink> contentLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :accountId
        ];
        Set<Id> contentDocIds = new Set<Id>();
        for (ContentDocumentLink link : contentLinks) {
            contentDocIds.add(link.ContentDocumentId);
        }

        List<ContentVersion> welcomeLetters = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE
                Title LIKE '%Welcome Letter%'
                AND ContentDocumentId IN :contentDocIds
            LIMIT 1
        ];

        if (!welcomeLetters.isEmpty()) {
            cvIds.add(welcomeLetters[0].Id);
        }
        cvIds.add(mainContentVersionId);

        return cvIds;
    }

    @TestVisible
    private static String buildEnvelopeEmailBody(Boolean isNewCustomer) {
        if (isNewCustomer != true) {
            return null;
        }

        String resourceLinksHtml = buildEnvelopeResourceLinksHtml();
        if (String.isBlank(resourceLinksHtml)) {
            return null;
        }

        return '<p>' + escapeHtmlText(ENVELOPE_EMAIL_BODY_INTRO) + '</p>' + resourceLinksHtml;
    }

    private static String buildEnvelopeResourceLinksHtml() {
        List<String> items = new List<String>();
        for (String label : NEW_CUSTOMER_RESOURCE_LABELS) {
            String url = NEW_CUSTOMER_RESOURCE_URL_BY_LABEL.get(label);
            if (String.isBlank(url)) {
                continue;
            }
            items.add(
                '<li><a href="' +
                escapeHtmlAttribute(url) +
                '">' +
                escapeHtmlText(label) +
                '</a></li>'
            );
        }
        if (items.isEmpty()) {
            return '';
        }
        return '<ul>' + String.join(items, '') + '</ul>';
    }

    private static String escapeHtmlText(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;');
    }

    private static String escapeHtmlAttribute(String value) {
        if (value == null) {
            return '';
        }
        return escapeHtmlText(value).replace('"', '&quot;');
    }

    @TestVisible
    private static List<dfsle.Tab> buildSignerTabs() {
        dfsle.Tab.Anchor mainAnchor = new dfsle.Tab.Anchor(
            ANCHOR_MAIN,
            false,
            false,
            null,
            true,
            false,
            'pixels',
            0,
            -10
        );

        dfsle.Tab.Anchor mainAnchorFullName = new dfsle.Tab.Anchor(
            ANCHOR_MAIN,
            false,
            false,
            null,
            true,
            false,
            'pixels',
            -40,
            20
        );

        dfsle.Tab.Anchor mainAnchorDateSigned = new dfsle.Tab.Anchor(
            ANCHOR_MAIN,
            false,
            false,
            null,
            true,
            false,
            'pixels',
            120,
            20
        );

        dfsle.Tab.Anchor initialAnchor = new dfsle.Tab.Anchor(
            'Initial(s)',
            false,
            true,
            null,
            true,
            true,
            'pixels',
            40,
            10
        );

        return new List<dfsle.Tab>{
            new dfsle.SignHereTab()
                .withRequired(true)
                .withAnchor(mainAnchor),
            new dfsle.TextTab()
                .withDataLabel('full_name')
                .withAnchor(mainAnchorFullName),
            new dfsle.DateSignedTab()
                .withAnchor(mainAnchorDateSigned),
            new dfsle.InitialHereTab()
                .withScale(0.6)
                .withAnchor(initialAnchor)
        };
    }

    @TestVisible
    private static List<dfsle.Recipient> buildRecipients(
        Id contractBidId,
        String signerEmail,
        String signerName,
        List<User> ccUsers
    ) {
        dfsle.Recipient signer = dfsle.Recipient.fromSource(
            signerName,
            signerEmail,
            null,
            'Signer',
            new dfsle.Entity(contractBidId)
        ).withTabs(buildSignerTabs());

        List<dfsle.Recipient> recipients = new List<dfsle.Recipient>{ signer };

        if (ccUsers == null) {
            return recipients;
        }

        Set<String> seenEmails = new Set<String>{ signerEmail.toLowerCase() };
        for (User ccUser : ccUsers) {
            if (ccUser == null || String.isBlank(ccUser.Email)) {
                continue;
            }
            String emailKey = ccUser.Email.toLowerCase();
            if (seenEmails.contains(emailKey)) {
                continue;
            }
            seenEmails.add(emailKey);

            recipients.add(
                dfsle.Recipient.fromSource(
                    ccUser.Name,
                    ccUser.Email,
                    null,
                    'Carbon Copy',
                    null
                ).withType(dfsle.Recipient.TYPE_CARBON_COPY)
            );
        }

        return recipients;
    }

    @TestVisible
    private static dfsle.Envelope.Options buildEnvelopeOptions(
        Id contractBidId,
        String reminderValue,
        String daysBeforeExpires
    ) {
        return new dfsle.Envelope.Options(
            false,
            new dfsle.Document.WriteBack(
                contractBidId,
                dfsle.Document.WRITE_BACK_NAME_ENVELOPE_STATUS_PDF,
                true,
                false
            ),
            null,
            null
        );
    }

    private static String resolveDocuSignEnvelopeId(dfsle.Envelope sent, Id contractBidId) {
        return queryLatestDocuSignIdForSource(contractBidId);
    }

    private static String queryLatestDocuSignIdForSource(Id sourceRecordId) {
        List<String> objectNames = new List<String>{
            'dfsle__EnvelopeStatus__c',
            'dfsle__Envelope__c'
        };
        List<String> sourceFields = new List<String>{
            'dfsle__Source_Id__c',
            'dfsle__SourceId__c',
            'dfsle__ParentId__c',
            'dfsle__Contract_Bid__c'
        };

        for (String objectName : objectNames) {
            if (!Schema.getGlobalDescribe().containsKey(objectName)) {
                continue;
            }
            Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
                .get(objectName)
                .getDescribe()
                .fields.getMap();

            if (!fieldMap.containsKey('dfsle__DocuSignId__c'.toLowerCase())) {
                continue;
            }

            for (String sourceField : sourceFields) {
                if (!fieldMap.containsKey(sourceField.toLowerCase())) {
                    continue;
                }
                try {
                    String soql =
                        'SELECT dfsle__DocuSignId__c FROM ' +
                        objectName +
                        ' WHERE ' +
                        sourceField +
                        ' = :sourceRecordId ORDER BY CreatedDate DESC LIMIT 1';
                    List<SObject> rows = Database.query(soql);
                    if (!rows.isEmpty()) {
                        String docuSignId = (String) rows[0].get('dfsle__DocuSignId__c');
                        if (String.isNotBlank(docuSignId)) {
                            return docuSignId;
                        }
                    }
                } catch (Exception ex) {
                    System.debug(
                        LoggingLevel.FINER,
                        'DocuSign ID lookup skipped for ' + objectName + '.' + sourceField + ': ' + ex.getMessage()
                    );
                }
            }
        }

        return null;
    }

    private static Map<Id, List<User>> getAccountToUsersMap(Set<Id> accountIds) {
        Map<Id, List<User>> accountToUsersMap = new Map<Id, List<User>>();
        if (accountIds == null || accountIds.isEmpty()) {
            return accountToUsersMap;
        }

        for (Id accountId : accountIds) {
            accountToUsersMap.put(accountId, new List<User>());
        }

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

        if (activeStages.isEmpty()) {
            return accountToUsersMap;
        }

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
            WHERE Customer__c IN :accountIds
            AND Stage__c IN :activeStages
            AND (Lead_Generator__c != NULL OR Lead_Owner__c != NULL)
        ];

        for (Contract_Bid__c contract : contracts) {
            List<User> users = accountToUsersMap.get(contract.Customer__c);
            if (users == null) {
                users = new List<User>();
                accountToUsersMap.put(contract.Customer__c, users);
            }

            Set<String> existingEmails = new Set<String>();
            for (User existingUser : users) {
                if (existingUser != null && String.isNotBlank(existingUser.Email)) {
                    existingEmails.add(existingUser.Email.toLowerCase());
                }
            }

            if (contract.Lead_Generator__c != null &&
                String.isNotBlank(contract.Lead_Generator__r.Email) &&
                !existingEmails.contains(contract.Lead_Generator__r.Email.toLowerCase())
            ) {
                users.add(contract.Lead_Generator__r);
                existingEmails.add(contract.Lead_Generator__r.Email.toLowerCase());
            }

            if (contract.Lead_Owner__c != null &&
                String.isNotBlank(contract.Lead_Owner__r.Email) &&
                !existingEmails.contains(contract.Lead_Owner__r.Email.toLowerCase())
            ) {
                users.add(contract.Lead_Owner__r);
                existingEmails.add(contract.Lead_Owner__r.Email.toLowerCase());
            }
        }

        return accountToUsersMap;
    }
}
