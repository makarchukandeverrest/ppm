public with sharing class UnifiedActivitySelector {
    private static final Integer MAX_AGGREGATE_ITEMS = 2000;

    public List<Task> queryTasks(Set<Id> recordIds) {
        return [
            SELECT Id, Subject, Description, WhatId, WhoId, CreatedDate, CreatedById, CreatedBy.Name, Status, IsClosed, TaskSubtype
            FROM Task
            WHERE WhatId IN :recordIds OR WhoId IN :recordIds WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :MAX_AGGREGATE_ITEMS
        ];
    }

    public List<Event> queryEvents(Set<Id> recordIds) {
        return [
            SELECT Id, Subject, Description, WhatId, WhoId, CreatedDate, CreatedById, CreatedBy.Name, StartDateTime, EndDateTime
            FROM Event
            WHERE WhatId IN :recordIds OR WhoId IN :recordIds WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :MAX_AGGREGATE_ITEMS
        ];
    }

    public List<EmailMessage> queryEmailMessages(Set<Id> recordIds) {
        return [
            SELECT Id, Subject, TextBody, HtmlBody, RelatedToId, ActivityId, CreatedDate, CreatedById, CreatedBy.Name, Status
            FROM EmailMessage
            WHERE RelatedToId IN :recordIds OR ActivityId IN :recordIds WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :MAX_AGGREGATE_ITEMS
        ];
    }

    public List<FeedItem> queryFeedItemsByIds(Set<Id> feedItemIds) {
        return [
            SELECT Id, Body, Title, Type, RelatedRecordId, ParentId, CreatedDate, CreatedById, CreatedBy.Name
            FROM FeedItem
            WHERE Id IN :feedItemIds WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :MAX_AGGREGATE_ITEMS
        ];
    }

    public List<SObject> queryFeedObjectRows(String feedObjectName, Set<Id> parentIds) {
        String soql =
            'SELECT Id FROM ' + feedObjectName +
            ' WHERE ParentId IN :parentIds' +
            ' ORDER BY CreatedDate DESC' +
            ' LIMIT ' + MAX_AGGREGATE_ITEMS;
        return Database.query(soql, AccessLevel.USER_MODE);
    }

    public Map<Id, Integer> countEmailAttachments(Set<Id> emailMessageIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (emailMessageIds == null || emailMessageIds.isEmpty()) {
            return counts;
        }

        if (Schema.sObjectType.ContentDocumentLink.isAccessible()) {
            for (AggregateResult aggregateResult : [
                SELECT LinkedEntityId entityId, COUNT(Id) attachmentTotal
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :emailMessageIds WITH USER_MODE
                GROUP BY LinkedEntityId
            ]) {
                counts.put(
                    (Id) aggregateResult.get('entityId'),
                    (Integer) aggregateResult.get('attachmentTotal')
                );
            }
        }

        if (Schema.sObjectType.Attachment.isAccessible()) {
            for (AggregateResult aggregateResult : [
                SELECT ParentId parentId, COUNT(Id) attachmentTotal
                FROM Attachment
                WHERE ParentId IN :emailMessageIds WITH USER_MODE
                GROUP BY ParentId
            ]) {
                Id parentId = (Id) aggregateResult.get('parentId');
                Integer attachmentTotal = (Integer) aggregateResult.get('attachmentTotal');
                counts.put(
                    parentId,
                    (counts.containsKey(parentId) ? counts.get(parentId) : 0) + attachmentTotal
                );
            }
        }

        return counts;
    }

    public List<ContentDocumentLink> queryContentDocumentLinksByEntityIds(Set<Id> entityIds) {
        return [
            SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :entityIds WITH USER_MODE
        ];
    }

    public List<ContentVersion> queryContentVersionsByIds(Set<Id> versionIds) {
        return [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :versionIds WITH USER_MODE
        ];
    }

    public List<ContentVersion> queryContentVersionById(Id versionId) {
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionId WITH USER_MODE
            LIMIT 1
        ];
    }

    public SObject queryParentRecordById(Id recordId, List<String> selectFields, String objectName) {
        String soql =
            'SELECT ' + String.join(selectFields, ', ') +
            ' FROM ' + objectName +
            ' WHERE Id = :recordId LIMIT 1';
        List<SObject> results = Database.query(soql, AccessLevel.USER_MODE);
        return results.isEmpty() ? null : results[0];
    }
}
