public with sharing class DocuSignSignedFileAssigner {

    public static void assignContractDocuments(List<EmailMessage> docuSignEmails) {
        if (docuSignEmails == null || docuSignEmails.isEmpty()) {
            return;
        }

        Set<Id> emailIds = new Set<Id>();
        for (EmailMessage em : docuSignEmails) {
            if (em != null && em.Id != null) {
                emailIds.add(em.Id);
            }
        }
        if (emailIds.isEmpty()) {
            return;
        }

        // Files attached to these emails (they should already exist)
        List<ContentDocumentLink> emailLinks = [
            SELECT ContentDocumentId, LinkedEntityId
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

        List<ContentVersion> signedVersions = [
            SELECT Id, ContentDocumentId, Title, IsLatest
            FROM ContentVersion
            WHERE ContentDocumentId IN :signedDocIds
            AND IsLatest = true
        ];
        if (signedVersions.isEmpty()) {
            return;
        }

        // Base titles for signed files
        Set<String> signedBaseTitles = new Set<String>();
        Map<Id, String> signedDocIdToBaseTitle = new Map<Id, String>();
        for (ContentVersion cv : signedVersions) {
            if (String.isBlank(cv.Title)) {
                continue;
            }

            String baseTitle = normalizeTitle(cv.Title);
            if (!String.isBlank(baseTitle)) {
                signedBaseTitles.add(baseTitle);
                signedDocIdToBaseTitle.put(cv.ContentDocumentId, baseTitle);
            }
        }
        if (signedBaseTitles.isEmpty()) {
            return;
        }

        // All latest versions (to match to Account)
        List<ContentVersion> allVersions = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE IsLatest = true
            AND ContentDocumentId NOT IN :signedDocIds // exclude signed documents themselves
        ];

        Set<Id> accountSideDocIds = new Set<Id>();
        Map<Id, String> docIdToBaseTitle = new Map<Id, String>();
        for (ContentVersion cv : allVersions) {
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

        // Resolve Account via ContentDocumentLink
        List<ContentDocumentLink> allLinks = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :accountSideDocIds
        ];

        Map<Id, Id> docIdToAccountId = new Map<Id, Id>();
        Set<Id> opportunityIds = new Set<Id>();
        Map<Id, Set<Id>> oppIdToDocIds = new Map<Id, Set<Id>>();

        for (ContentDocumentLink cdl : allLinks) {
            if (cdl.LinkedEntityId == null) {
                continue;
            }

            String prefix = String.valueOf(cdl.LinkedEntityId).left(3);

            if (prefix == '001') {
                if (!docIdToAccountId.containsKey(cdl.ContentDocumentId)) {
                    docIdToAccountId.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
                }
            } else if (prefix == '006') {
                opportunityIds.add(cdl.LinkedEntityId);
                if (!oppIdToDocIds.containsKey(cdl.LinkedEntityId)) {
                    oppIdToDocIds.put(cdl.LinkedEntityId, new Set<Id>());
                }
                oppIdToDocIds.get(cdl.LinkedEntityId).add(cdl.ContentDocumentId);
            }
        }

        if (!opportunityIds.isEmpty()) {
            for (Opportunity opp : [
                SELECT Id, AccountId
                FROM Opportunity
                WHERE Id IN :opportunityIds
                AND AccountId != null
            ]) {
                for (Id docId : oppIdToDocIds.get(opp.Id)) {
                    if (!docIdToAccountId.containsKey(docId)) {
                        docIdToAccountId.put(docId, opp.AccountId);
                    }
                }
            }
        }

        // baseTitle → AccountId
        Map<String, Id> baseTitleToAccountId = new Map<String, Id>();
        for (Id docId : accountSideDocIds) {
            Id accId = docIdToAccountId.get(docId);
            String baseTitle = docIdToBaseTitle.get(docId);
            if (
                accId != null
                && !String.isBlank(baseTitle)
                && !baseTitleToAccountId.containsKey(baseTitle)
            ) {
                baseTitleToAccountId.put(baseTitle, accId);
            }
        }
        if (baseTitleToAccountId.isEmpty()) {
            return;
        }

        // Rename + Link
        List<ContentVersion> versionsToUpdate = new List<ContentVersion>();
        List<ContentDocumentLink> newCdls = new List<ContentDocumentLink>();

        for (ContentVersion cv : signedVersions) {
            String baseTitle = signedDocIdToBaseTitle.get(cv.ContentDocumentId);
            if (String.isBlank(baseTitle)) {
                continue;
            }

            Id accId = baseTitleToAccountId.get(baseTitle);
            if (accId == null) {
                continue;
            }

            // Filename without extension + suffix
            String newTitle = baseTitle + ' - Completed';
            versionsToUpdate.add(new ContentVersion(Id = cv.Id, Title = newTitle));

            newCdls.add(
                new ContentDocumentLink(
                    ContentDocumentId = cv.ContentDocumentId,
                    LinkedEntityId = accId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                )
            );
        }

        if (!versionsToUpdate.isEmpty()) {
            update versionsToUpdate;
        }

        if (!newCdls.isEmpty()) {
            Set<Id> docIds = new Set<Id>();
            Set<Id> accIds = new Set<Id>();
            for (ContentDocumentLink l : newCdls) {
                docIds.add(l.ContentDocumentId);
                accIds.add(l.LinkedEntityId);
            }

            Set<String> existingPairs = new Set<String>();
            for (ContentDocumentLink e : [
                SELECT ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink
                WHERE ContentDocumentId IN :docIds
                AND LinkedEntityId IN :accIds
            ]) {
                existingPairs.add(e.ContentDocumentId + '|' + e.LinkedEntityId);
            }

            List<ContentDocumentLink> filtered = new List<ContentDocumentLink>();
            for (ContentDocumentLink l : newCdls) {
                if (!existingPairs.contains(l.ContentDocumentId + '|' + l.LinkedEntityId)) {
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

        String result = title.trim();

        // Remove the suffix we add after signing
        String completedSuffix = ' - Completed';
        if (result.endsWithIgnoreCase(completedSuffix)) {
            result = result.left(result.length() - completedSuffix.length()).trim();
        }

        // Strip ALL .pdf extensions (including .pdf.pdf)
        while (result.endsWithIgnoreCase('.pdf')) {
            result = result.left(result.length() - 4);
        }

        // Strip any other remaining extension
        Integer dotIdx = result.lastIndexOf('.');
        if (dotIdx > 0) {
            result = result.left(dotIdx);
        }

        result = result.trim();
        return String.isBlank(result) ? null : result;
    }

    public static void assignProposalDocuments(List<EmailMessage> docuSignEmails) {
        if (docuSignEmails == null || docuSignEmails.isEmpty()) {
            return;
        }

        Set<Id> emailIds = new Set<Id>();
        for (EmailMessage em : docuSignEmails) {
            if (em != null && em.Id != null) {
                emailIds.add(em.Id);
            }
        }

        List<ContentDocumentLink> emailLinks = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :emailIds
        ];

        Set<Id> signedDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : emailLinks) {
            signedDocIds.add(cdl.ContentDocumentId);
        }

        List<ContentVersion> signedVersions = [
            SELECT Id, ContentDocumentId, Title, IsLatest
            FROM ContentVersion
            WHERE ContentDocumentId IN :signedDocIds
            AND IsLatest = true AND Title LIKE '%Premier Swim Proposal%'
        ];
        if (signedVersions.isEmpty()) {
            return;
        }

        Set<String> signedBaseTitles = new Set<String>();
        Map<Id, String> signedDocIdToBaseTitle = new Map<Id, String>();
        for (ContentVersion cv : signedVersions) {
            if (String.isBlank(cv.Title)) {
                continue;
            }

            String baseTitle = normalizeTitle(cv.Title);
            if (!String.isBlank(baseTitle)) {
                signedBaseTitles.add(baseTitle);
                signedDocIdToBaseTitle.put(cv.ContentDocumentId, baseTitle);
            }
        }
        if (signedBaseTitles.isEmpty()) {
            return;
        }

        List<ContentVersion> allAdditionalVersions = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE IsLatest = true
            AND ContentDocumentId NOT IN :signedDocIds AND Title LIKE '%Premier Swim Proposal%'
        ];

        Set<Id> oppSideDocIds = new Set<Id>();
        Map<Id, String> docIdToBaseTitle = new Map<Id, String>();
        for (ContentVersion cv : allAdditionalVersions) {
            if (String.isBlank(cv.Title)) {
                continue;
            }

            String baseTitle = normalizeTitle(cv.Title);
            if (signedBaseTitles.contains(baseTitle)) {
                oppSideDocIds.add(cv.ContentDocumentId);
                docIdToBaseTitle.put(cv.ContentDocumentId, baseTitle);
            }
        }
        if (oppSideDocIds.isEmpty()) {
            return;
        }

        List<ContentDocumentLink> allLinks = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :oppSideDocIds
        ];

        Map<String, Id> baseTitleToOpportunityId = new Map<String, Id>();
        for (ContentDocumentLink cdl : allLinks) {
            if (cdl.LinkedEntityId == null) {
                continue;
            }

            String prefix = String.valueOf(cdl.LinkedEntityId).left(3);
            if (prefix != '006') {
                continue;
            }

            String baseTitle = docIdToBaseTitle.get(cdl.ContentDocumentId);
            if (
                !String.isBlank(baseTitle)
                && !baseTitleToOpportunityId.containsKey(baseTitle)
            ) {
                baseTitleToOpportunityId.put(baseTitle, cdl.LinkedEntityId);
            }
        }
        if (baseTitleToOpportunityId.isEmpty()) {
            return;
        }

        List<ContentVersion> versionsToUpdate = new List<ContentVersion>();
        List<ContentDocumentLink> newCdls = new List<ContentDocumentLink>();

        for (ContentVersion cv : signedVersions) {
            String baseTitle = signedDocIdToBaseTitle.get(cv.ContentDocumentId);
            if (String.isBlank(baseTitle)) {
                continue;
            }

            Id oppId = baseTitleToOpportunityId.get(baseTitle);
            if (oppId == null) {
                continue;
            }

            String newTitle = baseTitle + ' - Completed';
            versionsToUpdate.add(new ContentVersion(Id = cv.Id, Title = newTitle));

            newCdls.add(
                new ContentDocumentLink(
                    ContentDocumentId = cv.ContentDocumentId,
                    LinkedEntityId = oppId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                )
            );
        }
        insert newCdls;
    }

}