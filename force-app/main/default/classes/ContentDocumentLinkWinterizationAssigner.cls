public with sharing class ContentDocumentLinkWinterizationAssigner {
    public static void assignWinterizationToCases(List<ContentDocumentLink> accountLinks) {
        if (accountLinks == null || accountLinks.isEmpty()) {
            return;
        }

        Set<Id> contentDocumentIds = new Set<Id>();
        Map<Id, Id> accountIdByDocumentId = new Map<Id, Id>();

        for (ContentDocumentLink link : accountLinks) {
            if (link.ContentDocumentId == null || link.LinkedEntityId == null) {
                continue;
            }

            contentDocumentIds.add(link.ContentDocumentId);
            accountIdByDocumentId.put(link.ContentDocumentId, link.LinkedEntityId);
        }

        if (contentDocumentIds.isEmpty()) {
            return;
        }

        Set<Id> winterizationDocumentIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();

        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
            AND IsLatest = true
        ]) {
            if (String.isBlank(cv.Title) || !cv.Title.contains('Winterization')) {
                continue;
            }

            Id accountId = accountIdByDocumentId.get(cv.ContentDocumentId);

            if (accountId == null) {
                continue;
            }

            winterizationDocumentIds.add(cv.ContentDocumentId);
            accountIds.add(accountId);
        }

        if (winterizationDocumentIds.isEmpty()) {
            return;
        }

        Map<Id, Id> openCaseIdByAccountId = new Map<Id, Id>();

        for (Case c : [
            SELECT Id, AccountId
            FROM Case
            WHERE AccountId IN :accountIds
            AND IsClosed = false
            ORDER BY CreatedDate DESC
        ]) {
            if (!openCaseIdByAccountId.containsKey(c.AccountId)) {
                openCaseIdByAccountId.put(c.AccountId, c.Id);
            }
        }

        if (openCaseIdByAccountId.isEmpty()) {
            return;
        }

        Set<String> existingKeys = new Set<String>();

        for (ContentDocumentLink existing : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :winterizationDocumentIds
            AND LinkedEntityId IN :openCaseIdByAccountId.values()
        ]) {
            existingKeys.add(String.valueOf(existing.ContentDocumentId) + ':' + String.valueOf(existing.LinkedEntityId));
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();

        for (Id documentId : winterizationDocumentIds) {
            Id accountId = accountIdByDocumentId.get(documentId);
            Id caseId = openCaseIdByAccountId.get(accountId);

            if (caseId == null) {
                continue;
            }

            String key = String.valueOf(documentId) + ':' + String.valueOf(caseId);

            if (existingKeys.contains(key)) {
                continue;
            }

            linksToInsert.add(new ContentDocumentLink(
                ContentDocumentId = documentId,
                LinkedEntityId = caseId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        if (!linksToInsert.isEmpty()) {
            insert linksToInsert;
        }
    }
}
