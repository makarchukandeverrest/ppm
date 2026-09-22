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
        Set<Id> relatedIds = expandEmailRelatedIds(recordIds);
        Set<Id> emailIds = queryEmailMessageIds(relatedIds);
        if (emailIds.isEmpty()) {
            return new List<EmailMessage>();
        }
        return [
            SELECT Id, Subject, TextBody, HtmlBody, RelatedToId, ActivityId, CreatedDate, CreatedById, CreatedBy.Name, FromName, FromAddress, Status
            FROM EmailMessage
            WHERE Id IN :emailIds WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :MAX_AGGREGATE_ITEMS
        ];
    }

    private Set<Id> expandEmailRelatedIds(Set<Id> recordIds) {
        Set<Id> relatedIds = new Set<Id>();
        if (recordIds == null || recordIds.isEmpty()) {
            return relatedIds;
        }
        relatedIds.addAll(recordIds);
        relatedIds.addAll(queryContactIdsForAccounts(relatedIds));
        return relatedIds;
    }

    private Set<Id> queryContactIdsForAccounts(Set<Id> recordIds) {
        Set<Id> accountIds = new Set<Id>();
        for (Id recordId : recordIds) {
            if (recordId != null && recordId.getSObjectType() == Account.SObjectType) {
                accountIds.add(recordId);
            }
        }
        if (accountIds.isEmpty() || !Schema.sObjectType.Contact.isAccessible()) {
            return new Set<Id>();
        }

        Set<Id> contactIds = new Set<Id>();
        for (Contact contactRecord : [
            SELECT Id
            FROM Contact
            WHERE AccountId IN :accountIds WITH USER_MODE
            LIMIT :MAX_AGGREGATE_ITEMS
        ]) {
            contactIds.add(contactRecord.Id);
        }
        return contactIds;
    }

    private Set<Id> queryEmailMessageIds(Set<Id> relatedIds) {
        Set<Id> emailIds = new Set<Id>();
        if (relatedIds == null || relatedIds.isEmpty()) {
            return emailIds;
        }

        for (EmailMessage emailMessage : [
            SELECT Id
            FROM EmailMessage
            WHERE RelatedToId IN :relatedIds OR ActivityId IN :relatedIds WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :MAX_AGGREGATE_ITEMS
        ]) {
            emailIds.add(emailMessage.Id);
        }

        if (Schema.sObjectType.EmailMessageRelation.isAccessible()) {
            for (AggregateResult aggregateResult : [
                SELECT EmailMessageId emailId
                FROM EmailMessageRelation
                WHERE RelationId IN :relatedIds WITH USER_MODE
                GROUP BY EmailMessageId
                LIMIT :MAX_AGGREGATE_ITEMS
            ]) {
                Id emailId = (Id) aggregateResult.get('emailId');
                if (emailId != null) {
                    emailIds.add(emailId);
                }
            }
        }
        return emailIds;
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