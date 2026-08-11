public with sharing class UnifiedActivityService {
    private final UnifiedActivitySelector selector;
    private final UnifiedActivityMapper mapper;

    public UnifiedActivityService() {
        this(new UnifiedActivitySelector(), new UnifiedActivityMapper());
    }

    public UnifiedActivityService(UnifiedActivitySelector selector, UnifiedActivityMapper mapper) {
        this.selector = selector;
        this.mapper = mapper;
    }

    public UnifiedActivityModels.ActivityPageResult getUnifiedActivities(
        Id recordId,
        String sortDirection,
        Integer pageSize,
        Integer offset,
        String activityType,
        String searchTerm,
        String relatedRecordConfig,
        String currentRecordLabel
    ) {
        if (recordId == null) {
            throw new UnifiedActivityException('recordId is required');
        }

        UnifiedActivityModels.SortDirection direction = UnifiedActivityUtils.parseSortDirection(sortDirection);
        Integer safePageSize = UnifiedActivityUtils.normalizePageSize(pageSize);
        Integer safeOffset = offset == null || offset < 0 ? 0 : offset;
        Map<Id, String> recordLabels = resolveActivityRecordIds(recordId, relatedRecordConfig, currentRecordLabel);

        List<UnifiedActivityModels.ActivityItem> items = new List<UnifiedActivityModels.ActivityItem>();
        Set<Id> recordIds = recordLabels.keySet();
        items.addAll(mapper.mapTasks(selector.queryTasks(recordIds), recordLabels));
        items.addAll(mapper.mapEvents(selector.queryEvents(recordIds), recordLabels));
        items.addAll(mapper.mapEmailMessages(selector.queryEmailMessages(recordIds), recordLabels));
        items.addAll(mapper.mapFeedItems(queryFeedItems(recordLabels), recordLabels));

        UnifiedActivityUtils.sortItems(items, direction);
        List<UnifiedActivityModels.ActivityItem> filteredItems = UnifiedActivityUtils.applyFilters(items, activityType, searchTerm);
        return UnifiedActivityUtils.paginate(filteredItems, safePageSize, safeOffset);
    }

    private Map<Id, String> resolveActivityRecordIds(
        Id recordId,
        String relatedRecordConfig,
        String currentRecordLabel
    ) {
        Map<Id, String> recordLabels = new Map<Id, String>();
        Schema.SObjectType sObjectType = recordId.getSObjectType();
        String objectLabel = String.isNotBlank(currentRecordLabel)
            ? currentRecordLabel.trim()
            : sObjectType.getDescribe().getLabel();
        recordLabels.put(recordId, objectLabel);

        if (String.isBlank(relatedRecordConfig)) {
            return recordLabels;
        }

        Map<String, String> fieldToLabel = parseRelatedRecordConfig(relatedRecordConfig);
        if (fieldToLabel.isEmpty()) {
            return recordLabels;
        }

        Set<String> validFields = filterValidLookupFields(sObjectType, fieldToLabel.keySet());
        if (validFields.isEmpty()) {
            return recordLabels;
        }

        List<String> selectFields = new List<String>{ 'Id' };
        selectFields.addAll(validFields);
        SObject parentRecord = selector.queryParentRecordById(
            recordId,
            selectFields,
            sObjectType.getDescribe().getName()
        );
        if (parentRecord == null) {
            return recordLabels;
        }

        for (String fieldName : validFields) {
            Id relatedRecordId = (Id) parentRecord.get(fieldName);
            if (relatedRecordId != null && !recordLabels.containsKey(relatedRecordId)) {
                recordLabels.put(relatedRecordId, fieldToLabel.get(fieldName));
            }
        }

        return recordLabels;
    }

    private Map<String, String> parseRelatedRecordConfig(String relatedRecordConfig) {
        Map<String, String> fieldToLabel = new Map<String, String>();
        for (String entry : relatedRecordConfig.split(',')) {
            String trimmedEntry = entry != null ? entry.trim() : null;
            if (String.isBlank(trimmedEntry)) {
                continue;
            }

            List<String> parts = trimmedEntry.split(':');
            String fieldName = parts[0].trim();
            if (String.isBlank(fieldName)) {
                continue;
            }

            String label = parts.size() > 1 && String.isNotBlank(parts[1])
                ? parts[1].trim()
                : UnifiedActivityUtils.formatFieldLabel(fieldName);
            fieldToLabel.put(fieldName, label);
        }
        return fieldToLabel;
    }

    private Set<String> filterValidLookupFields(Schema.SObjectType sObjectType, Set<String> fieldNames) {
        Set<String> validFields = new Set<String>();
        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();

        for (String fieldName : fieldNames) {
            if (!fieldMap.containsKey(fieldName)) {
                continue;
            }
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE && fieldDescribe.isAccessible()) {
                validFields.add(fieldName);
            }
        }
        return validFields;
    }

    private List<FeedItem> queryFeedItems(Map<Id, String> recordLabels) {
        Set<Id> recordIds = recordLabels.keySet();
        if (recordIds.isEmpty() || !Schema.sObjectType.FeedItem.isAccessible()) {
            return new List<FeedItem>();
        }
        return queryFeedItemsByParentIds(recordIds);
    }

    private List<FeedItem> queryFeedItemsByParentIds(Set<Id> recordIds) {
        Map<String, Set<Id>> parentIdsByFeedObject = new Map<String, Set<Id>>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        for (Id parentId : recordIds) {
            String feedObjectName = resolveFeedObjectName(parentId.getSObjectType());
            if (String.isBlank(feedObjectName) || !globalDescribe.containsKey(feedObjectName)) {
                continue;
            }
            if (!parentIdsByFeedObject.containsKey(feedObjectName)) {
                parentIdsByFeedObject.put(feedObjectName, new Set<Id>());
            }
            parentIdsByFeedObject.get(feedObjectName).add(parentId);
        }

        Set<Id> feedItemIds = new Set<Id>();
        for (String feedObjectName : parentIdsByFeedObject.keySet()) {
            Set<Id> parentIds = parentIdsByFeedObject.get(feedObjectName);
            for (SObject row : selector.queryFeedObjectRows(feedObjectName, parentIds)) {
                feedItemIds.add((Id) row.get('Id'));
            }
        }

        if (feedItemIds.isEmpty()) {
            return new List<FeedItem>();
        }

        return selector.queryFeedItemsByIds(feedItemIds);
    }

    private String resolveFeedObjectName(Schema.SObjectType sObjectType) {
        if (sObjectType == null) {
            return null;
        }
        String objectName = sObjectType.getDescribe().getName();
        if (objectName == 'User') {
            return 'UserProfileFeed';
        }
        if (objectName.endsWith('__c')) {
            return objectName.removeEnd('__c') + '__Feed';
        }
        return objectName + 'Feed';
    }
}
