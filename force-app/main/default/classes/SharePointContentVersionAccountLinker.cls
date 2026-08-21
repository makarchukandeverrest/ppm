/**
 * Links SharePoint-sourced ContentVersions to matching Accounts.
 * Used when Power Automate creates ContentVersion without ContentDocumentLink.
 * Runs async because ContentDocumentLink cannot be inserted in the same
 * ContentVersion after-insert transaction.
 */
public with sharing class SharePointContentVersionAccountLinker implements Queueable {

    private static final Pattern FOLDER_FROM_TITLE = Pattern.compile(
        '^(.+?)-\\d{4}-\\d{4} Bids-'
    );

    private Set<Id> versionIds;

    public SharePointContentVersionAccountLinker(Set<Id> versionIds) {
        this.versionIds = versionIds;
    }

    public static void linkToAccounts(List<ContentVersion> versions) {
        if (versions == null || versions.isEmpty()) {
            return;
        }

        Set<Id> idsToLink = new Set<Id>();
        for (ContentVersion cv : versions) {
            if (cv != null && cv.Id != null && String.isNotBlank(cv.SharePoint_External_Id__c)) {
                idsToLink.add(cv.Id);
            }
        }
        if (idsToLink.isEmpty()) {
            return;
        }

        if (System.isQueueable() || System.isFuture() || System.isBatch()) {
            linkVersions(idsToLink);
            return;
        }
        System.enqueueJob(new SharePointContentVersionAccountLinker(idsToLink));
    }

    public void execute(QueueableContext ctx) {
        if (versionIds == null || versionIds.isEmpty()) {
            return;
        }
        linkVersions(versionIds);
    }

    private static void linkVersions(Set<Id> versionIds) {
        List<ContentVersion> reloaded = [
            SELECT Id, Title, ContentDocumentId, SharePoint_External_Id__c
            FROM ContentVersion
            WHERE Id IN :versionIds
            AND SharePoint_External_Id__c != null
            AND ContentDocumentId != null
        ];
        if (reloaded.isEmpty()) {
            return;
        }

        Map<Id, String> folderByDocId = new Map<Id, String>();
        Set<String> folderNames = new Set<String>();
        for (ContentVersion cv : reloaded) {
            String folderName = extractFolderName(cv.Title);
            if (String.isBlank(folderName)) {
                continue;
            }
            folderByDocId.put(cv.ContentDocumentId, folderName);
            folderNames.add(folderName);
        }
        if (folderByDocId.isEmpty()) {
            return;
        }

        Map<Id, Set<Id>> existingAccountLinks = loadExistingAccountLinks(folderByDocId.keySet());
        Map<String, List<Account>> accountsByName = queryAccountsByFolderNames(folderNames);
        if (accountsByName.isEmpty()) {
            return;
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        Set<String> pendingKeys = new Set<String>();

        for (Id docId : folderByDocId.keySet()) {
            String folderName = folderByDocId.get(docId);
            Set<Id> alreadyLinked = existingAccountLinks.containsKey(docId)
                ? existingAccountLinks.get(docId)
                : new Set<Id>();

            for (String accountName : accountsByName.keySet()) {
                if (!namesMatch(accountName, folderName)) {
                    continue;
                }
                for (Account acc : accountsByName.get(accountName)) {
                    if (alreadyLinked.contains(acc.Id)) {
                        continue;
                    }
                    String dedupeKey = String.valueOf(docId) + ':' + String.valueOf(acc.Id);
                    if (pendingKeys.contains(dedupeKey)) {
                        continue;
                    }
                    pendingKeys.add(dedupeKey);
                    linksToInsert.add(new ContentDocumentLink(
                        ContentDocumentId = docId,
                        LinkedEntityId = acc.Id,
                        ShareType = 'V'
                    ));
                }
            }
        }

        if (linksToInsert.isEmpty()) {
            return;
        }

        Database.SaveResult[] results = Database.insert(linksToInsert, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                System.debug(
                    'Skip SharePoint account link for document ' +
                    linksToInsert[i].ContentDocumentId + ': ' +
                    results[i].getErrors()
                );
            }
        }
    }

    @TestVisible
    private static String extractFolderName(String title) {
        if (String.isBlank(title)) {
            return null;
        }
        Matcher m = FOLDER_FROM_TITLE.matcher(title);
        if (!m.find()) {
            return null;
        }
        return m.group(1);
    }

    @TestVisible
    private static Boolean namesMatch(String accountName, String folderName) {
        if (String.isBlank(accountName) || String.isBlank(folderName)) {
            return false;
        }
        String a = accountName.toLowerCase();
        String f = folderName.toLowerCase();
        return a.contains(f) || f.contains(a);
    }

    private static Map<Id, Set<Id>> loadExistingAccountLinks(Set<Id> docIds) {
        Map<Id, Set<Id>> byDoc = new Map<Id, Set<Id>>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :docIds
        ]) {
            String linked = String.valueOf(link.LinkedEntityId);
            if (!linked.startsWith('001')) {
                continue;
            }
            if (!byDoc.containsKey(link.ContentDocumentId)) {
                byDoc.put(link.ContentDocumentId, new Set<Id>());
            }
            byDoc.get(link.ContentDocumentId).add(link.LinkedEntityId);
        }
        return byDoc;
    }

    private static Map<String, List<Account>> queryAccountsByFolderNames(Set<String> folderNames) {
        List<String> likeConditions = new List<String>();
        for (String name : folderNames) {
            likeConditions.add('Name LIKE \'%' + String.escapeSingleQuotes(name) + '%\'');
        }
        String query = 'SELECT Id, Name FROM Account WHERE ' + String.join(likeConditions, ' OR ');
        List<Account> matchedAccounts = Database.query(query);

        Map<String, List<Account>> accountsByName = new Map<String, List<Account>>();
        for (Account acc : matchedAccounts) {
            if (!accountsByName.containsKey(acc.Name)) {
                accountsByName.put(acc.Name, new List<Account>());
            }
            accountsByName.get(acc.Name).add(acc);
        }
        return accountsByName;
    }
}
