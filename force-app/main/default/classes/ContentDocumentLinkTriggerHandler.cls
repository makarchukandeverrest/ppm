public with sharing class ContentDocumentLinkTriggerHandler {

    public static void handleAfterInsert(List<ContentDocumentLink> newLinks) {
        if (newLinks == null || newLinks.isEmpty()) return;

        // 1. Збираємо LinkedEntityId — шукаємо EmailMessage
        Set<Id> linkedEntityIds = new Set<Id>();
        for (ContentDocumentLink cdl : newLinks) {
            if (cdl.LinkedEntityId != null) {
                linkedEntityIds.add(cdl.LinkedEntityId);
            }
        }

        // 2. Фільтруємо тільки EmailMessage від DocuSign
        List<EmailMessage> docuSignEmails = [
            SELECT Id, Subject, FromAddress, TextBody, Headers
            FROM EmailMessage
            WHERE Id IN :linkedEntityIds
            AND FromAddress LIKE '%docusign%'
            AND (Subject LIKE 'Completed:%' OR Subject LIKE 'Signed:%')
        ];

        if (docuSignEmails.isEmpty()) return;

        // 3. Передаємо в існуючий асайнер
        DocuSignSignedFileAssigner.assignDocuments(docuSignEmails);
    }
}