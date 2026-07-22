public with sharing class DocuSignDfsleEnvelopeService {

    private static final String ANCHOR_MAIN =
        'Please initial page(s) 2, 3, 4 and 5 of this contract where indicated. ';

    private static final String ENVELOPE_EMAIL_SUBJECT_PROPOSAL_LABEL = 'Premier Pool Management Proposal';

    private static final String ENVELOPE_EMAIL_WEBSITE_URL = 'https://www.premierswim.com/';
    private static final String ENVELOPE_EMAIL_SIGNATURE_TEAM = 'Premier Pool Management Team';

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

    private static final Set<String> DEFAULT_CC_USER_NAMES = new Set<String>{
        'Roman Shestakov',
        'Stephanie Pratt',
        'Jessica Floyd'
    };

    private static final List<String> ENVELOPE_EMAIL_BODY_BULLETS = new List<String>{
        'Spring Start-up (inspection, repairs, health department inspection and permits)',
        'American Red Cross certified lifeguards and pool operators fully trained to your property\'s specific needs',
        'General liability insurance with a $10,000,000 limit',
        'ALL pool chemicals are included',
        'A minimum of 3 weekly visits by our supervisory staff',
        'Our management and service teams are available and On-call 24/7',
        'A timely and thorough winterization of your facility with ALL winterization chemicals included'
    };

    public class DfsleEnvelopeSendRequest {
        public Id contractBidId;
        public Id mainContentVersionId;
        public String signerEmail;
        public String signerName;
        public Boolean isNewCustomer;
        public Id accountId;
        public List<User> ccUsers;
        public String reminderValue;
        public String daysBeforeExpires;

        public DfsleEnvelopeSendRequest(
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
            this.contractBidId = contractBidId;
            this.mainContentVersionId = mainContentVersionId;
            this.signerEmail = signerEmail;
            this.signerName = signerName;
            this.isNewCustomer = isNewCustomer;
            this.accountId = accountId;
            this.ccUsers = ccUsers;
            this.reminderValue = reminderValue;
            this.daysBeforeExpires = daysBeforeExpires;
        }
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
        List<DfsleEnvelopeSendRequest> sendRequests = new List<DfsleEnvelopeSendRequest>();

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

        List<User> defaultCcUsers = getDefaultCcUsers();

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

            List<User> ccUsers = new List<User>();
            if (accountToUsersMap.containsKey(acc.accountId)) {
                ccUsers.addAll(accountToUsersMap.get(acc.accountId));
            }
            ccUsers.addAll(defaultCcUsers);

            for (FileWrapper file : acc.files) {
                if (file == null || file.ToSent != true || file.Id == null) continue;
                if (!cvById.containsKey(file.Id)) continue;

                sendRequests.add(new DfsleEnvelopeSendRequest(
                    acc.contract.Id,
                    file.Id,
                    acc.email,
                    acc.accountName,
                    acc.newClient == true,
                    acc.accountId,
                    ccUsers,
                    acc.reminderValue,
                    acc.daysBeforeExpires
                ));

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

        if (!sendRequests.isEmpty()) {
            Database.executeBatch(new BatchHttpSender(sendRequests), 1);
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
        List<Id> documentCvIds = new List<Id>{ mainContentVersionId };

        dfsle.Envelope env = dfsle.EnvelopeService.getEmptyEnvelope(
            new dfsle.Entity(contractBidId)
        );

        ContentVersion mainCv = [
            SELECT Title
            FROM ContentVersion
            WHERE Id = :mainContentVersionId
            LIMIT 1
        ];

        String envelopeEmailSubject = buildEnvelopeEmailSubject(signerName, mainCv.Title);
        String envelopeEmailBody = resolveEnvelopeEmailBody(isNewCustomer, accountId);
        env = env.withEmail(envelopeEmailSubject, envelopeEmailBody);

        List<dfsle.Document> docs = dfsle.DocumentService.getDocuments(
            ContentVersion.SObjectType,
            new Set<Id>(documentCvIds)
        );
        env = env.withDocuments(docs);
        env = env.withRecipients(
            buildRecipients(contractBidId, signerEmail, signerName, ccUsers)
        );
        env = env.withOptions(buildEnvelopeOptions(contractBidId));
        env = env.withNotifications(buildEnvelopeNotifications(reminderValue, daysBeforeExpires));

        String envelopeId;
        if (Test.isRunningTest() && FORCE_RESOLVE_DOCUSIGN_ID_IN_TEST == true) {
            envelopeId = resolveDocuSignEnvelopeId(null, contractBidId);
        } else if (Test.isRunningTest()) {
            envelopeId = 'TEST-DFSLE-ENVELOPE-' + mainContentVersionId;
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
    private static String buildEnvelopeEmailSubject(String accountName, String contractFileTitle) {
        String proposalLabel = ENVELOPE_EMAIL_SUBJECT_PROPOSAL_LABEL;
        String safeAccountName = String.isBlank(accountName) ? '' : accountName.trim();
        String secondYear = extractSecondContractYear(contractFileTitle);

        if (String.isNotBlank(secondYear)) {
            return secondYear + ' ' + proposalLabel + ' - ' + safeAccountName;
        }
        return proposalLabel + ' - ' + safeAccountName;
    }

    @TestVisible
    private static String extractSecondContractYear(String contractFileTitle) {
        if (String.isBlank(contractFileTitle)) {
            return null;
        }

        Matcher yearRangeMatcher = Pattern.compile('(\\d{4})-(\\d{4})').matcher(contractFileTitle);
        if (yearRangeMatcher.find()) {
            return yearRangeMatcher.group(2);
        }
        return null;
    }

    @TestVisible
    private static String resolveEnvelopeEmailBody(Boolean isNewCustomer, Id accountId) {
        if (isNewCustomer == true) {
            return buildContractEmailBodyHtml(resolveContactFirstName(accountId));
        }

        return buildProposalEmailBodyHtml(resolveContactFirstName(accountId));
    }

    @TestVisible
    private static String buildEnvelopeEmailBody(Boolean isNewCustomer, Id accountId) {
        return resolveEnvelopeEmailBody(isNewCustomer, accountId);
    }

    @TestVisible
    private static String resolveContactFirstName(Id accountId) {
        if (accountId == null) {
            return null;
        }

        List<Account> accounts = [
            SELECT Primary_Contact__r.FirstName
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (accounts.isEmpty() || accounts[0].Primary_Contact__r == null) {
            return null;
        }
        return accounts[0].Primary_Contact__r.FirstName;
    }

    private static String buildProposalEmailBodyHtml(String contactFirstName) {
        List<String> parts = new List<String>();

        String greeting = String.isNotBlank(contactFirstName)
            ? 'Hi ' + escapeHtmlText(contactFirstName) + ','
            : 'Hi,';
        parts.add('<p>' + greeting + '</p>');

        parts.add(
            '<p>' +
            escapeHtmlText(
                'Please review the attached pool management proposal and let us know if you have any questions or would like to discuss any aspect of the agreement.'
            ) +
            '</p>'
        );

        parts.add(
            '<p>' +
            escapeHtmlText(
                'Thank you for your time and consideration. We appreciate the opportunity and look forward to the possibility of working with you.'
            ) +
            '</p>'
        );

        parts.add(
            '<p>' +
            'Best regards,<br/><br/>' +
            escapeHtmlText(ENVELOPE_EMAIL_SIGNATURE_TEAM) +
            '</p>'
        );
        parts.add(
            '<p>Check out our website: <a href="' +
            escapeHtmlAttribute(ENVELOPE_EMAIL_WEBSITE_URL) +
            '">' +
            escapeHtmlText(ENVELOPE_EMAIL_WEBSITE_URL) +
            '</a></p>'
        );

        return String.join(parts, '');
    }

    private static String buildContractEmailBodyHtml(String contactFirstName) {
        List<String> parts = new List<String>();

        String greeting = String.isNotBlank(contactFirstName)
            ? 'Hello ' + escapeHtmlText(contactFirstName) + ','
            : 'Hello,';
        parts.add('<p>' + greeting + '</p>');

        parts.add(
            '<p>' +
            escapeHtmlText(
                'Thank you for considering our pool management proposal. I\'m attaching the contract, along with our welcome letter, general references, recommendation letters and a copy of our certificate of insurance. Please review everything and see how we compare to the competition and let me know if we can schedule a time to discuss how we can be of service to you in the future.'
            ) +
            '</p>'
        );

        parts.add(
            '<p>' +
            escapeHtmlText('Our "turn-key" pool management contract includes:') +
            '</p>'
        );

        List<String> bulletItems = new List<String>();
        for (String bullet : ENVELOPE_EMAIL_BODY_BULLETS) {
            bulletItems.add('<li>' + escapeHtmlText(bullet) + '</li>');
        }
        parts.add('<ul>' + String.join(bulletItems, '') + '</ul>');

        parts.add(
            '<p>' +
            escapeHtmlText(
                'We have years of experience in providing excellent pool management services with a long list of references to back it up. In addition to our reliable service, we also offer very competitive prices along with great discounts for new and existing customers.'
            ) +
            '</p>'
        );

        parts.add(
            '<p>' +
            escapeHtmlText(
                'Please let us know if there is anything else that we can do to earn your business.'
            ) +
            '</p>'
        );

        String resourceLinksHtml = buildEnvelopeResourceLinksHtml();
        if (String.isNotBlank(resourceLinksHtml)) {
            parts.add(
                '<p>' + escapeHtmlText('Additional reference documents:') + '</p>' + resourceLinksHtml
            );
        }

        parts.add(
            '<p>' +
            'Best Regards,<br/><br/>' +
            escapeHtmlText(ENVELOPE_EMAIL_SIGNATURE_TEAM) +
            '</p>'
        );
        parts.add(
            '<p>Check out our website: <a href="' +
            escapeHtmlAttribute(ENVELOPE_EMAIL_WEBSITE_URL) +
            '">' +
            escapeHtmlText(ENVELOPE_EMAIL_WEBSITE_URL) +
            '</a></p>'
        );

        return String.join(parts, '');
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
    private static dfsle.Envelope.Options buildEnvelopeOptions(Id contractBidId) {
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

    @TestVisible
    private static dfsle.Notifications buildEnvelopeNotifications(
        String reminderValue,
        String daysBeforeExpires
    ) {
        Integer expireAfterDays = parsePositiveDays(daysBeforeExpires, 120);
        Integer expireWarnDays = expireAfterDays > 10 ? 10 : Math.max(1, expireAfterDays - 1);
        Boolean remindEnabled = String.isNotBlank(reminderValue);
        Integer reminderDays = remindEnabled ? parsePositiveDays(reminderValue, 1) : 1;

        return new dfsle.Notifications(
            remindEnabled,
            reminderDays,
            reminderDays,
            true,
            expireAfterDays,
            expireWarnDays,
            false
        );
    }

    @TestVisible
    private static Integer parsePositiveDays(String value, Integer defaultValue) {
        if (String.isBlank(value)) {
            return defaultValue;
        }
        try {
            Integer days = Integer.valueOf(value.trim());
            return days >= 1 ? days : defaultValue;
        } catch (Exception ex) {
            return defaultValue;
        }
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

    private static List<User> getDefaultCcUsers() {
        try {
            return [
                SELECT Id, Name, Email
                FROM User
                WHERE Name IN :DEFAULT_CC_USER_NAMES
                AND IsActive = true
            ];
        } catch (Exception ex) {
            return new List<User>();
        }
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