public with sharing class DocuSignSignedFileAssigner {

    public static void assignDocuments(List<EmailMessage> docuSignEmails) {

        if (docuSignEmails == null || docuSignEmails.isEmpty()) {
            return;
        }

        // 1. Collect EmailMessage Ids
        Set<Id> emailIds = new Set<Id>();
        for (EmailMessage em : docuSignEmails) {
            if (em != null && em.Id != null) {
                emailIds.add(em.Id);
            }
        }
        if (emailIds.isEmpty()) {
            return;
        }

        // 2. Files related to EmailMessage (signed DocuSign documents)
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

        // 3. Latest versions of signed files
        List<ContentVersion> signedVersions = [
            SELECT Id, ContentDocumentId, Title, FileExtension, IsLatest
            FROM ContentVersion
            WHERE ContentDocumentId IN :signedDocIds
            AND IsLatest = true
        ];
        if (signedVersions.isEmpty()) {
            return;
        }

        // 4. Collect base titles of signed files (without extension)
        Set<String> baseTitles = new Set<String>();

        for (ContentVersion cv : signedVersions) {
            if (String.isBlank(cv.Title)) {
                continue;
            }

            String title = cv.Title;
            String ext   = cv.FileExtension;

            if (!String.isBlank(ext)) {
                String suffix = '.' + ext;
                if (title.endsWith(suffix)) {
                    title = title.left(title.length() - suffix.length());
                }
            }

            baseTitles.add(title);
        }

        if (baseTitles.isEmpty()) {
            return;
        }

        // 5. Find ContentVersion with the same titles (original files on Accounts)
        List<ContentVersion> accountSideVersions = [
            SELECT Id, ContentDocumentId, Title, IsLatest
            FROM ContentVersion
            WHERE IsLatest = true
            AND Title IN :baseTitles
        ];
        if (accountSideVersions.isEmpty()) {
            return;
        }

        // 6. Collect ContentDocumentIds of these original files
        Set<Id> accountSideDocIds = new Set<Id>();
        for (ContentVersion cv : accountSideVersions) {
            accountSideDocIds.add(cv.ContentDocumentId);
        }
        if (accountSideDocIds.isEmpty()) {
            return;
        }

        // 7. Get all links for these ContentDocuments to find which are linked to Accounts
        List<ContentDocumentLink> allLinksForAccountSideDocs = [
            SELECT Id, ContentDocumentId, LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :accountSideDocIds
        ];

        // Map ContentDocumentId → AccountId
        Map<Id, Id> docIdToAccountId = new Map<Id, Id>();
        for (ContentDocumentLink cdl : allLinksForAccountSideDocs) {
            if (cdl.LinkedEntityId == null) {
                continue;
            }

            String linkedIdStr = String.valueOf(cdl.LinkedEntityId);
            // Account Ids start with '001'
            if (linkedIdStr.startsWith('001')) {
                if (!docIdToAccountId.containsKey(cdl.ContentDocumentId)) {
                    docIdToAccountId.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
                }
            }
        }
        if (docIdToAccountId.isEmpty()) {
            return;
        }

        // 8. Map baseTitle → AccountId based on original files
        Map<String, Id> baseTitleToAccountId = new Map<String, Id>();

        for (ContentVersion cv : accountSideVersions) {
            Id accId = docIdToAccountId.get(cv.ContentDocumentId);
            if (accId == null) {
                continue;
            }

            String baseTitle = cv.Title; // original title without extension
            if (!baseTitleToAccountId.containsKey(baseTitle)) {
                baseTitleToAccountId.put(baseTitle, accId);
            }
        }
        if (baseTitleToAccountId.isEmpty()) {
            return;
        }

        // 9. Update Title and create ContentDocumentLink from signed files to Accounts
        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
        List<ContentVersion>     versionsToUpdate = new List<ContentVersion>();

        for (ContentVersion signedCv : signedVersions) {

            if (String.isBlank(signedCv.Title)) {
                continue;
            }

            // Recalculate base title for signed file
            String signedBaseTitle = signedCv.Title;
            if (!String.isBlank(signedCv.FileExtension)) {
                String suffix = '.' + signedCv.FileExtension;
                if (signedBaseTitle.endsWith(suffix)) {
                    signedBaseTitle = signedBaseTitle.left(signedBaseTitle.length() - suffix.length());
                }
            }

            Id accId = baseTitleToAccountId.get(signedBaseTitle);
            if (accId == null) {
                continue;
            }

            // 9.1. Change Title: append " - Completed"
            String newTitle = signedCv.Title;
            if (!newTitle.endsWith(' - Completed')) {
                newTitle += ' - Completed';
            }

            ContentVersion cvForUpdate = new ContentVersion(
                Id    = signedCv.Id,
                Title = newTitle
            );
            versionsToUpdate.add(cvForUpdate);

            // 9.2. Link signed file to Account
            ContentDocumentLink link = new ContentDocumentLink();
            link.ContentDocumentId = signedCv.ContentDocumentId;
            link.LinkedEntityId    = accId;
            link.ShareType         = 'V';
            link.Visibility        = 'AllUsers';
            newLinks.add(link);
        }

        if (!versionsToUpdate.isEmpty()) {
            update versionsToUpdate;
        }
        if (!newLinks.isEmpty()) {
            insert newLinks;
        }
    }
}