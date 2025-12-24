public with sharing class ContractMassSendController {

    private static final String LOG = '🟦 [ContractMassSend] ';

    /* =========================================================
       DTOs
    ========================================================= */

    public class TemplateDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        public TemplateDto(Id i, String n) {
            id = i;
            name = n;
        }
    }

    public class ContractDto {
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public Integer versionNumber;
        @AuraEnabled public String fileExtension;
    }

    public class CustomerDto {
        @AuraEnabled public Id customerId;
        @AuraEnabled public String customerName;
        @AuraEnabled public String customerEmail;
        @AuraEnabled public List<ContractDto> contracts;
    }

    public class LogRowDto {
        @AuraEnabled public String customerName;
        @AuraEnabled public String fileTitle;
        @AuraEnabled public Integer versionNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
    }

    public class InitResponse {
        @AuraEnabled public Boolean hasAccess;
        @AuraEnabled public String accessMessage;
        @AuraEnabled public List<TemplateDto> templates;
        @AuraEnabled public List<CustomerDto> customers;
        @AuraEnabled public List<LogRowDto> recentLogs;
    }

    /* =========================================================
       INIT (Record Page + List View)
    ========================================================= */

    @AuraEnabled(cacheable=true)
    public static InitResponse getInitData(List<Id> inputIds) {

        InitResponse res = new InitResponse();
        System.debug(LOG + 'getInitData START');
        System.debug(LOG + 'Incoming inputIds = ' + inputIds);

        /* ---------- Permission ---------- */
        if (!FeatureManagement.checkPermission('Mass_Contract_Send')) {
            res.hasAccess = false;
            res.accessMessage = 'Missing permission: Mass_Contract_Send';
            System.debug(LOG + 'EXIT: no permission');
            return res;
        }
        res.hasAccess = true;

        /* ---------- Default to empty if none provided ---------- */
        if (inputIds == null) {
            inputIds = new List<Id>();
        }

        if (inputIds.isEmpty()) {
            System.debug(LOG + 'No inputIds provided. Returning templates only.');
            res.customers = new List<CustomerDto>();
            
            // Still load templates so the user can see the UI
            res.templates = new List<TemplateDto>();
            for (EmailTemplate t : [
                SELECT Id, Name
                FROM EmailTemplate
                WHERE IsActive = true
                ORDER BY Name
                LIMIT 200
            ]) {
                res.templates.add(new TemplateDto(t.Id, t.Name));
            }
            res.recentLogs = new List<LogRowDto>();
            return res;
        }

        /* ---------- Identify ID Type ---------- */
        Set<Id> customerIds = new Set<Id>();
        
        Id firstId = inputIds[0];
        String sobjectType = firstId.getSobjectType().getDescribe().getName();
        System.debug(LOG + 'Detected SObjectType: ' + sobjectType);

        if (sobjectType == 'Account') {
            // Direct Customer IDs
            customerIds.addAll(inputIds);
        } else if (sobjectType == 'Contract_Bid__c') {
            // Resolve Customers from Contract Bids
            List<Contract_Bid__c> bids = [
                SELECT Customer__c
                FROM Contract_Bid__c
                WHERE Id IN :inputIds
            ];
            for (Contract_Bid__c cb : bids) {
                if (cb.Customer__c != null) {
                    customerIds.add(cb.Customer__c);
                }
            }
        } else {
            // Unsupported type
            System.debug(LOG + 'Unsupported SObjectType');
        }

        if (customerIds.isEmpty()) {
            res.customers = new List<CustomerDto>();
            System.debug(LOG + 'EXIT: no customers linked');
            return res;
        }

        /* ---------- Accounts ---------- */
        Map<Id, Account> accById = new Map<Id, Account>([
            SELECT Id, Name, Primary_Contact__c, Primary_Contact__r.Email
            FROM Account
            WHERE Id IN :customerIds
        ]);

        System.debug(LOG + 'Accounts loaded = ' + accById.size());

        /* ---------- Files ---------- */
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :customerIds
        ];

        Map<Id, Set<Id>> customerToDocIds = new Map<Id, Set<Id>>();
        Set<Id> docIds = new Set<Id>();

        for (ContentDocumentLink l : links) {
            docIds.add(l.ContentDocumentId);
            if (!customerToDocIds.containsKey(l.LinkedEntityId)) {
                customerToDocIds.put(l.LinkedEntityId, new Set<Id>());
            }
            customerToDocIds.get(l.LinkedEntityId).add(l.ContentDocumentId);
        }

        System.debug(LOG + 'ContentDocuments found = ' + docIds.size());

        List<ContentVersion> cvs = docIds.isEmpty()
            ? new List<ContentVersion>()
            : [
                SELECT Id, Title, ContentDocumentId, VersionNumber, FileExtension, 
                       ContentDocument.LatestPublishedVersionId, ContentDocument.LastModifiedDate
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND IsLatest = true
                AND FileExtension = 'pdf'
                AND Title LIKE '%Contract%'
                ORDER BY ContentDocument.LastModifiedDate DESC
            ];

        System.debug(LOG + 'Latest ContentVersions = ' + cvs.size());

        // Map: ContentDocumentId -> ContractDto with LastModifiedDate
        Map<Id, ContractDto> latestByDoc = new Map<Id, ContractDto>();
        Map<Id, DateTime> docLastModified = new Map<Id, DateTime>();
        
        for (ContentVersion cv : cvs) {
            ContractDto cd = new ContractDto();
            cd.contentVersionId = cv.Id;
            cd.title = cv.Title;
            cd.versionNumber = Integer.valueOf(cv.VersionNumber);
            cd.fileExtension = cv.FileExtension;
            latestByDoc.put(cv.ContentDocumentId, cd);
            docLastModified.put(cv.ContentDocumentId, cv.ContentDocument.LastModifiedDate);
        }

        /* ---------- Build Customers ---------- */
        res.customers = new List<CustomerDto>();

        for (Id custId : customerIds) {
            Account acc = accById.get(custId);
            if (acc == null) continue;

            CustomerDto dto = new CustomerDto();
            dto.customerId = acc.Id;
            dto.customerName = acc.Name;
            dto.customerEmail =
                acc.Primary_Contact__r != null
                    ? acc.Primary_Contact__r.Email
                    : null;

            dto.contracts = new List<ContractDto>();

            // Select ONLY the latest contract based on LastModifiedDate
            if (customerToDocIds.containsKey(custId)) {
                Id latestDocId = null;
                DateTime latestDate = null;
                
                for (Id docId : customerToDocIds.get(custId)) {
                    if (latestByDoc.containsKey(docId)) {
                        DateTime docDate = docLastModified.get(docId);
                        if (latestDate == null || docDate > latestDate) {
                            latestDate = docDate;
                            latestDocId = docId;
                        }
                    }
                }
                
                if (latestDocId != null) {
                    dto.contracts.add(latestByDoc.get(latestDocId));
                }
            }

            res.customers.add(dto);
        }

        /* ---------- Email Templates ---------- */
        res.templates = new List<TemplateDto>();
        for (EmailTemplate t : [
            SELECT Id, Name
            FROM EmailTemplate
            WHERE IsActive = true
            ORDER BY Name
            LIMIT 200
        ]) {
            res.templates.add(new TemplateDto(t.Id, t.Name));
        }

        res.recentLogs = new List<LogRowDto>();

        System.debug(LOG + 'Customers prepared = ' + res.customers.size());
        System.debug(LOG + 'getInitData END');

        return res;
    }

    /* =========================================================
       SEND
    ========================================================= */

    /* =========================================================
       TEMPLATE DETAILS
    ========================================================= */
    @AuraEnabled
    public static Map<String, String> getTemplateDetails(Id templateId) {
        EmailTemplate t = [
            SELECT Subject, HtmlValue, Body 
            FROM EmailTemplate 
            WHERE Id = :templateId 
            LIMIT 1
        ];
        return new Map<String, String>{
            'subject' => t.Subject,
            'body' => String.isNotBlank(t.HtmlValue) ? t.HtmlValue : t.Body
        };
    }

    /* =========================================================
       SEND
    ========================================================= */

    public class SendReqRow {
        public Id customerId;
        public List<Id> contentVersionIds;
    }

    public class SendResponse {
        @AuraEnabled public List<LogRowDto> logs;
    }

    @AuraEnabled
    public static SendResponse sendContracts(
        List<Id> inputIds,
        Id emailTemplateId,
        String requestJson,
        String subject,       // New
        String body           // New
    ) {
        System.debug(LOG + 'sendContracts START');

        if (!FeatureManagement.checkPermission('Mass_Contract_Send')) {
            throw new AuraHandledException('Missing permission: Mass_Contract_Send');
        }

        if (emailTemplateId == null && String.isBlank(body)) {
            throw new AuraHandledException('Email template or body is required.');
        }

        if (String.isBlank(requestJson)) {
            throw new AuraHandledException('Nothing to send.');
        }

        List<SendReqRow> rows =
            (List<SendReqRow>) JSON.deserialize(requestJson, List<SendReqRow>.class);

        Set<Id> customerIds = new Set<Id>();
        Set<Id> cvIds = new Set<Id>();

        for (SendReqRow r : rows) {
            customerIds.add(r.customerId);
            if (r.contentVersionIds != null) {
                cvIds.addAll(r.contentVersionIds);
            }
        }

        Map<Id, ContentVersion> cvById = new Map<Id, ContentVersion>([
            SELECT Id, Title, VersionNumber, IsLatest
            FROM ContentVersion
            WHERE Id IN :cvIds
        ]);

        for (ContentVersion cv : cvById.values()) {
            if (!cv.IsLatest) {
                throw new AuraHandledException(
                    'Only latest contract versions can be sent.'
                );
            }
        }

        Map<Id, Account> accById = new Map<Id, Account>([
            SELECT Id, Name, Primary_Contact__c, Primary_Contact__r.Email,
                   Primary_Contact__r.FirstName, Primary_Contact__r.LastName
            FROM Account
            WHERE Id IN :customerIds
        ]);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<LogRowDto> logs = new List<LogRowDto>();
        
        Map<Integer, List<LogRowDto>> emailIndexToLogs = new Map<Integer, List<LogRowDto>>();
        Integer emailIndex = 0;

        for (SendReqRow r : rows) {
            Account acc = accById.get(r.customerId);

            if (acc == null || acc.Primary_Contact__c == null) {
                LogRowDto log = new LogRowDto();
                log.customerName = acc != null ? acc.Name : 'Unknown';
                log.status = 'Failed';
                log.message = 'Primary Contact is missing.';
                logs.add(log);
                continue;
            }

            if (String.isBlank(acc.Primary_Contact__r.Email)) {
                LogRowDto log = new LogRowDto();
                log.customerName = acc.Name;
                log.status = 'Failed';
                log.message = 'Primary Contact has no email.';
                logs.add(log);
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(acc.Primary_Contact__c);
            mail.setWhatId(acc.Id);
            mail.setEntityAttachments(r.contentVersionIds);
            mail.setSaveAsActivity(true);

            // CUSTOM CONTENT LOGIC
            // If body is provided, we use it and merge fields manually.
            // Otherwise we use the templateId.
            if (String.isNotBlank(body)) {
                
                String mergedBody = body;
                String mergedSubject = String.isNotBlank(subject) ? subject : '';

                // Get Organization and User info for merge
                Organization org = [SELECT Name FROM Organization LIMIT 1];
                User currentUser = [SELECT FirstName, LastName FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

                // Merge Account fields
                mergedBody = mergedBody.replace('{!Account.Name}', (acc.Name != null ? acc.Name : ''));
                
                // Merge Contact fields
                String contactFullName = '';
                String contactFirstName = '';
                if (acc.Primary_Contact__r != null) {
                    contactFirstName = acc.Primary_Contact__r.FirstName != null ? acc.Primary_Contact__r.FirstName : '';
                    String contactLastName = acc.Primary_Contact__r.LastName != null ? acc.Primary_Contact__r.LastName : '';
                    contactFullName = (contactFirstName + ' ' + contactLastName).trim();
                }
                mergedBody = mergedBody.replace('{!Contact.Name}', contactFullName);
                mergedBody = mergedBody.replace('{!Contact.FirstName}', contactFirstName);
                
                // Merge Organization fields
                mergedBody = mergedBody.replace('{!Organization.Name}', org.Name != null ? org.Name : '');
                
                // Merge User fields
                mergedBody = mergedBody.replace('{!User.FirstName}', currentUser.FirstName != null ? currentUser.FirstName : '');
                mergedBody = mergedBody.replace('{!User.LastName}', currentUser.LastName != null ? currentUser.LastName : '');
                
                // Apply to subject as well
                mergedSubject = mergedSubject.replace('{!Account.Name}', (acc.Name != null ? acc.Name : ''));
                mergedSubject = mergedSubject.replace('{!Organization.Name}', org.Name != null ? org.Name : '');
                mergedSubject = mergedSubject.replace('{!User.FirstName}', currentUser.FirstName != null ? currentUser.FirstName : '');

                mail.setSubject(mergedSubject);
                mail.setHtmlBody(mergedBody);
            
            } else {
                mail.setTemplateId(emailTemplateId);
            }

            emails.add(mail);
            
            List<LogRowDto> currentEmailLogs = new List<LogRowDto>();
            for (Id cvId : r.contentVersionIds) {
                ContentVersion cv = cvById.get(cvId);
                LogRowDto log = new LogRowDto();
                log.customerName = acc.Name;
                log.fileTitle = cv.Title;
                log.versionNumber = Integer.valueOf(cv.VersionNumber);
                log.status = 'Sending';
                log.message = 'Email is being sent...';
                logs.add(log);
                currentEmailLogs.add(log);
            }
            emailIndexToLogs.put(emailIndex, currentEmailLogs);
            emailIndex++;
        }

        if (!emails.isEmpty()) {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);
            
            for (Integer i = 0; i < results.size(); i++) {
                Messaging.SendEmailResult result = results[i];
                List<LogRowDto> emailLogs = emailIndexToLogs.get(i);
                
                if (emailLogs != null) {
                    for (LogRowDto log : emailLogs) {
                        if (result.isSuccess()) {
                            log.status = 'Sent';
                            log.message = 'Email sent successfully.';
                        } else {
                            log.status = 'Failed';
                            String errorMsg = 'Unknown error';
                            if (result.getErrors() != null && result.getErrors().size() > 0) {
                                errorMsg = result.getErrors()[0].getMessage();
                            }
                            log.message = errorMsg;
                        }
                    }
                }
            }
        }

        SendResponse resp = new SendResponse();
        resp.logs = logs;
        return resp;
    }
}