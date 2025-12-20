public with sharing class DocuSignNotificationService {

    public static void handleEnvelopeStatusChange(List<ContentVersion> newVersions) {

        System.debug('=== DocuSignNotificationService START ===');

        if (newVersions == null || newVersions.isEmpty()) {
            System.debug('EXIT: No ContentVersions');
            return;
        }

        Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;

        List<Task> tasksToInsert = new List<Task>();
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        // -------------------------------------------------
        // 1️⃣ Resolve REAL ContentVersions by EnvelopeId
        // -------------------------------------------------
        Set<String> envelopeIds = new Set<String>();
        for (ContentVersion cv : newVersions) {
            if (String.isNotBlank(cv.DocuSign_Envelope_Id__c)) {
                envelopeIds.add(cv.DocuSign_Envelope_Id__c);
            }
        }

        if (envelopeIds.isEmpty()) {
            System.debug('EXIT: No EnvelopeIds');
            return;
        }

        List<ContentVersion> realVersions = [
            SELECT Id, ContentDocumentId, Title, DocuSign_Envelope_Status__c, DocuSign_Envelope_Id__c
            FROM ContentVersion
            WHERE DocuSign_Envelope_Id__c IN :envelopeIds
            ORDER BY CreatedDate DESC
        ];

        // -------------------------------------------------
// 1.5 Collect ContentDocumentIds from REAL versions
// -------------------------------------------------
Set<Id> contentDocIds = new Set<Id>();
for (ContentVersion cv : realVersions) {
    if (cv.ContentDocumentId != null) {
        contentDocIds.add(cv.ContentDocumentId);
    }
}

if (contentDocIds.isEmpty()) {
    System.debug('EXIT: No ContentDocumentIds');
    return;
}

        if (realVersions.isEmpty()) {
            System.debug('EXIT: No real ContentVersions found');
            return;
        }

        // -------------------------
        // 2. Read ContentDocumentLinks
        // -------------------------
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :contentDocIds
        ];

        Map<Id, Id> contentDocToAccount = new Map<Id, Id>();
        Map<Id, Id> contentDocToEmail   = new Map<Id, Id>();
        Set<Id> accountIds = new Set<Id>();

        for (ContentDocumentLink l : links) {
            String prefix = String.valueOf(l.LinkedEntityId).substring(0, 3);

            if (prefix == '001') { // Account
                contentDocToAccount.put(l.ContentDocumentId, l.LinkedEntityId);
                accountIds.add(l.LinkedEntityId);
            }
            else if (prefix == '02s') { // EmailMessage
                contentDocToEmail.put(l.ContentDocumentId, l.LinkedEntityId);
            }
        }

        System.debug('Direct Account links found: ' + accountIds);
        System.debug('EmailMessage links found: ' + contentDocToEmail);

        // -------------------------
        // 3. Resolve Account via EmailMessage → Contract_Bid__c
        // -------------------------
        if (accountIds.isEmpty() && !contentDocToEmail.isEmpty()) {

            List<EmailMessage> emails = [
                SELECT Id, RelatedToId
                FROM EmailMessage
                WHERE Id IN :contentDocToEmail.values()
            ];

            Set<Id> contractIds = new Set<Id>();
            for (EmailMessage em : emails) {
                if (em.RelatedToId != null &&
                    String.valueOf(em.RelatedToId).startsWith('a0b')) {
                    contractIds.add(em.RelatedToId);
                }
            }

            System.debug('Resolved Contract_Bid__c IDs from EmailMessage: ' + contractIds);

            if (!contractIds.isEmpty()) {
                List<Contract_Bid__c> bidsFromEmail = [
                    SELECT Id, Customer__c
                    FROM Contract_Bid__c
                    WHERE Id IN :contractIds
                ];

                for (Contract_Bid__c b : bidsFromEmail) {
                    if (b.Customer__c != null) {
                        accountIds.add(b.Customer__c);
                    }
                }
            }
        }

        System.debug('Final AccountIds to process: ' + accountIds);

        if (accountIds.isEmpty()) {
    System.debug('⚠️ Fallback: trying to resolve Account via Contract_Bid__c');

    List<Contract_Bid__c> recentBids = [
        SELECT Id, Customer__c
        FROM Contract_Bid__c
        WHERE CreatedById = :UserInfo.getUserId()
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];

    if (!recentBids.isEmpty()) {
        accountIds.add(recentBids[0].Customer__c);
        System.debug('✅ Fallback Account resolved: ' + recentBids[0].Customer__c);
    }
}

        // -------------------------
        // 4. Load Active Stages
        // -------------------------
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

        System.debug('Active Stages: ' + activeStages);

        if (activeStages.isEmpty()) {
            System.debug('EXIT: No active stages');
            return;
        }

        // -------------------------
        // 5. Load Contract Bids
        // -------------------------
        List<Contract_Bid__c> bids = [
            SELECT Id, Name, Customer__c,
                   Record_Manager__c,
                   Record_Manager__r.Email,
                   Stage__c
            FROM Contract_Bid__c
            WHERE Customer__c IN :accountIds
            AND Stage__c IN :activeStages
        ];

        Map<Id, Contract_Bid__c> accountToBid = new Map<Id, Contract_Bid__c>();
        for (Contract_Bid__c b : bids) {
            accountToBid.put(b.Customer__c, b);
        }

        System.debug('Resolved Contract Bids: ' + accountToBid.keySet());

        // -------------------------
        // 6. Create Tasks + Emails
        // -------------------------
        for (ContentVersion cv : realVersions) {

            Id accId = contentDocToAccount.get(cv.ContentDocumentId);

            if (accId == null) {
                accId = accountIds.isEmpty() ? null : accountIds.iterator().next();
            }

            if (accId == null || !accountToBid.containsKey(accId)) {
                System.debug('SKIP CV ' + cv.Id + ' — no Account / Bid');
                continue;
            }

            Contract_Bid__c bid = accountToBid.get(accId);
            String status = cv.DocuSign_Envelope_Status__c;

            System.debug('Processing CV ' + cv.Id + ' for Bid ' + bid.Id);

            // Email (PROD only)
            if (!isSandbox && String.isNotBlank(bid.Record_Manager__r.Email)) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new String[]{ bid.Record_Manager__r.Email });
                mail.setSubject(
                    'DocuSign Envelope for Contract Bid "' + bid.Name + '" changed status to ' + status
                );
                mail.setPlainTextBody(
                    'Hello,\n\n' +
                    'The DocuSign envelope has changed status to "' + status + '".\n\n' +
                    'Document: ' + cv.Title + '\n' +
                    'Completed Date: ' + System.now() + '\n\n' +
                    'Best regards,\nSalesforce System'
                );
                emailsToSend.add(mail);
            }

            // Task
            if (bid.Record_Manager__c != null) {
                Task t = new Task();
                t.OwnerId = bid.Record_Manager__c;
                t.WhatId  = bid.Id;
                t.Subject = 'DocuSign Envelope status changed to ' + status;
                t.Description =
                    'DocuSign envelope for "' + bid.Name +
                    '" changed status to "' + status + '"';
                t.Status = 'Completed';
                t.Priority = 'Normal';
                t.ActivityDate = Date.today();

                tasksToInsert.add(t);

                System.debug('TASK prepared for Bid ' + bid.Id);
            }
        }

        // -------------------------
        // 7. Persist
        // -------------------------
        if (!emailsToSend.isEmpty() && !isSandbox) {
            Messaging.sendEmail(emailsToSend);
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
            System.debug('TASKS INSERTED: ' + tasksToInsert.size());
        } else {
            System.debug('NO TASKS TO INSERT');
        }

        System.debug('=== DocuSignNotificationService END ===');
    }
}