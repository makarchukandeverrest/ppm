public with sharing class UnifiedActivityMapper {
  public static final String TYPE_TASK = 'Task';
  public static final String TYPE_CALL = 'Call';
  public static final String TYPE_EVENT = 'Event';
  public static final String TYPE_EMAIL = 'EmailMessage';
  public static final String TYPE_FEED = 'FeedItem';
  public static final String TYPE_NOTE = 'ContentNote';

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

  public List<UnifiedActivityModels.ActivityItem> mapTasks(
    List<Task> tasks,
    Map<Id, String> recordLabels
  ) {
    List<UnifiedActivityModels.ActivityItem> result = new List<UnifiedActivityModels.ActivityItem>();
    for (Task t : tasks) {
      if (isEmailLikeTask(t)) {
        continue;
      }
      result.add(
        new UnifiedActivityModels.ActivityItem(
          t.Id,
          isCallTask(t) ? TYPE_CALL : TYPE_TASK,
          t.Subject,
          t.Description,
          t.CreatedDate,
          t.CreatedById,
          t.CreatedBy?.Name,
          t.Status,
          null,
          UnifiedActivityUtils.resolveSourceLabel(
            t.WhatId,
            t.WhoId,
            recordLabels
          )
        )
      );
    }
    return result;
  }

  public List<UnifiedActivityModels.ActivityItem> mapEvents(
    List<Event> events,
    Map<Id, String> recordLabels
  ) {
    List<UnifiedActivityModels.ActivityItem> result = new List<UnifiedActivityModels.ActivityItem>();
    for (Event e : events) {
      result.add(
        new UnifiedActivityModels.ActivityItem(
          e.Id,
          TYPE_EVENT,
          e.Subject,
          e.Description,
          e.CreatedDate,
          e.CreatedById,
          e.CreatedBy?.Name,
          null,
          null,
          UnifiedActivityUtils.resolveSourceLabel(
            e.WhatId,
            e.WhoId,
            recordLabels
          )
        )
      );
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
        resolveEmailActorName(em),
        EMAIL_STATUS_MAP.get(em.Status),
        null,
        UnifiedActivityUtils.resolveSourceLabel(
          em.RelatedToId,
          em.ActivityId,
          recordLabels
        )
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
    Map<Id, ContentVersion> versionsById = loadContentPostVersions(feedItems);
    Map<Id, ContentNote> notesById = loadNotesForContentPosts(versionsById);

    for (FeedItem fi : feedItems) {
      if (fi.Type == 'ContentPost' && fi.RelatedRecordId != null) {
        ContentVersion version = versionsById.get(fi.RelatedRecordId);
        if (version != null && version.FileType == 'SNOTE') {
          result.add(
            mapNoteFeedItem(
              fi,
              version,
              notesById.get(version.ContentDocumentId),
              recordLabels
            )
          );
          continue;
        }
      }

      List<UnifiedActivityModels.ActivityContentPart> contentParts = buildFeedItemContentParts(
        fi,
        versionsById
      );
      String feedTitle = fi.Type == 'TrackedChange'
        ? buildTrackedChangeTitle(contentParts, fi)
        : buildFeedItemTitle(fi);
      result.add(
        new UnifiedActivityModels.ActivityItem(
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
        )
      );
    }
    return result;
  }

  private Map<Id, ContentVersion> loadContentPostVersions(
    List<FeedItem> feedItems
  ) {
    Set<Id> versionIds = new Set<Id>();
    for (FeedItem fi : feedItems) {
      if (fi.Type == 'ContentPost' && fi.RelatedRecordId != null) {
        versionIds.add(fi.RelatedRecordId);
      }
    }
    Map<Id, ContentVersion> versionsById = new Map<Id, ContentVersion>();
    if (versionIds.isEmpty()) {
      return versionsById;
    }
    for (
      ContentVersion version : selector.queryContentVersionsForFeedPosts(
        versionIds
      )
    ) {
      versionsById.put(version.Id, version);
    }
    return versionsById;
  }

  private Map<Id, ContentNote> loadNotesForContentPosts(
    Map<Id, ContentVersion> versionsById
  ) {
    Set<Id> noteIds = new Set<Id>();
    for (ContentVersion version : versionsById.values()) {
      if (version.FileType == 'SNOTE' && version.ContentDocumentId != null) {
        noteIds.add(version.ContentDocumentId);
      }
    }
    Map<Id, ContentNote> notesById = new Map<Id, ContentNote>();
    if (noteIds.isEmpty()) {
      return notesById;
    }
    for (ContentNote note : selector.queryContentNotesByIds(noteIds)) {
      notesById.put(note.Id, note);
    }
    return notesById;
  }

  private UnifiedActivityModels.ActivityItem mapNoteFeedItem(
    FeedItem fi,
    ContentVersion version,
    ContentNote note,
    Map<Id, String> recordLabels
  ) {
    String htmlBody = note != null &&
      note.Content != null
      ? note.Content.toString()
      : '';
    List<UnifiedActivityModels.ActivityContentPart> contentParts = buildNoteContentParts(
      htmlBody
    );
    String title = String.isNotBlank(fi.Title)
      ? fi.Title
      : (note != null && String.isNotBlank(note.Title)
          ? note.Title
          : 'Untitled Note');

    return new UnifiedActivityModels.ActivityItem(
      version.ContentDocumentId != null ? version.ContentDocumentId : fi.Id,
      TYPE_NOTE,
      title,
      UnifiedActivityUtils.buildPlainTextFromParts(contentParts, htmlBody),
      fi.CreatedDate,
      fi.CreatedById,
      fi.CreatedBy?.Name,
      null,
      contentParts,
      recordLabels.get(fi.ParentId)
    );
  }

  @TestVisible
  private List<UnifiedActivityModels.ActivityContentPart> buildNoteContentParts(
    String html
  ) {
    List<UnifiedActivityModels.ActivityContentPart> parts = new List<UnifiedActivityModels.ActivityContentPart>();
    if (String.isBlank(html)) {
      return parts;
    }

    Pattern imgPattern = Pattern.compile(
      '(?i)<img[^>]+src=["\']([^"\']+)["\'][^>]*>'
    );
    Matcher matcher = imgPattern.matcher(html);
    Integer lastEnd = 0;
    Boolean foundImage = false;

    while (matcher.find()) {
      foundImage = true;
      String before = html.substring(lastEnd, matcher.start());
      if (
        String.isNotBlank(UnifiedActivityUtils.stripHtmlToPlainText(before))
      ) {
        UnifiedActivityModels.ActivityContentPart textPart = new UnifiedActivityModels.ActivityContentPart();
        textPart.partType = 'text';
        textPart.text = UnifiedActivityUtils.isRichTextBody(before)
          ? before
          : UnifiedActivityUtils.escapeHtml(before);
        parts.add(textPart);
      }

      String imageUrl = UnifiedActivityUtils.unescapeHtmlAttribute(
        matcher.group(1)
      );
      Id contentDocumentId = resolveNoteImageDocumentId(imageUrl);
      UnifiedActivityModels.ActivityContentPart imagePart = new UnifiedActivityModels.ActivityContentPart();
      imagePart.partType = 'image';
      imagePart.contentDocumentId = contentDocumentId;
      imagePart.imageUrl = contentDocumentId != null
        ? '/sfc/servlet.shepherd/document/download/' + contentDocumentId
        : imageUrl;
      imagePart.altText = 'Image';
      parts.add(imagePart);
      lastEnd = matcher.end();
    }

    if (!foundImage) {
      UnifiedActivityModels.ActivityContentPart textPart = new UnifiedActivityModels.ActivityContentPart();
      textPart.partType = 'text';
      textPart.text = UnifiedActivityUtils.isRichTextBody(html)
        ? html
        : UnifiedActivityUtils.escapeHtml(html);
      parts.add(textPart);
      return parts;
    }

    String after = html.substring(lastEnd);
    if (String.isNotBlank(UnifiedActivityUtils.stripHtmlToPlainText(after))) {
      UnifiedActivityModels.ActivityContentPart textPart = new UnifiedActivityModels.ActivityContentPart();
      textPart.partType = 'text';
      textPart.text = UnifiedActivityUtils.isRichTextBody(after)
        ? after
        : UnifiedActivityUtils.escapeHtml(after);
      parts.add(textPart);
    }
    return parts;
  }

  @TestVisible
  private Id resolveNoteImageDocumentId(String imageUrl) {
    if (String.isBlank(imageUrl)) {
      return null;
    }
    Matcher documentMatcher = Pattern.compile(
        '/document/download/([a-zA-Z0-9]{15,18})'
      )
      .matcher(imageUrl);
    if (documentMatcher.find()) {
      return (Id) documentMatcher.group(1);
    }

    String versionId;
    Matcher versionMatcher = Pattern.compile(
        '/version/download/([a-zA-Z0-9]{15,18})'
      )
      .matcher(imageUrl);
    Matcher eidMatcher = Pattern.compile('(?:\\?|&)eid=([a-zA-Z0-9]{15,18})')
      .matcher(imageUrl);
    if (versionMatcher.find()) {
      versionId = versionMatcher.group(1);
    } else if (eidMatcher.find()) {
      versionId = eidMatcher.group(1);
    } else {
      return null;
    }
    return resolveContentDocumentIdFromVersionId(versionId);
  }

  private Boolean isCallTask(Task taskRecord) {
    return taskRecord.TaskSubtype == 'Call';
  }

  private Boolean isEmailLikeTask(Task taskRecord) {
    if (
      taskRecord.TaskSubtype == 'Email' ||
      taskRecord.TaskSubtype == 'ListEmail'
    ) {
      return true;
    }
    if (String.isBlank(taskRecord.Description)) {
      return false;
    }
    String description = taskRecord.Description;
    return description.contains('To:') && description.contains('Subject:');
  }

  private String resolveEmailActorName(EmailMessage em) {
    if (String.isNotBlank(em.FromName)) {
      return em.FromName;
    }
    if (String.isNotBlank(em.FromAddress)) {
      return em.FromAddress;
    }
    return em.CreatedBy?.Name;
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

    List<ContentDocumentLink> links = selector.queryContentDocumentLinksByEntityIds(
      new Set<Id>{ emailMessageId }
    );
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
      String url =
        '/sfc/servlet.shepherd/version/download/' + versionIds[index];
      result = result.replace(cidRef, url);
      index++;
    }
    return result;
  }

  private List<UnifiedActivityModels.ActivityContentPart> buildFeedItemContentParts(
    FeedItem fi,
    Map<Id, ContentVersion> versionsById
  ) {
    if (fi.Type == 'ContentPost' && fi.RelatedRecordId != null) {
      ContentVersion version = versionsById != null
        ? versionsById.get(fi.RelatedRecordId)
        : null;
      Id contentDocumentId = version != null
        ? version.ContentDocumentId
        : resolveContentDocumentIdFromVersionId(
            String.valueOf(fi.RelatedRecordId)
          );
      Id partDocumentId = contentDocumentId != null
        ? contentDocumentId
        : fi.RelatedRecordId;
      if (version != null && !isImageFileType(version.FileType)) {
        return new List<UnifiedActivityModels.ActivityContentPart>{
          buildFilePart(partDocumentId, buildAttachmentFileName(version))
        };
      }
      String imageUrl = contentDocumentId != null
        ? '/sfc/servlet.shepherd/document/download/' + contentDocumentId
        : '/sfc/servlet.shepherd/version/download/' + fi.RelatedRecordId;
      return new List<UnifiedActivityModels.ActivityContentPart>{
        buildImagePart(partDocumentId, imageUrl, fi.Title)
      };
    }

    List<UnifiedActivityModels.ActivityContentPart> connectApiParts = buildFeedContentPartsFromConnectApi(
      fi.Id
    );
    if (!connectApiParts.isEmpty()) {
      return connectApiParts;
    }

    if (String.isNotBlank(fi.Body)) {
      UnifiedActivityModels.ActivityContentPart textPart = new UnifiedActivityModels.ActivityContentPart();
      textPart.partType = 'text';
      textPart.text = UnifiedActivityUtils.isRichTextBody(fi.Body)
        ? fi.Body
        : UnifiedActivityUtils.escapeHtml(fi.Body);
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

  @TestVisible
  private String buildFeedItemTitle(FeedItem fi) {
    if (fi.Type == 'ContentPost' && String.isNotBlank(fi.Title)) {
      return fi.Title;
    }
    if (
      String.isNotBlank(fi.Body) &&
      !UnifiedActivityUtils.containsInlineImageReference(fi.Body)
    ) {
      String trimmed = fi.Body.trim();
      return trimmed.length() > 80 ? trimmed.substring(0, 80) + '...' : trimmed;
    }
    return 'Chatter post';
  }

  @TestVisible
  private String buildTrackedChangeTitle(
    List<UnifiedActivityModels.ActivityContentPart> parts,
    FeedItem fi
  ) {
    if (parts != null && !parts.isEmpty() && String.isNotBlank(parts[0].text)) {
      String plainText = parts[0]
        .text.replaceAll('<[^>]+>', ' ')
        .replaceAll('\\s+', ' ')
        .trim();
      Integer newlineIndex = plainText.indexOf('\n');
      if (newlineIndex > 0) {
        plainText = plainText.substring(0, newlineIndex).trim();
      }
      if (String.isNotBlank(plainText)) {
        return plainText.length() > 80
          ? plainText.substring(0, 80) + '...'
          : plainText;
      }
    }
    return buildFeedItemTitle(fi);
  }

  private static final Set<String> IMAGE_FILE_TYPES = new Set<String>{
    'PNG',
    'JPG',
    'JPEG',
    'GIF',
    'BMP',
    'TIFF',
    'TIF',
    'WEBP'
  };

  private Boolean isImageFileType(String fileType) {
    return String.isNotBlank(fileType) &&
      IMAGE_FILE_TYPES.contains(fileType.toUpperCase());
  }

  private String buildAttachmentFileName(ContentVersion version) {
    String title = String.isNotBlank(version.Title)
      ? version.Title.trim()
      : 'Attachment';
    if (String.isBlank(version.FileExtension)) {
      return title;
    }
    String extension = '.' + version.FileExtension.toLowerCase();
    if (title.toLowerCase().endsWith(extension)) {
      return title;
    }
    return title + extension;
  }

  private UnifiedActivityModels.ActivityContentPart buildFilePart(
    Id contentDocumentId,
    String fileName
  ) {
    UnifiedActivityModels.ActivityContentPart part = new UnifiedActivityModels.ActivityContentPart();
    part.partType = 'file';
    part.contentDocumentId = contentDocumentId;
    part.fileName = fileName;
    part.altText = fileName;
    return part;
  }

  private UnifiedActivityModels.ActivityContentPart buildImagePart(
    Id contentDocumentId,
    String imageUrl,
    String altText
  ) {
    UnifiedActivityModels.ActivityContentPart part = new UnifiedActivityModels.ActivityContentPart();
    part.partType = 'image';
    part.contentDocumentId = contentDocumentId;
    part.imageUrl = imageUrl;
    part.altText = String.isNotBlank(altText) ? altText : 'Attachment';
    return part;
  }

  private List<UnifiedActivityModels.ActivityContentPart> buildFeedContentPartsFromConnectApi(
    Id feedItemId
  ) {
    try {
      ConnectApi.FeedElement element = ConnectApi.ChatterFeeds.getFeedElement(
        null,
        feedItemId
      );
      if (!(element instanceof ConnectApi.FeedItem)) {
        return new List<UnifiedActivityModels.ActivityContentPart>();
      }

      ConnectApi.FeedItem feedItem = (ConnectApi.FeedItem) element;

      List<UnifiedActivityModels.ActivityContentPart> parts = new List<UnifiedActivityModels.ActivityContentPart>();
      List<String> versionIds = new List<String>();
      List<Integer> imagePartIndexes = new List<Integer>();

      if (feedItem.body != null && feedItem.body.messageSegments != null) {
        for (
          ConnectApi.MessageSegment segment : feedItem.body.messageSegments
        ) {
          appendSegment(parts, segment, versionIds, imagePartIndexes);
        }
      }

      if (parts.isEmpty()) {
        parts.addAll(buildTrackedChangesCapabilityParts(feedItem));
      }

      Map<String, Id> versionToDocumentId = resolveContentDocumentIds(
        versionIds
      );
      for (Integer partIndex : imagePartIndexes) {
        UnifiedActivityModels.ActivityContentPart imagePart = parts[partIndex];
        Id contentDocumentId = extractContentDocumentIdFromImageUrl(
          imagePart.imageUrl
        );
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

  @TestVisible
  private void appendSegment(
    List<UnifiedActivityModels.ActivityContentPart> parts,
    ConnectApi.MessageSegment segment,
    List<String> versionIds,
    List<Integer> imagePartIndexes
  ) {
    if (segment instanceof ConnectApi.TextSegment) {
      UnifiedActivityModels.ActivityContentPart textPart = new UnifiedActivityModels.ActivityContentPart();
      textPart.partType = 'text';
      textPart.text = UnifiedActivityUtils.escapeHtml(
        ((ConnectApi.TextSegment) segment).text
      );
      parts.add(textPart);
    } else if (segment instanceof ConnectApi.InlineImageSegment) {
      ConnectApi.InlineImageSegment imageSegment = (ConnectApi.InlineImageSegment) segment;
      UnifiedActivityModels.ActivityContentPart imagePart = new UnifiedActivityModels.ActivityContentPart();
      imagePart.partType = 'image';
      imagePart.imageUrl = imageSegment.url;
      imagePart.altText = String.isNotBlank(imageSegment.altText)
        ? imageSegment.altText
        : 'Image';
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
      mentionPart.text =
        '<strong>@' +
        UnifiedActivityUtils.escapeHtml(mentionSegment.name) +
        '</strong>';
      parts.add(mentionPart);
    } else if (segment instanceof ConnectApi.HashtagSegment) {
      ConnectApi.HashtagSegment hashtagSegment = (ConnectApi.HashtagSegment) segment;
      UnifiedActivityModels.ActivityContentPart hashtagPart = new UnifiedActivityModels.ActivityContentPart();
      hashtagPart.partType = 'text';
      hashtagPart.text =
        '#' + UnifiedActivityUtils.escapeHtml(hashtagSegment.tag);
      parts.add(hashtagPart);
    } else if (segment instanceof ConnectApi.LinkSegment) {
      ConnectApi.LinkSegment linkSegment = (ConnectApi.LinkSegment) segment;
      UnifiedActivityModels.ActivityContentPart linkPart = new UnifiedActivityModels.ActivityContentPart();
      linkPart.partType = 'text';
      linkPart.text =
        '<a href="' +
        linkSegment.url +
        '" target="_blank">' +
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
      namePart.text =
        '<strong>' +
        UnifiedActivityUtils.escapeHtml(nameSegment.text) +
        '</strong>';
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

  @TestVisible
  private List<UnifiedActivityModels.ActivityContentPart> buildTrackedChangesCapabilityParts(
    ConnectApi.FeedItem feedItem
  ) {
    List<UnifiedActivityModels.ActivityContentPart> parts = new List<UnifiedActivityModels.ActivityContentPart>();
    if (
      feedItem.capabilities == null ||
      feedItem.capabilities.trackedChanges == null ||
      feedItem.capabilities.trackedChanges.changes == null
    ) {
      return parts;
    }

    for (
      ConnectApi.TrackedChangeItem changeItem : feedItem.capabilities.trackedChanges.changes
    ) {
      if (String.isNotBlank(changeItem.fieldName)) {
        UnifiedActivityModels.ActivityContentPart namePart = new UnifiedActivityModels.ActivityContentPart();
        namePart.partType = 'text';
        namePart.text =
          '<strong>' +
          UnifiedActivityUtils.escapeHtml(
            UnifiedActivityUtils.formatFieldApiName(changeItem.fieldName)
          ) +
          '</strong>';
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

  @TestVisible
  private Map<String, Id> resolveContentDocumentIds(List<String> versionIds) {
    Map<String, Id> versionToDocumentId = new Map<String, Id>();
    if (versionIds == null || versionIds.isEmpty()) {
      return versionToDocumentId;
    }

    Set<Id> versionIdSet = new Set<Id>();
    for (String versionId : versionIds) {
      versionIdSet.add((Id) versionId);
    }

    for (
      ContentVersion version : selector.queryContentVersionsByIds(versionIdSet)
    ) {
      versionToDocumentId.put(version.Id, version.ContentDocumentId);
    }
    return versionToDocumentId;
  }

  @TestVisible
  private Id extractContentDocumentIdFromImageUrl(String imageUrl) {
    if (String.isBlank(imageUrl)) {
      return null;
    }
    Matcher documentMatcher = Pattern.compile(
        '/document/download/([a-zA-Z0-9]{15,18})'
      )
      .matcher(imageUrl);
    if (documentMatcher.find()) {
      return (Id) documentMatcher.group(1);
    }
    return null;
  }

  @TestVisible
  private String extractVersionIdFromImageUrl(String imageUrl) {
    if (String.isBlank(imageUrl)) {
      return null;
    }
    Matcher queryMatcher = Pattern.compile('versionId=([a-zA-Z0-9]{15,18})')
      .matcher(imageUrl);
    if (queryMatcher.find()) {
      return queryMatcher.group(1);
    }
    Matcher downloadMatcher = Pattern.compile(
        '/version/download/([a-zA-Z0-9]{15,18})'
      )
      .matcher(imageUrl);
    if (downloadMatcher.find()) {
      return downloadMatcher.group(1);
    }
    return null;
  }

  @TestVisible
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

    Matcher idMatcher = Pattern.compile('(?:refid|id)=([a-zA-Z0-9]{15,18})')
      .matcher(normalizedUrl);
    if (idMatcher.find()) {
      return resolveContentDocumentIdFromVersionId(idMatcher.group(1));
    }

    return null;
  }

  @TestVisible
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

    List<ContentVersion> versions = selector.queryContentVersionById(
      versionKey
    );
    return versions.isEmpty() ? null : versions[0].ContentDocumentId;
  }

  @TestVisible
  private Id resolveInlineImageContentDocumentId(
    String imageUrl,
    List<String> imageContentVersionIds,
    Integer imageIndex
  ) {
    if (
      imageContentVersionIds != null &&
      imageIndex < imageContentVersionIds.size() &&
      String.isNotBlank(imageContentVersionIds[imageIndex])
    ) {
      Id fromVersionId = resolveContentDocumentIdFromVersionId(
        imageContentVersionIds[imageIndex]
      );
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
      appendTextSegmentFromHtml(
        segments,
        html.substring(lastEnd, matcher.start())
      );

      String imageUrl = UnifiedActivityUtils.unescapeHtmlAttribute(
        matcher.group(1)
      );
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
      Matcher singleQuoteMatcher = Pattern.compile(
          '(?i)<img[^>]+src=\'([^\']+)\'[^>]*>'
        )
        .matcher(html);
      lastEnd = 0;
      imageIndex = 0;
      segments.clear();

      while (singleQuoteMatcher.find()) {
        appendTextSegmentFromHtml(
          segments,
          html.substring(lastEnd, singleQuoteMatcher.start())
        );

        String imageUrl = UnifiedActivityUtils.unescapeHtmlAttribute(
          singleQuoteMatcher.group(1)
        );
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
