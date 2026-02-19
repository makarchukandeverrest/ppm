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

        // 2. Находим файлы, прикреплённые к этим EmailMessage (подписанные DocuSign)
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

        // 3. Берём последние версии подписанных файлов
        List<ContentVersion> signedVersions = [
            SELECT Id, ContentDocumentId, Title, IsLatest
            FROM ContentVersion
            WHERE ContentDocumentId IN :signedDocIds
            AND IsLatest = true
        ];
        if (signedVersions.isEmpty()) {
            return;
        }

        // 4. Собираем baseTitles для подписанных файлов (Title без расширения)
        Set<String> signedBaseTitles = new Set<String>();

        for (ContentVersion cv : signedVersions) {
            if (String.isBlank(cv.Title)) {
                continue;
            }
            String baseTitle = normalizeTitle(cv.Title);
            if (!String.isBlank(baseTitle)) {
                signedBaseTitles.add(baseTitle);
            }
        }
        if (signedBaseTitles.isEmpty()) {
            return;
        }

        // 5. Ищем исходные файлы (latest) по тем же baseTitles
        //    Здесь сравниваем уже нормализованный Title (без расширения)
        List<ContentVersion> accountSideVersions = [
            SELECT Id, ContentDocumentId, Title, IsLatest
            FROM ContentVersion
            WHERE IsLatest = true
        ];
        if (accountSideVersions.isEmpty()) {
            return;
        }

        // 6. Фильтруем accountSideVersions в Apex по baseTitle
        //    И собираем ContentDocumentId этих файлов
        Set<Id> accountSideDocIds = new Set<Id>();
        Map<Id, String> docIdToBaseTitle = new Map<Id, String>();

        for (ContentVersion cv : accountSideVersions) {
            if (String.isBlank(cv.Title)) {
                continue;
            }
            String baseTitle = normalizeTitle(cv.Title);
            if (signedBaseTitles.contains(baseTitle)) {
                accountSideDocIds.add(cv.ContentDocumentId);
                docIdToBaseTitle.put(cv.ContentDocumentId, baseTitle);
            }
        }
        if (accountSideDocIds.isEmpty()) {
            return;
        }

        // 7. Линки этих доков, чтобы найти Account
        List<ContentDocumentLink> allLinksForAccountSideDocs = [
            SELECT Id, ContentDocumentId, LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :accountSideDocIds
        ];

        Map<Id, Id> docIdToAccountId = new Map<Id, Id>();
        for (ContentDocumentLink cdl : allLinksForAccountSideDocs) {
            if (cdl.LinkedEntityId == null) {
                continue;
            }
            String linkedIdStr = String.valueOf(cdl.LinkedEntityId);
            if (linkedIdStr.startsWith('001')) {
                if (!docIdToAccountId.containsKey(cdl.ContentDocumentId)) {
                    docIdToAccountId.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
                }
            }
        }
        if (docIdToAccountId.isEmpty()) {
            return;
        }

        // 8. baseTitle -> AccountId
        Map<String, Id> baseTitleToAccountId = new Map<String, Id>();

        for (Id docId : accountSideDocIds) {
            Id accId = docIdToAccountId.get(docId);
            if (accId == null) {
                continue;
            }
            String baseTitle = docIdToBaseTitle.get(docId);
            if (String.isBlank(baseTitle)) {
                continue;
            }
            if (!baseTitleToAccountId.containsKey(baseTitle)) {
                baseTitleToAccountId.put(baseTitle, accId);
            }
        }
        if (baseTitleToAccountId.isEmpty()) {
            return;
        }

        // 9. Переименовываем подписанные и линкуем к Account
        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
        List<ContentVersion> versionsToUpdate = new List<ContentVersion>();

        for (ContentVersion signedCv : signedVersions) {

            if (String.isBlank(signedCv.Title)) {
                continue;
            }

            String signedBaseTitle = normalizeTitle(signedCv.Title);
            if (String.isBlank(signedBaseTitle)) {
                continue;
            }

            Id accId = baseTitleToAccountId.get(signedBaseTitle);
            if (accId == null) {
                continue;
            }

            // 9.1. Переименовать
            String newTitle = signedCv.Title;
            if (!newTitle.endsWith(' - Completed')) {
                newTitle += ' - Completed';
            }

            versionsToUpdate.add(new ContentVersion(
                Id    = signedCv.Id,
                Title = newTitle
            ));

            // 9.2. Линкануть к Account
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
            insert newLinks;
        }
    }

    // Вспомогательный метод: обрезает расширение по последней точке
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
