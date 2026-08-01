public with sharing class UnifiedActivityController {

    public static final String TYPE_TASK = 'Task';
    public static final String TYPE_EVENT = 'Event';
    public static final String TYPE_EMAIL = 'EmailMessage';
    public static final String TYPE_FEED = 'FeedItem';

    public enum SortDirection { ASCENDING, DESCENDING }

    public class ActivityContentPart {
        @AuraEnabled public String partType;
        @AuraEnabled public String text;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String altText;
    }

    public class ActivityPageResult {
        @AuraEnabled public List<ActivityItem> items;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Integer nextOffset;
    }

    public class ActivityItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String type;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public List<ActivityContentPart> contentParts;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String createdById;
        @AuraEnabled public String createdByName;
        @AuraEnabled public String status;
        @AuraEnabled public String iconName;
        @AuraEnabled public String formattedType;
        @AuraEnabled public String sourceLabel;
        @AuraEnabled public Integer attachmentCount;

        public ActivityItem(
            Id id,
            String type,
            String title,
            String description,
            Datetime createdDate,
            Id createdById,
            String createdByName,
            String status
        ) {
            this(id, type, title, description, createdDate, createdById, createdByName, status, null, null);
        }

        public ActivityItem(
            Id id,
            String type,
            String title,
            String description,
            Datetime createdDate,
            Id createdById,
            String createdByName,
            String status,
            List<ActivityContentPart> contentParts
        ) {
            this(id, type, title, description, createdDate, createdById, createdByName, status, contentParts, null);
        }

        public ActivityItem(
            Id id,
            String type,
            String title,
            String description,
            Datetime createdDate,
            Id createdById,
            String createdByName,
            String status,
            List<ActivityContentPart> contentParts,
            String sourceLabel
        ) {
            this.id = id;
            this.type = type;
            this.title = title;
            this.description = description;
            this.contentParts = contentParts != null ? contentParts : new List<ActivityContentPart>();
            this.createdDate = createdDate;
            this.createdById = createdById;
            this.createdByName = createdByName;
            this.status = status;
            this.sourceLabel = sourceLabel;
            this.attachmentCount = 0;
            this.iconName = iconNameFor(type);
            this.formattedType = formattedTypeFor(type);
        }
    }

    private static final Integer DEFAULT_PAGE_SIZE = 20;
    private static final Integer MAX_AGGREGATE_ITEMS = 2000;

    @AuraEnabled
    public static ActivityPageResult getUnifiedActivities(
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
            throw new IllegalArgumentException('recordId is required');
        }

        SortDirection direction = parseSortDirection(sortDirection);
        Integer safePageSize = normalizePageSize(pageSize);
        Integer safeOffset = offset == null || offset < 0 ? 0 : offset;
        Map<Id, String> recordLabels = resolveActivityRecordIds(recordId, relatedRecordConfig, currentRecordLabel);

        List<ActivityItem> items = new List<ActivityItem>();
        items.addAll(getTasks(recordLabels));
        items.addAll(getEvents(recordLabels));
        items.addAll(getEmailMessages(recordLabels));
        items.addAll(getFeedItems(recordLabels));

        sortItems(items, direction);
        List<ActivityItem> filteredItems = applyFilters(items, activityType, searchTerm);
        return paginate(filteredItems, safePageSize, safeOffset);
    }

    private static Map<Id, String> resolveActivityRecordIds(
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
        String query =
            'SELECT ' + String.join(selectFields, ', ') +
            ' FROM ' + sObjectType.getDescribe().getName() +
            ' WHERE Id = :recordId LIMIT 1';
        SObject parentRecord = Database.query(query);

        for (String fieldName : validFields) {
            Id relatedRecordId = (Id) parentRecord.get(fieldName);
            if (relatedRecordId != null && !recordLabels.containsKey(relatedRecordId)) {
                recordLabels.put(relatedRecordId, fieldToLabel.get(fieldName));
            }
        }

        return recordLabels;
    }

    private static Map<String, String> parseRelatedRecordConfig(String relatedRecordConfig) {
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
                : formatFieldLabel(fieldName);
            fieldToLabel.put(fieldName, label);
        }
        return fieldToLabel;
    }

    private static Set<String> filterValidLookupFields(Schema.SObjectType sObjectType, Set<String> fieldNames) {
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

    private static String formatFieldLabel(String fieldName) {
        if (fieldName.endsWith('__c')) {
            return fieldName.removeEnd('__c').replace('_', ' ');
        }
        if (fieldName.endsWith('Id')) {
            return fieldName.removeEnd('Id');
        }
        return fieldName;
    }

    private static String resolveSourceLabel(Id primaryId, Id secondaryId, Map<Id, String> recordLabels) {
        if (primaryId != null && recordLabels.containsKey(primaryId)) {
            return recordLabels.get(primaryId);
        }
        if (secondaryId != null && recordLabels.containsKey(secondaryId)) {
            return recordLabels.get(secondaryId);
        }
        return null;
    }

    @AuraEnabled
    public static void createChatterPost(Id recordId, String body, List<String> imageContentVersionIds) {
        if (recordId == null) {
            throw new IllegalArgumentException('recordId is required');
        }
        if (isBlankRichText(body)) {
            throw new IllegalArgumentException('body is required');
        }
        if (!Schema.sObjectType.FeedItem.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create Chatter posts');
        }

        String trimmedBody = body.trim();
        if (containsInlineHtmlImage(trimmedBody)) {
            createChatterPostWithConnectApi(recordId, trimmedBody, imageContentVersionIds);
            return;
        }

        FeedItem feedItem = new FeedItem();
        feedItem.ParentId = recordId;
        feedItem.Body = trimmedBody;
        feedItem.IsRichText = true;
        insert feedItem;
    }

    private static void createChatterPostWithConnectApi(
        Id recordId,
        String htmlBody,
        List<String> imageContentVersionIds
    ) {
        ConnectApi.FeedItemInput input = new ConnectApi.FeedItemInput();
        input.subjectId = recordId;
        input.feedElementType = ConnectApi.FeedElementType.FeedItem;

        ConnectApi.MessageBodyInput messageBody = new ConnectApi.MessageBodyInput();
        messageBody.messageSegments = buildConnectApiSegmentsFromRichTextHtml(
            htmlBody,
            imageContentVersionIds
        );
        if (messageBody.messageSegments.isEmpty()) {
            throw new IllegalArgumentException('body is required');
        }

        input.body = messageBody;
        ConnectApi.ChatterFeeds.postFeedElement(null, input);
    }

    private static Boolean containsInlineHtmlImage(String body) {
        return String.isNotBlank(body) && body.toLowerCase().contains('<img');
    }

    private static List<ConnectApi.MessageSegmentInput> buildConnectApiSegmentsFromRichTextHtml(
        String html,
        List<String> imageContentVersionIds
    ) {
        List<ConnectApi.MessageSegmentInput> segments = new List<ConnectApi.MessageSegmentInput>();

        Pattern imgPattern = Pattern.compile('(?i)<img[^>]+src="([^"]+)"[^>]*>');
        Matcher matcher = imgPattern.matcher(html);
        Integer lastEnd = 0;
        Integer imageIndex = 0;

        while (matcher.find()) {
            appendTextSegmentFromHtml(segments, html.substring(lastEnd, matcher.start()));

            String imageUrl = unescapeHtmlAttribute(matcher.group(1));
            Id contentDocumentId = resolveInlineImageContentDocumentId(
                imageUrl,
                imageContentVersionIds,
                imageIndex
            );
            imageIndex++;

            if (contentDocumentId == null) {
                throw new AuraHandledException(
                    'Could not attach the uploaded image to the Chatter post. Wait for the image upload to finish, then try again.'
                );
            }

            ConnectApi.InlineImageSegmentInput imageSegment = new ConnectApi.InlineImageSegmentInput();
            imageSegment.altText = 'Image';
            imageSegment.fileId = contentDocumentId;
            segments.add(imageSegment);
            lastEnd = matcher.end();
        }

        if (lastEnd == 0) {
            Matcher singleQuoteMatcher = Pattern.compile('(?i)<img[^>]+src=\'([^\']+)\'[^>]*>').matcher(html);
            lastEnd = 0;
            imageIndex = 0;
            segments.clear();

            while (singleQuoteMatcher.find()) {
                appendTextSegmentFromHtml(segments, html.substring(lastEnd, singleQuoteMatcher.start()));

                String imageUrl = unescapeHtmlAttribute(singleQuoteMatcher.group(1));
                Id contentDocumentId = resolveInlineImageContentDocumentId(
                    imageUrl,
                    imageContentVersionIds,
                    imageIndex
                );
                imageIndex++;

                if (contentDocumentId == null) {
                    throw new AuraHandledException(
                        'Could not attach the uploaded image to the Chatter post. Wait for the image upload to finish, then try again.'
                    );
                }

                ConnectApi.InlineImageSegmentInput imageSegment = new ConnectApi.InlineImageSegmentInput();
                imageSegment.altText = 'Image';
                imageSegment.fileId = contentDocumentId;
                segments.add(imageSegment);
                lastEnd = singleQuoteMatcher.end();
            }
        }

        appendTextSegmentFromHtml(segments, html.substring(lastEnd));
        return segments;
    }

    private static Id resolveInlineImageContentDocumentId(
        String imageUrl,
        List<String> imageContentVersionIds,
        Integer imageIndex
    ) {
        if (imageContentVersionIds != null
            && imageIndex < imageContentVersionIds.size()
            && String.isNotBlank(imageContentVersionIds[imageIndex])) {
            Id fromVersionId = resolveContentDocumentIdFromVersionId(imageContentVersionIds[imageIndex]);
            if (fromVersionId != null) {
                return fromVersionId;
            }
        }

        return resolveContentDocumentIdFromImageUrl(imageUrl);
    }

    private static Id resolveContentDocumentIdFromVersionId(String versionIdValue) {
        if (String.isBlank(versionIdValue)) {
            return null;
        }

        String versionKey = versionIdValue.trim();
        if (versionKey.length() == 15 || versionKey.length() == 18) {
            try {
                Id versionId = (Id) versionKey;
                if (String.valueOf(versionId).startsWith('069')) {
                    return versionId;
                }
            } catch (Exception ex) {
                // Not a valid Salesforce Id.
            }
        }

        List<ContentVersion> versions = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionKey
            LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0].ContentDocumentId;
    }

    private static Id resolveContentDocumentIdFromImageUrl(String imageUrl) {
        if (String.isBlank(imageUrl)) {
            return null;
        }

        String normalizedUrl = unescapeHtmlAttribute(imageUrl);

        Id contentDocumentId = extractContentDocumentIdFromImageUrl(normalizedUrl);
        if (contentDocumentId != null) {
            return contentDocumentId;
        }

        String versionId = extractVersionIdFromImageUrl(normalizedUrl);
        if (String.isNotBlank(versionId)) {
            return resolveContentDocumentIdFromVersionId(versionId);
        }

        Matcher idMatcher = Pattern.compile('(?:refid|id)=([a-zA-Z0-9]{15,18})').matcher(normalizedUrl);
        if (idMatcher.find()) {
            return resolveContentDocumentIdFromVersionId(idMatcher.group(1));
        }

        return null;
    }

    private static void appendTextSegmentFromHtml(
        List<ConnectApi.MessageSegmentInput> segments,
        String htmlFragment
    ) {
        String plainText = stripHtmlToPlainText(htmlFragment);
        if (String.isBlank(plainText)) {
            return;
        }

        ConnectApi.TextSegmentInput textSegment = new ConnectApi.TextSegmentInput();
        textSegment.text = plainText;
        segments.add(textSegment);
    }

    private static String stripHtmlToPlainText(String htmlFragment) {
        if (String.isBlank(htmlFragment)) {
            return '';
        }

        String text = htmlFragment.replaceAll('<br\\s*/?>', '\n');
        text = text.replaceAll('</p\\s*>', '\n');
        text = text.replaceAll('<[^>]+>', '');
        text = unescapeHtmlAttribute(text);
        text = text.replace('\u00a0', ' ').trim();
        return text;
    }

    private static String unescapeHtmlAttribute(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        String amp = String.fromCharArray(new List<Integer>{ 38 });
        value = value.replace(amp + 'amp;', amp);
        value = value.replace(amp + 'quot;', '"');
        value = value.replace(amp + '#39;', String.fromCharArray(new List<Integer>{ 39 }));
        value = value.replace(amp + 'lt;', '<');
        value = value.replace(amp + 'gt;', '>');
        return value;
    }

    private static Boolean isBlankRichText(String body) {
        if (String.isBlank(body)) {
            return true;
        }
        String stripped = body.replaceAll('<[^>]+>', '');
        stripped = stripped.replace('&nbsp;', ' ').trim();
        return String.isBlank(stripped);
    }

    private static Boolean isRichTextBody(String body) {
        return String.isNotBlank(body) && body.contains('<') && body.contains('>');
    }

    private static List<ActivityItem> getTasks(Map<Id, String> recordLabels) {
        Set<Id> recordIds = recordLabels.keySet();
        List<ActivityItem> result = new List<ActivityItem>();
        for (Task t : [
            SELECT Id, Subject, Description, WhatId, WhoId, CreatedDate, CreatedById, CreatedBy.Name, Status, IsClosed, TaskSubtype
            FROM Task
            WHERE WhatId IN :recordIds OR WhoId IN :recordIds
            ORDER BY CreatedDate DESC
            LIMIT :MAX_AGGREGATE_ITEMS
        ]) {
            if (isEmailLikeTask(t)) {
                continue;
            }
            result.add(new ActivityItem(
                t.Id,
                TYPE_TASK,
                t.Subject,
                t.Description,
                t.CreatedDate,
                t.CreatedById,
                t.CreatedBy?.Name,
                t.Status,
                null,
                resolveSourceLabel(t.WhatId, t.WhoId, recordLabels)
            ));
        }
        return result;
    }

    private static Boolean isEmailLikeTask(Task taskRecord) {
        if (taskRecord.TaskSubtype == 'Email' || taskRecord.TaskSubtype == 'ListEmail') {
            return true;
        }
        if (String.isBlank(taskRecord.Description)) {
            return false;
        }
        String description = taskRecord.Description;
        return description.contains('To:')
            && description.contains('Subject:');
    }

    private static List<ActivityItem> getEvents(Map<Id, String> recordLabels) {
        Set<Id> recordIds = recordLabels.keySet();
        List<ActivityItem> result = new List<ActivityItem>();
        for (Event e : [
            SELECT Id, Subject, Description, WhatId, WhoId, CreatedDate, CreatedById, CreatedBy.Name, StartDateTime, EndDateTime
            FROM Event
            WHERE WhatId IN :recordIds OR WhoId IN :recordIds
            ORDER BY CreatedDate DESC
            LIMIT :MAX_AGGREGATE_ITEMS
        ]) {
            result.add(new ActivityItem(
                e.Id,
                TYPE_EVENT,
                e.Subject,
                e.Description,
                e.CreatedDate,
                e.CreatedById,
                e.CreatedBy?.Name,
                null,
                null,
                resolveSourceLabel(e.WhatId, e.WhoId, recordLabels)
            ));
        }
        return result;
    }

    private static List<ActivityItem> getEmailMessages(Map<Id, String> recordLabels) {
        Set<Id> recordIds = recordLabels.keySet();
        List<ActivityItem> result = new List<ActivityItem>();
        List<EmailMessage> emailMessages = [
            SELECT Id, Subject, TextBody, HtmlBody, RelatedToId, ActivityId, CreatedDate, CreatedById, CreatedBy.Name, Status
            FROM EmailMessage
            WHERE RelatedToId IN :recordIds OR ActivityId IN :recordIds
            ORDER BY CreatedDate DESC
            LIMIT :MAX_AGGREGATE_ITEMS
        ];
        Map<Id, Integer> attachmentCounts = countEmailAttachments(
            new Map<Id, EmailMessage>(emailMessages).keySet()
        );

        for (EmailMessage em : emailMessages) {
            String body = resolveEmailBody(em);
            ActivityItem item = new ActivityItem(
                em.Id,
                TYPE_EMAIL,
                em.Subject,
                body,
                em.CreatedDate,
                em.CreatedById,
                em.CreatedBy?.Name,
                em.Status,
                null,
                resolveSourceLabel(em.RelatedToId, em.ActivityId, recordLabels)
            );
            item.attachmentCount = attachmentCounts.containsKey(em.Id)
                ? attachmentCounts.get(em.Id)
                : 0;
            result.add(item);
        }
        return result;
    }

    private static Map<Id, Integer> countEmailAttachments(Set<Id> emailMessageIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (emailMessageIds == null || emailMessageIds.isEmpty()) {
            return counts;
        }

        if (Schema.sObjectType.ContentDocumentLink.isAccessible()) {
            for (AggregateResult aggregateResult : [
                SELECT LinkedEntityId entityId, COUNT(Id) attachmentTotal
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :emailMessageIds
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
                WHERE ParentId IN :emailMessageIds
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

    private static List<ActivityItem> getFeedItems(Map<Id, String> recordLabels) {
        Set<Id> recordIds = recordLabels.keySet();
        List<ActivityItem> result = new List<ActivityItem>();
        if (!Schema.sObjectType.FeedItem.isAccessible()) {
            return result;
        }
        List<FeedItem> feedItems = [
            SELECT Id, Body, Title, Type, RelatedRecordId, ParentId, CreatedDate, CreatedById, CreatedBy.Name
            FROM FeedItem
            WHERE ParentId IN :recordIds
            ORDER BY CreatedDate DESC
            LIMIT :MAX_AGGREGATE_ITEMS
        ];
        for (FeedItem fi : feedItems) {
            List<ActivityContentPart> contentParts = buildFeedItemContentParts(fi);
            result.add(new ActivityItem(
                fi.Id,
                TYPE_FEED,
                buildFeedItemTitle(fi),
                buildPlainTextFromParts(contentParts, fi.Body),
                fi.CreatedDate,
                fi.CreatedById,
                fi.CreatedBy?.Name,
                null,
                contentParts,
                recordLabels.get(fi.ParentId)
            ));
        }
        return result;
    }

    private static String buildPlainTextFromParts(List<ActivityContentPart> parts, String fallback) {
        if (parts == null || parts.isEmpty()) {
            return fallback;
        }
        List<String> values = new List<String>();
        for (ActivityContentPart part : parts) {
            if (part.partType == 'text' && String.isNotBlank(part.text)) {
                values.add(part.text);
            } else if (part.partType == 'image' && String.isNotBlank(part.altText)) {
                values.add(part.altText);
            }
        }
        return values.isEmpty() ? fallback : String.join(values, ' ');
    }

    private static List<ActivityContentPart> buildFeedItemContentParts(FeedItem fi) {
        if (fi.Type == 'ContentPost' && fi.RelatedRecordId != null) {
            return new List<ActivityContentPart>{
                buildImagePart(
                    fi.RelatedRecordId,
                    '/sfc/servlet.shepherd/document/download/' + fi.RelatedRecordId,
                    fi.Title
                )
            };
        }
        if (containsInlineImageReference(fi.Body) || fi.Type == 'ContentPost') {
            List<ActivityContentPart> parts = buildFeedContentPartsFromConnectApi(fi.Id);
            if (!parts.isEmpty()) {
                return parts;
            }
        }
        if (String.isNotBlank(fi.Body)) {
            ActivityContentPart textPart = new ActivityContentPart();
            textPart.partType = 'text';
            textPart.text = isRichTextBody(fi.Body) ? fi.Body : escapeHtml(fi.Body);
            return new List<ActivityContentPart>{ textPart };
        }
        return new List<ActivityContentPart>();
    }

    private static ActivityContentPart buildImagePart(Id contentDocumentId, String imageUrl, String altText) {
        ActivityContentPart part = new ActivityContentPart();
        part.partType = 'image';
        part.contentDocumentId = contentDocumentId;
        part.imageUrl = imageUrl;
        part.altText = String.isNotBlank(altText) ? altText : 'Attachment';
        return part;
    }

    private static List<ActivityContentPart> buildFeedContentPartsFromConnectApi(Id feedItemId) {
        try {
            ConnectApi.FeedElement element = ConnectApi.ChatterFeeds.getFeedElement(null, feedItemId);
            if (!(element instanceof ConnectApi.FeedItem)) {
                return new List<ActivityContentPart>();
            }

            ConnectApi.FeedItem feedItem = (ConnectApi.FeedItem) element;
            if (feedItem.body == null || feedItem.body.messageSegments == null) {
                return new List<ActivityContentPart>();
            }

            List<ActivityContentPart> parts = new List<ActivityContentPart>();
            List<String> versionIds = new List<String>();
            List<Integer> imagePartIndexes = new List<Integer>();

            for (ConnectApi.MessageSegment segment : feedItem.body.messageSegments) {
                if (segment instanceof ConnectApi.TextSegment) {
                    ActivityContentPart textPart = new ActivityContentPart();
                    textPart.partType = 'text';
                    textPart.text = escapeHtml(((ConnectApi.TextSegment) segment).text);
                    parts.add(textPart);
                } else if (segment instanceof ConnectApi.InlineImageSegment) {
                    ConnectApi.InlineImageSegment imageSegment = (ConnectApi.InlineImageSegment) segment;
                    ActivityContentPart imagePart = new ActivityContentPart();
                    imagePart.partType = 'image';
                    imagePart.imageUrl = imageSegment.url;
                    imagePart.altText = String.isNotBlank(imageSegment.altText) ? imageSegment.altText : 'Image';
                    parts.add(imagePart);
                    imagePartIndexes.add(parts.size() - 1);
                    String versionId = extractVersionIdFromImageUrl(imageSegment.url);
                    if (String.isNotBlank(versionId)) {
                        versionIds.add(versionId);
                    }
                } else if (segment instanceof ConnectApi.MentionSegment) {
                    ConnectApi.MentionSegment mentionSegment = (ConnectApi.MentionSegment) segment;
                    ActivityContentPart mentionPart = new ActivityContentPart();
                    mentionPart.partType = 'text';
                    mentionPart.text = '<strong>@' + escapeHtml(mentionSegment.name) + '</strong>';
                    parts.add(mentionPart);
                } else if (segment instanceof ConnectApi.HashtagSegment) {
                    ConnectApi.HashtagSegment hashtagSegment = (ConnectApi.HashtagSegment) segment;
                    ActivityContentPart hashtagPart = new ActivityContentPart();
                    hashtagPart.partType = 'text';
                    hashtagPart.text = '#' + escapeHtml(hashtagSegment.tag);
                    parts.add(hashtagPart);
                } else if (segment instanceof ConnectApi.LinkSegment) {
                    ConnectApi.LinkSegment linkSegment = (ConnectApi.LinkSegment) segment;
                    ActivityContentPart linkPart = new ActivityContentPart();
                    linkPart.partType = 'text';
                    linkPart.text =
                        '<a href="' + linkSegment.url + '" target="_blank">' +
                        escapeHtml(linkSegment.url) +
                        '</a>';
                    parts.add(linkPart);
                }
            }

            Map<String, Id> versionToDocumentId = resolveContentDocumentIds(versionIds);
            for (Integer partIndex : imagePartIndexes) {
                ActivityContentPart imagePart = parts[partIndex];
                Id contentDocumentId = extractContentDocumentIdFromImageUrl(imagePart.imageUrl);
                if (contentDocumentId == null) {
                    String versionId = extractVersionIdFromImageUrl(imagePart.imageUrl);
                    if (String.isNotBlank(versionId)) {
                        contentDocumentId = versionToDocumentId.get(versionId);
                    }
                }
                imagePart.contentDocumentId = contentDocumentId;
            }

            return parts;
        } catch (Exception ex) {
            return new List<ActivityContentPart>();
        }
    }

    private static Id extractContentDocumentIdFromImageUrl(String imageUrl) {
        if (String.isBlank(imageUrl)) {
            return null;
        }
        Matcher documentMatcher = Pattern.compile('/document/download/([a-zA-Z0-9]{15,18})').matcher(imageUrl);
        if (documentMatcher.find()) {
            return (Id) documentMatcher.group(1);
        }
        return null;
    }

    private static String extractVersionIdFromImageUrl(String imageUrl) {
        if (String.isBlank(imageUrl)) {
            return null;
        }
        Matcher queryMatcher = Pattern.compile('versionId=([a-zA-Z0-9]{15,18})').matcher(imageUrl);
        if (queryMatcher.find()) {
            return queryMatcher.group(1);
        }
        Matcher downloadMatcher = Pattern.compile('/version/download/([a-zA-Z0-9]{15,18})').matcher(imageUrl);
        if (downloadMatcher.find()) {
            return downloadMatcher.group(1);
        }
        return null;
    }

    private static Map<String, Id> resolveContentDocumentIds(List<String> versionIds) {
        Map<String, Id> versionToDocumentId = new Map<String, Id>();
        if (versionIds == null || versionIds.isEmpty()) {
            return versionToDocumentId;
        }

        Set<Id> versionIdSet = new Set<Id>();
        for (String versionId : versionIds) {
            versionIdSet.add((Id) versionId);
        }

        for (ContentVersion version : [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :versionIdSet
        ]) {
            versionToDocumentId.put(version.Id, version.ContentDocumentId);
        }
        return versionToDocumentId;
    }

    private static String buildFeedItemTitle(FeedItem fi) {
        if (fi.Type == 'ContentPost' && String.isNotBlank(fi.Title)) {
            return fi.Title;
        }
        if (String.isNotBlank(fi.Body) && !containsInlineImageReference(fi.Body)) {
            String trimmed = fi.Body.trim();
            return trimmed.length() > 80 ? trimmed.substring(0, 80) + '...' : trimmed;
        }
        return 'Chatter post';
    }

    private static String resolveEmailBody(EmailMessage em) {
        if (String.isNotBlank(em.HtmlBody)) {
            return resolveEmailInlineImages(em.HtmlBody, em.Id);
        }
        return em.TextBody;
    }

    private static String resolveEmailInlineImages(String htmlBody, Id emailMessageId) {
        if (String.isBlank(htmlBody) || !htmlBody.toLowerCase().contains('cid:')) {
            return htmlBody;
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :emailMessageId
        ];
        if (links.isEmpty()) {
            return htmlBody;
        }

        List<String> versionIds = new List<String>();
        for (ContentDocumentLink link : links) {
            if (link.ContentDocument?.LatestPublishedVersionId != null) {
                versionIds.add(link.ContentDocument.LatestPublishedVersionId);
            }
        }
        if (versionIds.isEmpty()) {
            return htmlBody;
        }

        String result = htmlBody;
        Pattern cidPattern = Pattern.compile('cid:[^"\'\\s>]+');
        Matcher matcher = cidPattern.matcher(htmlBody);
        Integer index = 0;
        while (matcher.find() && index < versionIds.size()) {
            String cidRef = matcher.group();
            String url = '/sfc/servlet.shepherd/version/download/' + versionIds[index];
            result = result.replace(cidRef, url);
            index++;
        }
        return result;
    }

    private static Boolean containsInlineImageReference(String body) {
        if (String.isBlank(body)) {
            return false;
        }
        if (body.toLowerCase().contains('<img')) {
            return true;
        }
        Pattern uuidPattern = Pattern.compile(
            '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        );
        return uuidPattern.matcher(body).find();
    }

    private static String escapeHtml(String text) {
        if (text == null) {
            return '';
        }
        return text.replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }

    private static Integer normalizePageSize(Integer pageSize) {
        if (pageSize == null || pageSize < 1) {
            return DEFAULT_PAGE_SIZE;
        }
        return pageSize;
    }

    private static List<ActivityItem> applyFilters(
        List<ActivityItem> items,
        String activityType,
        String searchTerm
    ) {
        String typeFilter = String.isBlank(activityType) || activityType == 'All' ? null : activityType;
        String term = String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();
        if (typeFilter == null && term == null) {
            return items;
        }

        List<ActivityItem> filteredItems = new List<ActivityItem>();
        for (ActivityItem item : items) {
            if (typeFilter != null && item.type != typeFilter) {
                continue;
            }
            if (term != null && !matchesSearch(item, term)) {
                continue;
            }
            filteredItems.add(item);
        }
        return filteredItems;
    }

    private static Boolean matchesSearch(ActivityItem item, String term) {
        return (item.title != null && item.title.toLowerCase().contains(term))
            || (item.description != null && item.description.toLowerCase().contains(term))
            || (item.createdByName != null && item.createdByName.toLowerCase().contains(term))
            || (item.sourceLabel != null && item.sourceLabel.toLowerCase().contains(term));
    }

    private static ActivityPageResult paginate(List<ActivityItem> items, Integer pageSize, Integer offset) {
        ActivityPageResult result = new ActivityPageResult();
        result.totalCount = items.size();
        result.items = new List<ActivityItem>();

        if (offset >= items.size()) {
            result.hasMore = false;
            result.nextOffset = offset;
            return result;
        }

        Integer endIndex = Math.min(offset + pageSize, items.size());
        for (Integer index = offset; index < endIndex; index++) {
            result.items.add(items[index]);
        }

        result.hasMore = endIndex < items.size();
        result.nextOffset = endIndex;
        return result;
    }

    private static void sortItems(List<ActivityItem> items, SortDirection direction) {
        items.sort(new ActivityItemComparator(direction));
    }

    private static SortDirection parseSortDirection(String value) {
        if (String.isBlank(value)) {
            return SortDirection.DESCENDING;
        }
        String v = value.toUpperCase();
        if (v == 'ASC' || v == 'ASCENDING') {
            return SortDirection.ASCENDING;
        }
        return SortDirection.DESCENDING;
    }

    private static String iconNameFor(String type) {
        switch on type {
            when 'Task' { return 'standard:task'; }
            when 'Event' { return 'standard:event'; }
            when 'EmailMessage' { return 'standard:email'; }
            when 'FeedItem' { return 'standard:feed'; }
            when else { return 'standard:default'; }
        }
    }

    private static String formattedTypeFor(String type) {
        switch on type {
            when 'Task' { return 'Task'; }
            when 'Event' { return 'Event'; }
            when 'EmailMessage' { return 'Email'; }
            when 'FeedItem' { return 'Chatter'; }
            when else { return type; }
        }
    }

    public class IllegalArgumentException extends Exception {}

    public class ActivityItemComparator implements Comparator<ActivityItem> {
        private final SortDirection direction;

        public ActivityItemComparator(SortDirection direction) {
            this.direction = direction;
        }

        public Integer compare(ActivityItem a, ActivityItem b) {
            if (a.createdDate == null && b.createdDate == null) {
                return 0;
            }
            if (a.createdDate == null) {
                return 1;
            }
            if (b.createdDate == null) {
                return -1;
            }
            Integer multiplier = (direction == SortDirection.ASCENDING) ? 1 : -1;
            return multiplier * (a.createdDate > b.createdDate ? 1 : (a.createdDate < b.createdDate ? -1 : 0));
        }
    }
}
