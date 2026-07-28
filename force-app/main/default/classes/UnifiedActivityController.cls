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
            this(id, type, title, description, createdDate, createdById, createdByName, status, null);
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
            this.id = id;
            this.type = type;
            this.title = title;
            this.description = description;
            this.contentParts = contentParts != null ? contentParts : new List<ActivityContentPart>();
            this.createdDate = createdDate;
            this.createdById = createdById;
            this.createdByName = createdByName;
            this.status = status;
            this.iconName = iconNameFor(type);
            this.formattedType = formattedTypeFor(type);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ActivityItem> getUnifiedActivities(Id recordId, String sortDirection) {
        if (recordId == null) {
            throw new IllegalArgumentException('recordId is required');
        }

        SortDirection direction = parseSortDirection(sortDirection);

        List<ActivityItem> items = new List<ActivityItem>();
        items.addAll(getTasks(recordId));
        items.addAll(getEvents(recordId));
        items.addAll(getEmailMessages(recordId));
        items.addAll(getFeedItems(recordId));

        sortItems(items, direction);
        return items;
    }

    @AuraEnabled
    public static void createChatterPost(Id recordId, String body) {
        if (recordId == null) {
            throw new IllegalArgumentException('recordId is required');
        }
        if (String.isBlank(body)) {
            throw new IllegalArgumentException('body is required');
        }

        ConnectApi.ChatterFeeds.postFeedElement(
            null,
            recordId,
            ConnectApi.FeedElementType.FeedItem,
            body
        );
    }

    private static List<ActivityItem> getTasks(Id recordId) {
        List<ActivityItem> result = new List<ActivityItem>();
        for (Task t : [
            SELECT Id, Subject, Description, CreatedDate, CreatedById, CreatedBy.Name, Status, IsClosed
            FROM Task
            WHERE WhatId = :recordId OR WhoId = :recordId
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            result.add(new ActivityItem(
                t.Id,
                TYPE_TASK,
                t.Subject,
                t.Description,
                t.CreatedDate,
                t.CreatedById,
                t.CreatedBy?.Name,
                t.Status
            ));
        }
        return result;
    }

    private static List<ActivityItem> getEvents(Id recordId) {
        List<ActivityItem> result = new List<ActivityItem>();
        for (Event e : [
            SELECT Id, Subject, Description, CreatedDate, CreatedById, CreatedBy.Name, StartDateTime, EndDateTime
            FROM Event
            WHERE WhatId = :recordId OR WhoId = :recordId
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            result.add(new ActivityItem(
                e.Id,
                TYPE_EVENT,
                e.Subject,
                e.Description,
                e.CreatedDate,
                e.CreatedById,
                e.CreatedBy?.Name,
                null
            ));
        }
        return result;
    }

    private static List<ActivityItem> getEmailMessages(Id recordId) {
        List<ActivityItem> result = new List<ActivityItem>();
        for (EmailMessage em : [
            SELECT Id, Subject, TextBody, HtmlBody, CreatedDate, CreatedById, CreatedBy.Name, Status
            FROM EmailMessage
            WHERE RelatedToId = :recordId OR ActivityId = :recordId
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            String body = resolveEmailBody(em);
            result.add(new ActivityItem(
                em.Id,
                TYPE_EMAIL,
                em.Subject,
                body,
                em.CreatedDate,
                em.CreatedById,
                em.CreatedBy?.Name,
                em.Status
            ));
        }
        return result;
    }

    private static List<ActivityItem> getFeedItems(Id recordId) {
        List<ActivityItem> result = new List<ActivityItem>();
        if (!Schema.sObjectType.FeedItem.isAccessible()) {
            return result;
        }
        List<FeedItem> feedItems = [
            SELECT Id, Body, Title, Type, RelatedRecordId, CreatedDate, CreatedById, CreatedBy.Name
            FROM FeedItem
            WHERE ParentId = :recordId
            ORDER BY CreatedDate DESC
            LIMIT 500
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
                contentParts
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
            textPart.text = escapeHtml(fi.Body);
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
