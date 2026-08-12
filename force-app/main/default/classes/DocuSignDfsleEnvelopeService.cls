public with sharing class DocuSignDfsleEnvelopeService {

    private static final String ANCHOR_MAIN = 'SECTION V. ACCEPTANCE OF PROPOSAL';

    private static final String ANCHOR_OWNERS_INITIALS = 'Owner\'s Initials:';

    private static final String ENVELOPE_EMAIL_SUBJECT_PROPOSAL_LABEL = 'Premier Pool Management Proposal';

    private static final String ENVELOPE_EMAIL_WEBSITE_URL = 'https://www.premierswim.com/';
    private static final String ENVELOPE_EMAIL_SIGNATURE_TEAM = 'Premier Pool Management Team';

    private static final List<String> NEW_CUSTOMER_RESOURCE_LABELS = new List<String>{
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
        'Jessica Floyd',
        'Adrian Voicu'
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

    @TestVisible
    private static final String STAGE_CONTRACT_SENT = 'Contract Sent via DocuSign';
    private static final String STAGE_PROPOSAL_REVIEW = 'Proposal/Review';
    private static final String STAGE_CLOSED_WON = 'Closed - WON';
    private static final String STAGE_REFERENCE_ACTIVE_STAGES = 'Active_Stages';
    private static final String STATUS_EMAIL_DRAFT = '0';
    private static final String EMAIL_SUBJECT_TEMPLATE = 'Sent Contracts for {0}';
    private static final String EMAIL_TO_IDS_KEY = 'ToIds';
    @TestVisible
    private static final String ROLE_CARBON_COPY = 'Carbon Copy';
    @TestVisible
    private static final String ROLE_SECONDARY_CONTACT = 'Secondary Contact';

    public class CcRecipient {
        public String name;
        public String email;

        public CcRecipient(String name, String email) {
            this.name = name;
            this.email = email;
        }
    }

    private static CcRecipient ccRecipientFromUser(User userRecord) {
        if (userRecord == null) {
            return null;
        }
        return new CcRecipient(userRecord.Name, userRecord.Email);
    }

    public class DfsleEnvelopeSendRequest {
        public Id contractBidId;
        public Id mainContentVersionId;
        public String signerEmail;
        public String signerName;
        public Boolean isNewCustomer;
        public Id accountId;
        public CcRecipient secondaryContact;
        public List<CcRecipient> ccUsers;
        public String reminderValue;
        public String daysBeforeExpires;

        public DfsleEnvelopeSendRequest(
            Id contractBidId,
            Id mainContentVersionId,
            String signerEmail,
            String signerName,
            Boolean isNewCustomer,
            Id accountId,
            CcRecipient secondaryContact,
            List<CcRecipient> ccUsers,
            String reminderValue,
            String daysBeforeExpires
        ) {
            this.contractBidId = contractBidId;
            this.mainContentVersionId = mainContentVersionId;
            this.signerEmail = signerEmail;
            this.signerName = signerName;
            this.isNewCustomer = isNewCustomer;
            this.accountId = accountId;
            this.secondaryContact = secondaryContact;
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

        if (accountWithFilesList == null || accountWithFilesList.isEmpty()) {
            return;
        }

        EnvelopeSendContext context = new EnvelopeSendContext(accountWithFilesList);

        Map<Id, List<CcRecipient>> accountToUsersMap = getAccountToUsersMap(context.accountIds);
        Map<Id, CcRecipient> accountSecondaryContactMap = getAccountSecondaryContactCcRecipients(context.accountIds);
        List<CcRecipient> defaultCcRecipients = getDefaultCcRecipients();

        for (AccountWithFiles acc : accountWithFilesList) {
            if (acc == null || acc.files == null) continue;
            if (acc.contract == null || acc.contract.Id == null) continue;
            if (String.isBlank(acc.email) || String.isBlank(acc.accountName)) continue;

            List<CcRecipient> ccUsers = new List<CcRecipient>();
            if (accountToUsersMap.containsKey(acc.accountId)) {
                ccUsers.addAll(accountToUsersMap.get(acc.accountId));
            }
            ccUsers.addAll(defaultCcRecipients);

            CcRecipient secondaryContact = accountSecondaryContactMap.get(acc.accountId);

            for (FileWrapper file : acc.files) {
                if (file == null || file.ToSent != true || file.Id == null) continue;
                if (!context.cvById.containsKey(file.Id)) continue;

                context.sendRequests.add(new DfsleEnvelopeSendRequest(
                    acc.contract.Id,
                    file.Id,
                    acc.email,
                    acc.accountName,
                    acc.newClient == true,
                    acc.accountId,
                    secondaryContact,
                    ccUsers,
                    acc.reminderValue,
                    acc.daysBeforeExpires
                ));

                acc.contract.Stage__c = STAGE_CONTRACT_SENT;
                if (!context.contractIds.contains(acc.contract.Id)) {
                    context.contractIds.add(acc.contract.Id);
                    context.contractsToUpdate.add(acc.contract);
                }

                context.emailMessages.add(buildEmailMessage(acc, file));
            }
        }

        if (!context.sendRequests.isEmpty()) {
            Database.executeBatch(new BatchHttpSender(context.sendRequests), 1);
        }
        if (!context.emailMessages.isEmpty()) {
            System.enqueueJob(new InsertEmailMessagesJob(context.emailMessages));
        }
        if (!context.contractsToUpdate.isEmpty()) {
            update context.contractsToUpdate;
        }
    }

    private class EnvelopeSendContext {
        private Set<Id> accountIds = new Set<Id>();
        private Set<Id> mainContentVersionIds = new Set<Id>();
        private List<Contract_Bid__c> contractsToUpdate = new List<Contract_Bid__c>();
        private Set<Id> contractIds = new Set<Id>();
        private List<EmailMessage> emailMessages = new List<EmailMessage>();
        private List<DfsleEnvelopeSendRequest> sendRequests = new List<DfsleEnvelopeSendRequest>();
        private Map<Id, ContentVersion> cvById = new Map<Id, ContentVersion>();

        private EnvelopeSendContext(List<AccountWithFiles> accountWithFilesList) {
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

            if (!mainContentVersionIds.isEmpty()) {
                cvById = new Map<Id, ContentVersion>([
                    SELECT Id
                    FROM ContentVersion
                    WHERE Id IN :mainContentVersionIds
                ]);
            }
        }
    }

    private static EmailMessage buildEmailMessage(AccountWithFiles acc, FileWrapper file) {
        EmailMessage emailMessage = new EmailMessage();
        emailMessage.Status = STATUS_EMAIL_DRAFT;
        emailMessage.RelatedToId = acc.contract.Id;
        emailMessage.FromAddress = UserInfo.getUserEmail();
        emailMessage.FromName = UserInfo.getName();
        emailMessage.Subject = String.format(EMAIL_SUBJECT_TEMPLATE, new List<String>{ acc.accountName });
        emailMessage.ToIds = new List<String>{ acc.accountId };
        emailMessage.ToAddress = acc.email;
        emailMessage.TextBody = String.valueOf(file.ContentDocumentId);
        return emailMessage;
    }

    public static String sendEnvelope(
        Id contractBidId,
        Id mainContentVersionId,
        String signerEmail,
        String signerName,
        Boolean isNewCustomer,
        Id accountId,
        CcRecipient secondaryContact,
        List<CcRecipient> ccRecipients,
        String reminderValue,
        String daysBeforeExpires
    ) {
        List<Id> documentCvIds = new List<Id>{ mainContentVersionId };

        dfsle.Envelope env = dfsle.EnvelopeService.getEmptyEnvelope(
            new dfsle.Entity(contractBidId)
        );

        ContentVersion mainCv = queryMainContentVersion(mainContentVersionId);
        if (mainCv == null) {
            throw new DocuSignEnvelopeException('ContentVersion not found for Id: ' + mainContentVersionId);
        }

        String envelopeEmailSubject = buildEnvelopeEmailSubject(signerName, mainCv.Title);
        String envelopeEmailBody = resolveEnvelopeEmailBody(isNewCustomer, accountId);
        env = env.withEmail(envelopeEmailSubject, envelopeEmailBody);

        List<dfsle.Document> docs = dfsle.DocumentService.getDocuments(
            ContentVersion.SObjectType,
            new Set<Id>(documentCvIds)
        );
        env = env.withDocuments(docs);
        env = env.withRecipients(
            buildRecipients(contractBidId, signerEmail, signerName, secondaryContact, ccRecipients)
        );
        env = env.withOptions(buildEnvelopeOptions(contractBidId));
        env = env.withNotifications(buildEnvelopeNotifications(reminderValue, daysBeforeExpires));

        String envelopeId = sendOrMockEnvelope(env, mainContentVersionId, contractBidId);

        if (String.isNotBlank(envelopeId)) {
            update new ContentVersion(
                Id = mainContentVersionId,
                DocuSign_Envelope_Id__c = envelopeId.toUpperCase(),
                To_Sent__c = false
            );

            if (accountId != null && DocuSignSentPdfService.requiresSentPdfCopy(mainCv)) {
                System.enqueueJob(
                    new DocuSignSentPdfSaverJob(accountId, mainContentVersionId, envelopeId)
                );
            }
        }

        return envelopeId;
    }

    private class DocuSignEnvelopeException extends Exception {
    }

    private static ContentVersion queryMainContentVersion(Id mainContentVersionId) {
        List<ContentVersion> contentVersions = [
            SELECT Title, FileExtension
            FROM ContentVersion
            WHERE Id = :mainContentVersionId
            LIMIT 1
        ];
        return contentVersions.isEmpty() ? null : contentVersions[0];
    }

    private static String sendOrMockEnvelope(dfsle.Envelope env, Id mainContentVersionId, Id contractBidId) {
        if (Test.isRunningTest() && FORCE_RESOLVE_DOCUSIGN_ID_IN_TEST == true) {
            return resolveDocuSignEnvelopeId(null, contractBidId);
        }
        if (Test.isRunningTest()) {
            return 'TEST-DFSLE-ENVELOPE-' + mainContentVersionId;
        }
        dfsle.Envelope sent = dfsle.EnvelopeService.sendEnvelope(env, true);
        return resolveDocuSignEnvelopeId(sent, contractBidId);
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
        // OWNER column — offsets from SECTION V header (right and down)
        dfsle.Tab.Anchor mainAnchor = new dfsle.Tab.Anchor(
            ANCHOR_MAIN,
            false,
            true,
            null,
            true,
            true,
            'pixels',
            350,
            48
        );

        dfsle.Tab.Anchor mainAnchorFullName = new dfsle.Tab.Anchor(
            ANCHOR_MAIN,
            false,
            true,
            null,
            true,
            true,
            'pixels',
            325,
            72
        );

        dfsle.Tab.Anchor mainAnchorDateSigned = new dfsle.Tab.Anchor(
            ANCHOR_MAIN,
            false,
            true,
            null,
            true,
            true,
            'pixels',
            480,
            72
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

        dfsle.Tab.Anchor ownersInitialsAnchor = new dfsle.Tab.Anchor(
            ANCHOR_OWNERS_INITIALS,
            false,
            false,
            null,
            true,
            false,
            'pixels',
            75,
            15
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
                .withAnchor(initialAnchor),
            new dfsle.InitialHereTab()
                .withScale(0.6)
                .withRequired(false)
                .withAnchor(ownersInitialsAnchor)
        };
    }

    @TestVisible
    private static List<dfsle.Recipient> buildRecipients(
        Id contractBidId,
        String signerEmail,
        String signerName,
        CcRecipient secondaryContact,
        List<CcRecipient> ccRecipients
    ) {
        List<dfsle.Recipient> recipients = new List<dfsle.Recipient>();
        Set<String> seenEmails = new Set<String>();
        Integer routingOrder = 1;

        if (secondaryContact != null && String.isNotBlank(secondaryContact.email)) {
            addCarbonCopyRecipient(
                recipients,
                secondaryContact,
                ROLE_SECONDARY_CONTACT,
                seenEmails,
                routingOrder
            );
            routingOrder++;
        }

        if (String.isNotBlank(signerEmail)) {
            String signerEmailKey = signerEmail.toLowerCase();
            if (!seenEmails.contains(signerEmailKey)) {
                seenEmails.add(signerEmailKey);
                recipients.add(
                    dfsle.Recipient.fromSource(
                        signerName,
                        signerEmail,
                        null,
                        'Signer',
                        new dfsle.Entity(contractBidId)
                    )
                        .withTabs(buildSignerTabs())
                        .withRoutingOrder(routingOrder)
                );
                routingOrder++;
            }
        }

        if (ccRecipients != null) {
            for (CcRecipient ccRecipient : ccRecipients) {
                if (addCarbonCopyRecipient(
                    recipients,
                    ccRecipient,
                    ROLE_CARBON_COPY,
                    seenEmails,
                    routingOrder
                )) {
                    routingOrder++;
                }
            }
        }

        return recipients;
    }

    private static Boolean addCarbonCopyRecipient(
        List<dfsle.Recipient> recipients,
        CcRecipient ccRecipient,
        String roleName,
        Set<String> seenEmails,
        Integer routingOrder
    ) {
        if (ccRecipient == null || String.isBlank(ccRecipient.email)) {
            return false;
        }
        String emailKey = ccRecipient.email.toLowerCase();
        if (seenEmails.contains(emailKey)) {
            return false;
        }
        seenEmails.add(emailKey);

        recipients.add(
            dfsle.Recipient.fromSource(
                ccRecipient.name,
                ccRecipient.email,
                null,
                roleName,
                null
            )
                .withType(dfsle.Recipient.TYPE_CARBON_COPY)
                .withRoutingOrder(routingOrder)
        );
        return true;
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
            new Map<String, Map<String, Object>>{
                dfsle.Envelope.STATUS_COMPLETED => new Map<String, Object>{
                    'Contract_Bid__c.Stage__c' => STAGE_CLOSED_WON
                }
            },
            new Map<String, Map<String, Object>>{
                dfsle.Recipient.STATUS_DELIVERED => new Map<String, Object>{
                    'Contract_Bid__c.Stage__c' => STAGE_PROPOSAL_REVIEW
                }
            }
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

    private static List<CcRecipient> getDefaultCcRecipients() {
        try {
            List<CcRecipient> recipients = new List<CcRecipient>();
            for (User userRecord : [
                SELECT Name, Email
                FROM User
                WHERE Name IN :DEFAULT_CC_USER_NAMES
                AND IsActive = true
            ]) {
                if (String.isNotBlank(userRecord.Email)) {
                    recipients.add(ccRecipientFromUser(userRecord));
                }
            }
            return recipients;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Failed to load default CC recipients: ' + ex.getMessage());
            return new List<CcRecipient>();
        }
    }

    @TestVisible
    private static Map<Id, CcRecipient> getAccountSecondaryContactCcRecipients(Set<Id> accountIds) {
        Map<Id, CcRecipient> accountSecondaryContactMap = new Map<Id, CcRecipient>();
        if (accountIds == null || accountIds.isEmpty()) {
            return accountSecondaryContactMap;
        }

        for (Account acc : [
            SELECT
                Id,
                Secondary_Contact__r.Name,
                Secondary_Contact__r.Email,
                Secondary_Contact__r.Email__c
            FROM Account
            WHERE Id IN :accountIds
        ]) {
            Contact secondaryContact = acc.Secondary_Contact__r;
            String secondaryEmail = resolveContactEmail(secondaryContact);
            if (String.isBlank(secondaryEmail)) {
                continue;
            }

            accountSecondaryContactMap.put(
                acc.Id,
                new CcRecipient(secondaryContact.Name, secondaryEmail)
            );
        }

        return accountSecondaryContactMap;
    }

    @TestVisible
    private static String resolveContactEmail(Contact contactRecord) {
        if (contactRecord == null) {
            return null;
        }
        if (String.isNotBlank(contactRecord.Email)) {
            return contactRecord.Email;
        }
        return contactRecord.Email__c;
    }

    private static Map<Id, List<CcRecipient>> getAccountToUsersMap(Set<Id> accountIds) {
        Map<Id, List<CcRecipient>> accountToUsersMap = new Map<Id, List<CcRecipient>>();
        if (accountIds == null || accountIds.isEmpty()) {
            return accountToUsersMap;
        }

        for (Id accountId : accountIds) {
            accountToUsersMap.put(accountId, new List<CcRecipient>());
        }

        Set<String> activeStages = resolveActiveStages();

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
            List<CcRecipient> recipients = accountToUsersMap.get(contract.Customer__c);
            if (recipients == null) {
                recipients = new List<CcRecipient>();
                accountToUsersMap.put(contract.Customer__c, recipients);
            }

            Set<String> existingEmails = new Set<String>();
            for (CcRecipient existingRecipient : recipients) {
                if (existingRecipient != null && String.isNotBlank(existingRecipient.email)) {
                    existingEmails.add(existingRecipient.email.toLowerCase());
                }
            }

            addCcRecipientFromUser(recipients, contract.Lead_Generator__r, existingEmails);
            addCcRecipientFromUser(recipients, contract.Lead_Owner__r, existingEmails);
        }

        return accountToUsersMap;
    }

    private static Set<String> resolveActiveStages() {
        Set<String> activeStages = new Set<String>();

        StageReferenceSettings__mdt settings = [
            SELECT Stage_Names__c
            FROM StageReferenceSettings__mdt
            WHERE DeveloperName = :STAGE_REFERENCE_ACTIVE_STAGES
            LIMIT 1
        ];

        if (settings != null && String.isNotBlank(settings.Stage_Names__c)) {
            for (String s : settings.Stage_Names__c.split(',')) {
                activeStages.add(s.trim());
            }
        }

        return activeStages;
    }

    private static void addCcRecipientFromUser(
        List<CcRecipient> recipients,
        User userRecord,
        Set<String> existingEmails
    ) {
        if (userRecord == null || String.isBlank(userRecord.Email)) {
            return;
        }
        String emailKey = userRecord.Email.toLowerCase();
        if (existingEmails.contains(emailKey)) {
            return;
        }
        recipients.add(ccRecipientFromUser(userRecord));
        existingEmails.add(emailKey);
    }
}
