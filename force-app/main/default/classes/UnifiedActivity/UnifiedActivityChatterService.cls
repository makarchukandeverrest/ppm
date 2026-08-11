public with sharing class UnifiedActivityChatterService {
    private final UnifiedActivityMapper mapper;

    public UnifiedActivityChatterService() {
        this(new UnifiedActivityMapper());
    }

    public UnifiedActivityChatterService(UnifiedActivityMapper mapper) {
        this.mapper = mapper;
    }

    public void createChatterPost(Id recordId, String body, List<String> imageContentVersionIds) {
        if (recordId == null) {
            throw new UnifiedActivityException('recordId is required');
        }
        if (UnifiedActivityUtils.isBlankRichText(body)) {
            throw new UnifiedActivityException('body is required');
        }
        if (!Schema.sObjectType.FeedItem.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create Chatter posts');
        }

        String trimmedBody = normalizeFeedItemRichText(body.trim());
        if (UnifiedActivityUtils.containsInlineHtmlImage(trimmedBody)) {
            createChatterPostWithConnectApi(recordId, trimmedBody, imageContentVersionIds);
            return;
        }

        FeedItem feedItem = new FeedItem();
        feedItem.ParentId = recordId;
        feedItem.Body = trimmedBody;
        feedItem.IsRichText = true;
        insert as user feedItem;
    }

    @TestVisible
    private String normalizeFeedItemRichText(String html) {
        if (String.isBlank(html)) {
            return html;
        }
        String normalized = html;
        normalized = normalized.replaceAll('(?i)<strong\\b[^>]*>', '<b>');
        normalized = normalized.replaceAll('(?i)</strong\\s*>', '</b>');
        normalized = normalized.replaceAll('(?i)<em\\b[^>]*>', '<i>');
        normalized = normalized.replaceAll('(?i)</em\\s*>', '</i>');
        return normalized;
    }

    private void createChatterPostWithConnectApi(
        Id recordId,
        String htmlBody,
        List<String> imageContentVersionIds
    ) {
        ConnectApi.FeedItemInput input = new ConnectApi.FeedItemInput();
        input.subjectId = recordId;
        input.feedElementType = ConnectApi.FeedElementType.FeedItem;

        ConnectApi.MessageBodyInput messageBody = new ConnectApi.MessageBodyInput();
        messageBody.messageSegments = mapper.buildConnectApiSegmentsFromRichTextHtml(
            htmlBody,
            imageContentVersionIds
        );
        if (messageBody.messageSegments.isEmpty()) {
            throw new UnifiedActivityException('body is required');
        }

        input.body = messageBody;
        ConnectApi.ChatterFeeds.postFeedElement(null, input);
    }
}
