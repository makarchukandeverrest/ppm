public with sharing class DocuSignSignedFileAssigner {

    public static void assignDocuments(List<EmailMessage> docuSignEmails) {

        if (docuSignEmails == null || docuSignEmails.isEmpty()) {
            return;
        }

        // 1. Собираем Id email'ов
        Set<Id> emailIds = new Set<Id>();
        for (EmailMessage em : docuSignEmails) {
            if (em != null && em.Id != null) {
                emailIds.add(em.Id);
            }
        }
        if (emailIds.isEmpty()) {
            return;
        }

        // 2. Файлы, прикреплённые к EmailMessage (подписанные)
        List<ContentDocumentLink> emailLinks = [
            SELECT Id, ContentDocumentId, LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :emailIds
        ];
        if (emailLinks.isEmpty()) {
            return;
        }

        Set<Id> signedDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : emailLinks) {
            signedDocIds.add(cdl.ContentDocumentId);
        }
        if (signedDocIds.isEmpty()) {
            return;
        }

        // 3. Latest версии подписанных файлов
        List<ContentVersion> signedVersions = [
            SELECT Id, ContentDocumentId, Title, IsLatest
            FROM ContentVersion
            WHERE ContentDocumentId IN :signedDocIds
            AND IsLatest = true
        ];
        if (signedVersions.isEmpty()) {
            return;
        }

        // 4. Base titles подписанных файлов
        Set<String> signedBaseTitles = new Set<String>();
        for (ContentVersion cv : signedVersions) {
            if (String.isBlank(cv.Title)) continue;

            String baseTitle = normalizeTitle(cv.Title);
            if (!String.isBlank(baseTitle)) {
                signedBaseTitles.add(baseTitle);
            }
        }
        if (signedBaseTitles.isEmpty()) {
            return;
        }

        // 5. Берём ВСЕ latest версии (як і було)
        List<ContentVersion> accountSideVersions = [
            SELECT Id, ContentDocumentId, Title, IsLatest
            FROM ContentVersion
            WHERE IsLatest = true
        ];
        if (accountSideVersions.isEmpty()) {
            return;
        }

        // 6. Фильтрация по baseTitle
        Set<Id> accountSideDocIds = new Set<Id>();
        Map<Id, String> docIdToBaseTitle = new Map<Id, String>();

        for (ContentVersion cv : accountSideVersions) {
            if (String.isBlank(cv.Title)) continue;

            String baseTitle = normalizeTitle(cv.Title);
            if (signedBaseTitles.contains(baseTitle)) {
                accountSideDocIds.add(cv.ContentDocumentId);
                docIdToBaseTitle.put(cv.ContentDocumentId, baseTitle);
            }
        }
        if (accountSideDocIds.isEmpty()) {
            return;
        }

        // 7. Ищем Account через Account ИЛИ Opportunity
        List<ContentDocumentLink> allLinksForAccountSideDocs = [
            SELECT Id, ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :accountSideDocIds
        ];

        Map<Id, Id> docIdToAccountId = new Map<Id, Id>();
        Set<Id> opportunityIds = new Set<Id>();
        Map<Id, Set<Id>> oppIdToDocIds = new Map<Id, Set<Id>>();

        for (ContentDocumentLink cdl : allLinksForAccountSideDocs) {
            if (cdl.LinkedEntityId == null) continue;

            String linkedIdStr = String.valueOf(cdl.LinkedEntityId);

            // Account
            if (linkedIdStr.startsWith('001')) {
                if (!docIdToAccountId.containsKey(cdl.ContentDocumentId)) {
                    docIdToAccountId.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
                }

            // Opportunity
            } else if (linkedIdStr.startsWith('006')) {
                opportunityIds.add(cdl.LinkedEntityId);

                if (!oppIdToDocIds.containsKey(cdl.LinkedEntityId)) {
                    oppIdToDocIds.put(cdl.LinkedEntityId, new Set<Id>());
                }
                oppIdToDocIds.get(cdl.LinkedEntityId).add(cdl.ContentDocumentId);
            }
        }

        // Resolve Opportunity → Account
        if (!opportunityIds.isEmpty()) {
            for (Opportunity opp : [
                SELECT Id, AccountId
                FROM Opportunity
                WHERE Id IN :opportunityIds
                AND AccountId != NULL
            ]) {
                Set<Id> relatedDocIds = oppIdToDocIds.get(opp.Id);
                if (relatedDocIds == null) continue;

                for (Id docId : relatedDocIds) {
                    if (!docIdToAccountId.containsKey(docId)) {
                        docIdToAccountId.put(docId, opp.AccountId);
                    }
                }
            }
        }

        if (docIdToAccountId.isEmpty()) {
            return;
        }

        // 8. baseTitle → Account
        Map<String, Id> baseTitleToAccountId = new Map<String, Id>();

        for (Id docId : accountSideDocIds) {
            Id accId = docIdToAccountId.get(docId);
            if (accId == null) continue;

            String baseTitle = docIdToBaseTitle.get(docId);
            if (String.isBlank(baseTitle)) continue;

            if (!baseTitleToAccountId.containsKey(baseTitle)) {
                baseTitleToAccountId.put(baseTitle, accId);
            }
        }
        if (baseTitleToAccountId.isEmpty()) {
            return;
        }

        // 9. Rename + link
        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
        List<ContentVersion> versionsToUpdate = new List<ContentVersion>();

        for (ContentVersion signedCv : signedVersions) {

            if (String.isBlank(signedCv.Title)) continue;

            String signedBaseTitle = normalizeTitle(signedCv.Title);
            if (String.isBlank(signedBaseTitle)) continue;

            Id accId = baseTitleToAccountId.get(signedBaseTitle);
            if (accId == null) continue;

            // Rename
            String newTitle = signedCv.Title;
            if (!newTitle.endsWith(' - Completed')) {
                newTitle += ' - Completed';
            }

            versionsToUpdate.add(new ContentVersion(
                Id    = signedCv.Id,
                Title = newTitle
            ));

            // Link
            newLinks.add(new ContentDocumentLink(
                ContentDocumentId = signedCv.ContentDocumentId,
                LinkedEntityId    = accId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            ));
        }

        if (!versionsToUpdate.isEmpty()) {
            update versionsToUpdate;
        }

        if (!newLinks.isEmpty()) {

            Set<String> pairs = new Set<String>();
            Set<Id> docIds = new Set<Id>();
            Set<Id> accIds = new Set<Id>();

            for (ContentDocumentLink l : newLinks) {
                pairs.add(l.ContentDocumentId + '|' + l.LinkedEntityId);
                docIds.add(l.ContentDocumentId);
                accIds.add(l.LinkedEntityId);
            }

            List<ContentDocumentLink> existing = [
                SELECT ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink
                WHERE ContentDocumentId IN :docIds
                AND LinkedEntityId IN :accIds
            ];

            Set<String> existingPairs = new Set<String>();
            for (ContentDocumentLink e : existing) {
                existingPairs.add(e.ContentDocumentId + '|' + e.LinkedEntityId);
            }

            List<ContentDocumentLink> filtered = new List<ContentDocumentLink>();
            for (ContentDocumentLink l : newLinks) {
                String key = l.ContentDocumentId + '|' + l.LinkedEntityId;
                if (!existingPairs.contains(key)) {
                    filtered.add(l);
                }
            }

            if (!filtered.isEmpty()) {
                insert filtered;
            }
        }
    }

    private static String normalizeTitle(String title) {
        if (String.isBlank(title)) {
            return null;
        }
        Integer dotIdx = title.lastIndexOf('.');
        if (dotIdx > 0) {
            return title.left(dotIdx);
        }
        return title;
    }
}