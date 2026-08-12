public with sharing class UnifiedActivityMapper {
    public static final String TYPE_TASK = 'Task';
    public static final String TYPE_EVENT = 'Event';
    public static final String TYPE_EMAIL = 'EmailMessage';
    public static final String TYPE_FEED = 'FeedItem';

    private static final Map<String, String> EMAIL_STATUS_MAP = new Map<String, String>{
        '0' => 'New',
        '1' => 'Read',
        '2' => 'Replied',
        '3' => 'Sent',
        '4' => 'Forwarded',
        '5' => 'Draft'
    };

    private final UnifiedActivitySelector selector;

    public UnifiedActivityMapper() {
        this(new UnifiedActivitySelector());
    }

    public UnifiedActivityMapper(UnifiedActivitySelector selector) {
        this.selector = selector;
    }

    public List<UnifiedActivityModels.ActivityItem> mapTasks(List<Task> tasks, Map<Id, String> recordLabels) {
        List<UnifiedActivityModels.ActivityItem> result = new List<UnifiedActivityModels.ActivityItem>();
        for (Task t : tasks) {
            if (isEmailLikeTask(t)) {
                continue;
            }
            result.add(new UnifiedActivityModels.ActivityItem(
                t.Id,
                TYPE_TASK,
                t.Subject,
                t.Description,
                t.CreatedDate,
                t.CreatedById,
                t.CreatedBy?.Name,
                t.Status,
                null,
                UnifiedActivityUtils.resolveSourceLabel(t.WhatId, t.WhoId, recordLabels)
            ));
        }
        return result;
    }

    public List<UnifiedActivityModels.ActivityItem> mapEvents(List<Event> events, Map<Id, String> recordLabels) {
        List<UnifiedActivityModels.ActivityItem> result = new List<UnifiedActivityModels.ActivityItem>();
        for (Event e : events) {
            result.add(new UnifiedActivityModels.ActivityItem(
                e.Id,
TYPE_EVENT,
                e.Subject,
                e.Description,
                e.CreatedDate,
                e.CreatedById,
                e.CreatedBy?.Name,
                null,
                null,
                UnifiedActivityUtils.resolveSourceLabel(e.WhatId, e.WhoId, recordLabels)
            ));
        }
        return result;
    }

    public List<UnifiedActivityModels.ActivityItem> mapEmailMessages(
        List<EmailMessage> emailMessages,
        Map<Id, String> recordLabels
    ) {
        List<UnifiedActivityModels.ActivityItem> result = new List<UnifiedActivityModels.ActivityItem>();
        Map<Id, Integer> attachmentCounts = selector.countEmailAttachments(
            new Map<Id, EmailMessage>(emailMessages).keySet()
        );

        for (EmailMessage em : emailMessages) {
            String body = resolveEmailBody(em);
            UnifiedActivityModels.ActivityItem item = new UnifiedActivityModels.ActivityItem(
                em.Id,
                TYPE_EMAIL,
                em.Subject,
                body,
                em.CreatedDate,
                em.CreatedById,
                em.CreatedBy?.Name,
                EMAIL_STATUS_MAP.get(em.Status),
                null,
                UnifiedActivityUtils.resolveSourceLabel(em.RelatedToId, em.ActivityId, recordLabels)
            );
            item.attachmentCount = attachmentCounts.containsKey(em.Id)
                ? attachmentCounts.get(em.Id)
                : 0;
            result.add(item);
        }
        return result;
    }

    public List<UnifiedActivityModels.ActivityItem> mapFeedItems(
        List<FeedItem> feedItems,
        Map<Id, String> recordLabels
    ) {
        List<UnifiedActivityModels.ActivityItem> result = new List<UnifiedActivityModels.ActivityItem>();
        for (FeedItem fi : feedItems) {
            List<UnifiedActivityModels.ActivityContentPart> contentParts = buildFeedItemContentParts(fi);
            String feedTitle = fi.Type == 'TrackedChange'
                ? buildTrackedChangeTitle(contentParts, fi)
                : buildFeedItemTitle(fi);
            result.add(new UnifiedActivityModels.ActivityItem(
                fi.Id,
                TYPE_FEED,
                feedTitle,
                UnifiedActivityUtils.buildPlainTextFromParts(contentParts, fi.Body),
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

    private Boolean isEmailLikeTask(Task taskRecord) {
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

    private String resolveEmailBody(EmailMessage em) {
        if (String.isNotBlank(em.HtmlBody)) {
            return resolveEmailInlineImages(em.HtmlBody, em.Id);
        }
        return em.TextBody;
    }

    private String resolveEmailInlineImages(String htmlBody, Id emailMessageId) {
        if (String.isBlank(htmlBody) || !htmlBody.toLowerCase().contains('cid:')) {
            return htmlBody;
        }

        List<ContentDocumentLink> links = selector.queryContentDocumentLinksByEntityIds(new Set<Id>{ emailMessageId });
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

    private List<UnifiedActivityModels.ActivityContentPart> buildFeedItemContentParts(FeedItem fi) {
        if (fi.Type == 'ContentPost' && fi.RelatedRecordId != null) {
            return new List<UnifiedActivityModels.ActivityContentPart>{
                buildImagePart(
                    fi.RelatedRecordId,
                    '/sfc/servlet.shepherd/document/download/' + fi.RelatedRecordId,
                    fi.Title
                )
            };
        }

        List<UnifiedActivityModels.ActivityContentPart> connectApiParts = buildFeedContentPartsFromConnectApi(fi.Id);
        if (!connectApiParts.isEmpty()) {
            return connectApiParts;
        }

        if (String.isNotBlank(fi.Body)) {
            UnifiedActivityModels.ActivityContentPart textPart = new UnifiedActivityModels.ActivityContentPart();
            textPart.partType = 'text';
            textPart.text = UnifiedActivityUtils.isRichTextBody(fi.Body) ? fi.Body : UnifiedActivityUtils.escapeHtml(fi.Body);
            return new List<UnifiedActivityModels.ActivityContentPart>{ textPart };
        }

        if (String.isNotBlank(fi.Title)) {
            UnifiedActivityModels.ActivityContentPart titlePart = new UnifiedActivityModels.ActivityContentPart();
            titlePart.partType = 'text';
            titlePart.text = UnifiedActivityUtils.escapeHtml(fi.Title);
            return new List<UnifiedActivityModels.ActivityContentPart>{ titlePart };
        }

        return new List<UnifiedActivityModels.ActivityContentPart>();
    }

    private String buildFeedItemTitle(FeedItem fi) {
        if (fi.Type == 'ContentPost' && String.isNotBlank(fi.Title)) {
            return fi.Title;
        }
        if (String.isNotBlank(fi.Body) && !UnifiedActivityUtils.containsInlineImageReference(fi.Body)) {
            String trimmed = fi.Body.trim();
            return trimmed.length() > 80 ? trimmed.substring(0, 80) + '...' : trimmed;
        }
        return 'Chatter post';
    }

    private String buildTrackedChangeTitle(
        List<UnifiedActivityModels.ActivityContentPart> parts,
        FeedItem fi
    ) {
        if (parts != null && !parts.isEmpty() && String.isNotBlank(parts[0].text)) {
            String plainText = parts[0].text.replaceAll('<[^>]+>', ' ').replaceAll('\\s+', ' ').trim();
            Integer newlineIndex = plainText.indexOf('\n');
            if (newlineIndex > 0) {
                plainText = plainText.substring(0, newlineIndex).trim();
            }
            if (String.isNotBlank(plainText)) {
                return plainText.length() > 80 ? plainText.substring(0, 80) + '...' : plainText;
            }
        }
        return buildFeedItemTitle(fi);
    }

    private UnifiedActivityModels.ActivityContentPart buildImagePart(Id contentDocumentId, String imageUrl, String altText) {
        UnifiedActivityModels.ActivityContentPart part = new UnifiedActivityModels.ActivityContentPart();
        part.partType = 'image';
        part.contentDocumentId = contentDocumentId;
        part.imageUrl = imageUrl;
        part.altText = String.isNotBlank(altText) ? altText : 'Attachment';
        return part;
    }

    private List<UnifiedActivityModels.ActivityContentPart> buildFeedContentPartsFromConnectApi(Id feedItemId) {
        try {
            ConnectApi.FeedElement element = ConnectApi.ChatterFeeds.getFeedElement(null, feedItemId);
            if (!(element instanceof ConnectApi.FeedItem)) {
                return new List<UnifiedActivityModels.ActivityContentPart>();
            }

            ConnectApi.FeedItem feedItem = (ConnectApi.FeedItem) element;

            List<UnifiedActivityModels.ActivityContentPart> parts = new List<UnifiedActivityModels.ActivityContentPart>();
            List<String> versionIds = new List<String>();
            List<Integer> imagePartIndexes = new List<Integer>();

            if (feedItem.body != null && feedItem.body.messageSegments != null) {
                for (ConnectApi.MessageSegment segment : feedItem.body.messageSegments) {
                    appendSegment(parts, segment, versionIds, imagePartIndexes);
                }
            }

            if (parts.isEmpty()) {
                parts.addAll(buildTrackedChangesCapabilityParts(feedItem));
            }

            Map<String, Id> versionToDocumentId = resolveContentDocumentIds(versionIds);
            for (Integer partIndex : imagePartIndexes) {
                UnifiedActivityModels.ActivityContentPart imagePart = parts[partIndex];
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
            return new List<UnifiedActivityModels.ActivityContentPart>();
        }
    }

    private void appendSegment(
        List<UnifiedActivityModels.ActivityContentPart> parts,
        ConnectApi.MessageSegment segment,
        List<String> versionIds,
        List<Integer> imagePartIndexes
    ) {
        if (segment instanceof ConnectApi.TextSegment) {
            UnifiedActivityModels.ActivityContentPart textPart = new UnifiedActivityModels.ActivityContentPart();
            textPart.partType = 'text';
            textPart.text = UnifiedActivityUtils.escapeHtml(((ConnectApi.TextSegment) segment).text);
            parts.add(textPart);
        } else if (segment instanceof ConnectApi.InlineImageSegment) {
            ConnectApi.InlineImageSegment imageSegment = (ConnectApi.InlineImageSegment) segment;
            UnifiedActivityModels.ActivityContentPart imagePart = new UnifiedActivityModels.ActivityContentPart();
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
            UnifiedActivityModels.ActivityContentPart mentionPart = new UnifiedActivityModels.ActivityContentPart();
            mentionPart.partType = 'text';
            mentionPart.text = '<strong>@' + UnifiedActivityUtils.escapeHtml(mentionSegment.name) + '</strong>';
            parts.add(mentionPart);
        } else if (segment instanceof ConnectApi.HashtagSegment) {
            ConnectApi.HashtagSegment hashtagSegment = (ConnectApi.HashtagSegment) segment;
            UnifiedActivityModels.ActivityContentPart hashtagPart = new UnifiedActivityModels.ActivityContentPart();
            hashtagPart.partType = 'text';
            hashtagPart.text = '#' + UnifiedActivityUtils.escapeHtml(hashtagSegment.tag);
            parts.add(hashtagPart);
        } else if (segment instanceof ConnectApi.LinkSegment) {
            ConnectApi.LinkSegment linkSegment = (ConnectApi.LinkSegment) segment;
            UnifiedActivityModels.ActivityContentPart linkPart = new UnifiedActivityModels.ActivityContentPart();
            linkPart.partType = 'text';
            linkPart.text =
                '<a href="' + linkSegment.url + '" target="_blank">' +
                UnifiedActivityUtils.escapeHtml(linkSegment.url) +
                '</a>';
            parts.add(linkPart);
        } else if (segment instanceof ConnectApi.EntityLinkSegment) {
            ConnectApi.EntityLinkSegment entityLinkSegment = (ConnectApi.EntityLinkSegment) segment;
            UnifiedActivityModels.ActivityContentPart entityPart = new UnifiedActivityModels.ActivityContentPart();
            entityPart.partType = 'text';
            entityPart.text = UnifiedActivityUtils.escapeHtml(entityLinkSegment.text);
            parts.add(entityPart);
        } else if (segment instanceof ConnectApi.FieldChangeNameSegment) {
            ConnectApi.FieldChangeNameSegment nameSegment = (ConnectApi.FieldChangeNameSegment) segment;
            UnifiedActivityModels.ActivityContentPart namePart = new UnifiedActivityModels.ActivityContentPart();
            namePart.partType = 'text';
            namePart.text = '<strong>' + UnifiedActivityUtils.escapeHtml(nameSegment.text) + '</strong>';
            parts.add(namePart);
        } else if (segment instanceof ConnectApi.FieldChangeValueSegment) {
            ConnectApi.FieldChangeValueSegment valueSegment = (ConnectApi.FieldChangeValueSegment) segment;
            if (String.isNotBlank(valueSegment.text)) {
                UnifiedActivityModels.ActivityContentPart valuePart = new UnifiedActivityModels.ActivityContentPart();
                valuePart.partType = 'text';
                valuePart.text = UnifiedActivityUtils.escapeHtml(valueSegment.text);
                parts.add(valuePart);
            }
        } else if (String.isNotBlank(segment.text)) {
            UnifiedActivityModels.ActivityContentPart fallbackPart = new UnifiedActivityModels.ActivityContentPart();
            fallbackPart.partType = 'text';
            fallbackPart.text = UnifiedActivityUtils.escapeHtml(segment.text);
            parts.add(fallbackPart);
        }
    }

    private List<UnifiedActivityModels.ActivityContentPart> buildTrackedChangesCapabilityParts(ConnectApi.FeedItem feedItem) {
        List<UnifiedActivityModels.ActivityContentPart> parts = new List<UnifiedActivityModels.ActivityContentPart>();
        if (feedItem.capabilities == null
            || feedItem.capabilities.trackedChanges == null
            || feedItem.capabilities.trackedChanges.changes == null) {
            return parts;
        }

        for (ConnectApi.TrackedChangeItem changeItem : feedItem.capabilities.trackedChanges.changes) {
            if (String.isNotBlank(changeItem.fieldName)) {
                UnifiedActivityModels.ActivityContentPart namePart = new UnifiedActivityModels.ActivityContentPart();
                namePart.partType = 'text';
                namePart.text = '<strong>' + UnifiedActivityUtils.escapeHtml(UnifiedActivityUtils.formatFieldApiName(changeItem.fieldName)) + '</strong>';
                parts.add(namePart);
            }

            String oldValueText = changeItem.oldValue;
            String newValueText = changeItem.newValue;
            String valueText;
            if (String.isNotBlank(oldValueText) && String.isNotBlank(newValueText)) {
                valueText = oldValueText + ' to ' + newValueText;
            } else if (String.isNotBlank(newValueText)) {
                valueText = newValueText;
            } else if (String.isNotBlank(oldValueText)) {
                valueText = oldValueText;
            } else {
                valueText = null;
            }

            if (String.isNotBlank(valueText)) {
                UnifiedActivityModels.ActivityContentPart valuePart = new UnifiedActivityModels.ActivityContentPart();
                valuePart.partType = 'text';
                valuePart.text = UnifiedActivityUtils.escapeHtml(valueText);
                parts.add(valuePart);
            }
        }
        return parts;
    }

    private Map<String, Id> resolveContentDocumentIds(List<String> versionIds) {
        Map<String, Id> versionToDocumentId = new Map<String, Id>();
        if (versionIds == null || versionIds.isEmpty()) {
            return versionToDocumentId;
        }

        Set<Id> versionIdSet = new Set<Id>();
        for (String versionId : versionIds) {
            versionIdSet.add((Id) versionId);
        }

        for (ContentVersion version : selector.queryContentVersionsByIds(versionIdSet)) {
            versionToDocumentId.put(version.Id, version.ContentDocumentId);
        }
        return versionToDocumentId;
    }

    private Id extractContentDocumentIdFromImageUrl(String imageUrl) {
        if (String.isBlank(imageUrl)) {
            return null;
        }
        Matcher documentMatcher = Pattern.compile('/document/download/([a-zA-Z0-9]{15,18})').matcher(imageUrl);
        if (documentMatcher.find()) {
            return (Id) documentMatcher.group(1);
        }
        return null;
    }

    private String extractVersionIdFromImageUrl(String imageUrl) {
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

    private Id resolveContentDocumentIdFromImageUrl(String imageUrl) {
        if (String.isBlank(imageUrl)) {
            return null;
        }

        String normalizedUrl = UnifiedActivityUtils.unescapeHtmlAttribute(imageUrl);

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

    private Id resolveContentDocumentIdFromVersionId(String versionIdValue) {
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

        List<ContentVersion> versions = selector.queryContentVersionById(versionKey);
        return versions.isEmpty() ? null : versions[0].ContentDocumentId;
    }

    private Id resolveInlineImageContentDocumentId(
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

    public List<ConnectApi.MessageSegmentInput> buildConnectApiSegmentsFromRichTextHtml(
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

            String imageUrl = UnifiedActivityUtils.unescapeHtmlAttribute(matcher.group(1));
            Id contentDocumentId = resolveInlineImageContentDocumentId(
                imageUrl,
                imageContentVersionIds,
                imageIndex
            );
            imageIndex++;

            if (contentDocumentId == null) {
                throw new UnifiedActivityException(
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

                String imageUrl = UnifiedActivityUtils.unescapeHtmlAttribute(singleQuoteMatcher.group(1));
                Id contentDocumentId = resolveInlineImageContentDocumentId(
                    imageUrl,
                    imageContentVersionIds,
                    imageIndex
                );
                imageIndex++;

                if (contentDocumentId == null) {
                    throw new UnifiedActivityException(
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

    private void appendTextSegmentFromHtml(
        List<ConnectApi.MessageSegmentInput> segments,
        String htmlFragment
    ) {
        String plainText = UnifiedActivityUtils.stripHtmlToPlainText(htmlFragment);
        if (String.isBlank(plainText)) {
            return;
        }

        ConnectApi.TextSegmentInput textSegment = new ConnectApi.TextSegmentInput();
        textSegment.text = plainText;
        segments.add(textSegment);
    }
}
