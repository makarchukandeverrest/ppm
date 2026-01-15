public with sharing class DocuSignNotificationService {
    
    public static void handleEnvelopeStatusChange(List<ContentVersion> newVersions) {

        // Detect sandbox safely
        Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;

        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        List<Task> tasksToInsert = new List<Task>();

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
            SELECT Id, ContentDocumentId, Title, DocuSign_Envelope_Status__c, DocuSign_Envelope_Id__c,
                   VersionNumber, CreatedDate, FirstPublishLocationId
            FROM ContentVersion
            WHERE DocuSign_Envelope_Id__c IN :envelopeIds
            ORDER BY CreatedDate DESC
        ];
        
        System.debug('🔍 Found ' + realVersions.size() + ' ContentVersions with EnvelopeIds: ' + envelopeIds);
        
        // Log all versions found
        for(ContentVersion cv : realVersions) {
            System.debug('   ContentVersion ID: ' + cv.Id);
            System.debug('      Title: ' + cv.Title);
            System.debug('      ContentDocumentId: ' + cv.ContentDocumentId);
            System.debug('      VersionNumber: ' + cv.VersionNumber);
            System.debug('      CreatedDate: ' + cv.CreatedDate);
            System.debug('      FirstPublishLocationId: ' + cv.FirstPublishLocationId);
            System.debug('      DocuSign_Envelope_Status__c: ' + cv.DocuSign_Envelope_Status__c);
        }
        
        // Check if multiple versions exist (DocuSign may have created new one)
        if(realVersions.size() > 1) {
            System.debug('⚠️ MULTIPLE ContentVersions found for same EnvelopeId!');
            System.debug('   Latest version: ' + realVersions[0].Id + ' (Created: ' + realVersions[0].CreatedDate + ')');
            System.debug('   Older versions: ' + (realVersions.size() - 1));
        }

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

        // Find Accounts via ContentDocumentLink
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :contentDocIds
        ];

        Map<Id, Id> contentDocToAccount = new Map<Id, Id>();
        Set<Id> accountIds = new Set<Id>();

        for(ContentDocumentLink l : links){
            if(String.valueOf(l.LinkedEntityId).startsWith('001')){
                contentDocToAccount.put(l.ContentDocumentId, l.LinkedEntityId);
                accountIds.add(l.LinkedEntityId);
            }
        }

        if(accountIds.isEmpty()) return;

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

        if(settings != null && String.isNotBlank(settings.Stage_Names__c)){
            for(String s : settings.Stage_Names__c.split(',')){
                activeStages.add(s.trim());
            }
        }

        if(activeStages.isEmpty())
            return;

        // Find Contract Bids with active stages
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
        for(Contract_Bid__c b : bids){
            accountToBid.put(b.Customer__c, b);
        }

        // Generate Tasks + Emails
        for(ContentVersion cv : newVersions){

            Id accId = contentDocToAccount.get(cv.ContentDocumentId);
            if(accId == null || !accountToBid.containsKey(accId)) continue;

            Contract_Bid__c bid = accountToBid.get(accId);
            String status = cv.DocuSign_Envelope_Status__c;

            // Email (only PROD)
            if(!isSandbox && String.isNotBlank(bid.Record_Manager__r.Email)){
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new String[]{ bid.Record_Manager__r.Email });
                mail.setSubject('DocuSign Envelope for Contract Bid "' + bid.Name +
                                '" changed status to ' + status);
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
			if(bid.Record_Manager__r != null){
                Task t = new Task();
                t.OwnerId = bid.Record_Manager__c;
                t.WhatId = bid.Id;
                t.Subject = 'DocuSign Envelope status changed to ' + status;
                t.Description =
                    'DocuSign envelope for "' + bid.Name +
                    '" changed status to "' + status + '"';
                t.Status = 'Completed';
                t.Priority = 'Normal';
                t.ActivityDate = Date.today();
    
                tasksToInsert.add(t);
			}
        }

        // Send Emails (PROD only)
        if(!emailsToSend.isEmpty() && !isSandbox){
            Messaging.sendEmail(emailsToSend);
        }

        // Insert Tasks
        if(!tasksToInsert.isEmpty()){
            insert tasksToInsert;
        }
    }
}