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

        // 7. Линки исходных доков → родитель Account (001) или Opportunity (006)
        List<ContentDocumentLink> allLinksForAccountSideDocs = [
            SELECT Id, ContentDocumentId, LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :accountSideDocIds
        ];

        Map<Id, Id> docIdToParentId = new Map<Id, Id>();
        for (ContentDocumentLink cdl : allLinksForAccountSideDocs) {
            if (cdl.LinkedEntityId == null) {
                continue;
            }
            String linkedIdStr = String.valueOf(cdl.LinkedEntityId);
            if (linkedIdStr.startsWith('001') || linkedIdStr.startsWith('006')) {
                if (!docIdToParentId.containsKey(cdl.ContentDocumentId)) {
                    docIdToParentId.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
                }
            }
        }
        if (docIdToParentId.isEmpty()) {
            return;
        }

        // 8. baseTitle → Id того же родителя, куда был привязан исходный файл
        Map<String, Id> baseTitleToParentId = new Map<String, Id>();

        for (Id docId : accountSideDocIds) {
            Id parentId = docIdToParentId.get(docId);
            if (parentId == null) {
                continue;
            }
            String baseTitle = docIdToBaseTitle.get(docId);
            if (String.isBlank(baseTitle)) {
                continue;
            }
            if (!baseTitleToParentId.containsKey(baseTitle)) {
                baseTitleToParentId.put(baseTitle, parentId);
            }
        }
        if (baseTitleToParentId.isEmpty()) {
            return;
        }

        // 9. Переименовать подписанный файл и связать с тем же родителем (Account или Opportunity)
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

            Id parentId = baseTitleToParentId.get(signedBaseTitle);
            if (parentId == null) {
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

            // 9.2. Привязать к Account или Opportunity
            newLinks.add(new ContentDocumentLink(
                ContentDocumentId = signedCv.ContentDocumentId,
                LinkedEntityId    = parentId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            ));
        }

        if (!versionsToUpdate.isEmpty()) {
            update versionsToUpdate;
        }

        if (!newLinks.isEmpty()) {
            // Собираем пары (ContentDocumentId, LinkedEntityId), которые хотим создать
            Set<String> pairs = new Set<String>();
            for (ContentDocumentLink l : newLinks) {
                pairs.add(l.ContentDocumentId + '|' + l.LinkedEntityId);
            }

            // Уже существующие линки на те же родительские записи
            Set<Id> docIds = new Set<Id>();
            Set<Id> parentEntityIds = new Set<Id>();
            for (ContentDocumentLink l : newLinks) {
                docIds.add(l.ContentDocumentId);
                parentEntityIds.add(l.LinkedEntityId);
            }

            List<ContentDocumentLink> existing = [
                SELECT ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink
                WHERE ContentDocumentId IN :docIds
                AND LinkedEntityId IN :parentEntityIds
            ];

            Set<String> existingPairs = new Set<String>();
            for (ContentDocumentLink e : existing) {
                existingPairs.add(e.ContentDocumentId + '|' + e.LinkedEntityId);
            }

            // Оставляем только те, которых ещё нет
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