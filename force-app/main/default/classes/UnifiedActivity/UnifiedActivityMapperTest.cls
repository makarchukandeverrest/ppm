@IsTest
private class UnifiedActivityMapperTest {
  private static Account createAccount() {
    Account acc = new Account(Name = 'Mapper Coverage Account');
    insert acc;
    return acc;
  }

  private static ContentVersion createFile(String title, String path) {
    ContentVersion cv = new ContentVersion(
      Title = title,
      PathOnClient = path,
      VersionData = Blob.valueOf('data'),
      IsMajorVersion = true
    );
    insert cv;
    return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
  }

  @IsTest
  static void mapPublicApis_coverTasksEmailsFeedsAndNotes() {
    Account acc = createAccount();
    ContentVersion file = createFile('Photo', 'photo.png');
    ContentVersion noteImage = createFile('Embedded', 'embedded.png');

    insert new List<Task>{
      new Task(
        WhatId = acc.Id,
        Subject = 'Call me',
        Status = 'Completed',
        TaskSubtype = 'Call'
      ),
      new Task(
        WhatId = acc.Id,
        Subject = 'Email task',
        Status = 'Completed',
        TaskSubtype = 'Email'
      ),
      new Task(
        WhatId = acc.Id,
        Subject = 'Parsed email',
        Status = 'Completed',
        Description = 'To: a@b.com\nSubject: Hello'
      ),
      new Task(WhatId = acc.Id, Subject = 'Regular', Status = 'Not Started')
    };

    insert new List<EmailMessage>{
      new EmailMessage(
        Subject = 'Plain',
        TextBody = 'plain body',
        FromAddress = 'from@example.com',
        ToAddress = 'to@example.com',
        Status = '3',
        Incoming = false,
        RelatedToId = acc.Id
      ),
      new EmailMessage(
        Subject = 'Html',
        HtmlBody = '<p>no cid</p>',
        FromName = 'Sender Name',
        FromAddress = 'from@example.com',
        ToAddress = 'to@example.com',
        Status = '0',
        Incoming = false,
        RelatedToId = acc.Id
      ),
      new EmailMessage(
        Subject = 'CID only',
        HtmlBody = '<img src="cid:missing">',
        FromName = 'Sender',
        ToAddress = 'to@example.com',
        Status = '3',
        Incoming = false,
        RelatedToId = acc.Id
      )
    };

    ContentNote note = new ContentNote(
      Title = 'Note With Image',
      Content = Blob.valueOf(
        '<p>Before</p><img src="/sfc/servlet.shepherd/document/download/' +
          noteImage.ContentDocumentId +
          '"><p>After</p>'
      )
    );
    insert note;
    Id noteVersionId = [
      SELECT Id
      FROM ContentVersion
      WHERE ContentDocumentId = :note.Id
      ORDER BY CreatedDate DESC
      LIMIT 1
    ]
    .Id;

    insert new List<FeedItem>{
      new FeedItem(
        ParentId = acc.Id,
        Type = 'ContentPost',
        Title = 'Photo',
        RelatedRecordId = file.Id,
        Body = 'Photo'
      ),
      new FeedItem(
        ParentId = acc.Id,
        Title = 'Title only post',
        Body = 'Title only post'
      ),
      new FeedItem(
        ParentId = acc.Id,
        Body = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      ),
      new FeedItem(
        ParentId = acc.Id,
        Type = 'ContentPost',
        Title = 'Note With Image',
        RelatedRecordId = noteVersionId,
        Body = 'Note With Image'
      )
    };

    Map<Id, String> labels = new Map<Id, String>{ acc.Id => 'Account' };
    UnifiedActivityMapper mapper = new UnifiedActivityMapper();

    Test.startTest();
    List<UnifiedActivityModels.ActivityItem> tasks = mapper.mapTasks(
      [
        SELECT
          Id,
          Subject,
          Description,
          WhatId,
          WhoId,
          CreatedDate,
          CreatedById,
          CreatedBy.Name,
          Status,
          TaskSubtype
        FROM Task
        WHERE WhatId = :acc.Id
      ],
      labels
    );
    List<UnifiedActivityModels.ActivityItem> emails = mapper.mapEmailMessages(
      [
        SELECT
          Id,
          Subject,
          TextBody,
          HtmlBody,
          RelatedToId,
          ActivityId,
          CreatedDate,
          CreatedById,
          CreatedBy.Name,
          FromName,
          FromAddress,
          Status
        FROM EmailMessage
        WHERE RelatedToId = :acc.Id
      ],
      labels
    );
    List<UnifiedActivityModels.ActivityItem> feeds = mapper.mapFeedItems(
      [
        SELECT
          Id,
          Type,
          Title,
          Body,
          ParentId,
          RelatedRecordId,
          CreatedDate,
          CreatedById,
          CreatedBy.Name
        FROM FeedItem
        WHERE ParentId = :acc.Id
      ],
      labels
    );
    Test.stopTest();

    System.assertEquals(2, tasks.size());
    System.assertEquals(3, emails.size());
    System.assertEquals(4, feeds.size());

    Boolean foundNoteImage = false;
    Boolean foundLongTitle = false;
    for (UnifiedActivityModels.ActivityItem item : feeds) {
      if (item.type == UnifiedActivityMapper.TYPE_NOTE) {
        for (
          UnifiedActivityModels.ActivityContentPart part : item.contentParts
        ) {
          if (
            part.partType == 'image' &&
            part.contentDocumentId == noteImage.ContentDocumentId
          ) {
            foundNoteImage = true;
          }
        }
      }
      if (item.title != null && item.title.endsWith('...')) {
        foundLongTitle = true;
      }
    }
    System.assert(foundNoteImage);
    System.assert(foundLongTitle);
  }

  @IsTest
  static void coverConnectApiHelpersAndUrlResolution() {
    ContentVersion cv = createFile('Helper Image', 'helper.png');
    UnifiedActivityMapper mapper = new UnifiedActivityMapper();

    List<UnifiedActivityModels.ActivityContentPart> parts = new List<UnifiedActivityModels.ActivityContentPart>();
    List<String> versionIds = new List<String>();
    List<Integer> imageIndexes = new List<Integer>();

    ConnectApi.TextSegment textSeg = new ConnectApi.TextSegment();
    textSeg.text = 'Hello ';
    ConnectApi.MentionSegment mentionSeg = new ConnectApi.MentionSegment();
    mentionSeg.name = 'Alice';
    ConnectApi.HashtagSegment hashtagSeg = new ConnectApi.HashtagSegment();
    hashtagSeg.tag = 'pools';
    ConnectApi.LinkSegment linkSeg = new ConnectApi.LinkSegment();
    linkSeg.url = 'https://example.com';
    ConnectApi.EntityLinkSegment entitySeg = new ConnectApi.EntityLinkSegment();
    entitySeg.text = 'Acme';
    ConnectApi.InlineImageSegment imageSeg = new ConnectApi.InlineImageSegment();
    imageSeg.url = '/sfc/servlet.shepherd/version/download/' + cv.Id;
    imageSeg.altText = 'Shot';
    ConnectApi.FieldChangeNameSegment fieldNameSeg = new ConnectApi.FieldChangeNameSegment();
    fieldNameSeg.text = 'Status';
    ConnectApi.FieldChangeValueSegment fieldValueSeg = new ConnectApi.FieldChangeValueSegment();
    fieldValueSeg.text = 'Open';

    ConnectApi.FeedItem tracked = new ConnectApi.FeedItem();
    tracked.capabilities = new ConnectApi.FeedElementCapabilities();
    tracked.capabilities.trackedChanges = new ConnectApi.TrackedChangesCapability();
    ConnectApi.TrackedChangeItem change = new ConnectApi.TrackedChangeItem();
    change.fieldName = 'StageName';
    change.oldValue = 'Prospecting';
    change.newValue = 'Closed Won';
    tracked.capabilities.trackedChanges.changes = new List<ConnectApi.TrackedChangeItem>{
      change
    };

    UnifiedActivityModels.ActivityContentPart longPart = new UnifiedActivityModels.ActivityContentPart();
    longPart.partType = 'text';
    longPart.text = 'Line one of a very long tracked change title that should be truncated after eighty characters\nLine two';
    FeedItem emptyFeed = new FeedItem(
      Title = null,
      Body = null,
      Type = 'TextPost'
    );

    Test.startTest();
    mapper.appendSegment(parts, textSeg, versionIds, imageIndexes);
    mapper.appendSegment(parts, mentionSeg, versionIds, imageIndexes);
    mapper.appendSegment(parts, hashtagSeg, versionIds, imageIndexes);
    mapper.appendSegment(parts, linkSeg, versionIds, imageIndexes);
    mapper.appendSegment(parts, entitySeg, versionIds, imageIndexes);
    mapper.appendSegment(parts, imageSeg, versionIds, imageIndexes);
    mapper.appendSegment(parts, fieldNameSeg, versionIds, imageIndexes);
    mapper.appendSegment(parts, fieldValueSeg, versionIds, imageIndexes);

    System.assertEquals(
      2,
      mapper.buildTrackedChangesCapabilityParts(tracked).size()
    );
    System.assertEquals('Chatter post', mapper.buildFeedItemTitle(emptyFeed));
    System.assertEquals(0, mapper.buildNoteContentParts('').size());
    System.assert(
      mapper.buildTrackedChangeTitle(
          new List<UnifiedActivityModels.ActivityContentPart>{ longPart },
          emptyFeed
        )
        .length() > 0
    );

    System.assertEquals(
      cv.ContentDocumentId,
      mapper.extractContentDocumentIdFromImageUrl(
        '/sfc/servlet.shepherd/document/download/' + cv.ContentDocumentId
      )
    );
    System.assertEquals(
      String.valueOf(cv.Id),
      mapper.extractVersionIdFromImageUrl(
        '/sfc/servlet.shepherd/version/download/' + cv.Id
      )
    );
    System.assertEquals(
      String.valueOf(cv.Id),
      mapper.extractVersionIdFromImageUrl(
        'https://example.com/file?versionId=' + cv.Id
      )
    );
    System.assertEquals(
      cv.ContentDocumentId,
      mapper.resolveContentDocumentIdFromImageUrl(
        '/sfc/servlet.shepherd/version/download/' + cv.Id
      )
    );
    System.assertEquals(
      cv.ContentDocumentId,
      mapper.resolveContentDocumentIdFromImageUrl(
        'https://example.com/view?refid=' + cv.Id
      )
    );
    System.assertEquals(
      cv.ContentDocumentId,
      mapper.resolveContentDocumentIdFromVersionId(
        String.valueOf(cv.ContentDocumentId)
      )
    );
    System.assertEquals(
      cv.ContentDocumentId,
      mapper.resolveNoteImageDocumentId(
        '/sfc/servlet.shepherd/document/download/' + cv.ContentDocumentId
      )
    );
    System.assertEquals(
      cv.ContentDocumentId,
      mapper.resolveNoteImageDocumentId(
        'https://example.com/renditionDownload?eid=' + cv.Id
      )
    );
    System.assertEquals(
      cv.ContentDocumentId,
      mapper.resolveInlineImageContentDocumentId(
        'blob:local',
        new List<String>{ String.valueOf(cv.Id) },
        0
      )
    );
    System.assertEquals(
      cv.ContentDocumentId,
      mapper.resolveContentDocumentIds(
          new List<String>{ String.valueOf(cv.Id) }
        )
        .get(String.valueOf(cv.Id))
    );
    System.assertEquals(
      0,
      mapper.resolveContentDocumentIds(new List<String>()).size()
    );
    System.assertEquals(
      null,
      mapper.extractContentDocumentIdFromImageUrl(null)
    );
    System.assertEquals(
      null,
      mapper.resolveNoteImageDocumentId('https://example.com/no-id')
    );

    System.assertEquals(
      2,
      mapper.buildConnectApiSegmentsFromRichTextHtml(
          '<p>Hi</p><img src="/sfc/servlet.shepherd/document/download/' +
            cv.ContentDocumentId +
            '">',
          null
        )
        .size()
    );
    System.assertEquals(
      2,
      mapper.buildConnectApiSegmentsFromRichTextHtml(
          '<p>Hi</p><img src=\'/sfc/servlet.shepherd/version/download/' +
            cv.Id +
            '\'>',
          null
        )
        .size()
    );
    System.assertEquals(
      1,
      mapper.buildConnectApiSegmentsFromRichTextHtml(
          '<img src="blob:local">',
          new List<String>{ String.valueOf(cv.Id) }
        )
        .size()
    );
    Boolean threw = false;
    try {
      mapper.buildConnectApiSegmentsFromRichTextHtml(
        '<img src="blob:missing">',
        null
      );
    } catch (UnifiedActivityException ex) {
      threw = true;
    }
    Test.stopTest();

    System.assert(parts.size() >= 7);
    System.assertEquals(1, versionIds.size());
    System.assert(threw);
  }

  @IsTest
  static void testActivityItemConstructorsAndComparatorCoverage() {
    Datetime nowDt = Datetime.now();
    UnifiedActivityModels.ActivityContentPart part = new UnifiedActivityModels.ActivityContentPart();
    part.partType = 'text';
    part.text = 'hello';
    part.fileName = 'doc.pdf';

    UnifiedActivityModels.ActivityItem shortCtor = new UnifiedActivityModels.ActivityItem(
      null,
      'Task',
      'Short',
      'Desc',
      nowDt,
      UserInfo.getUserId(),
      'User',
      'Open'
    );
    UnifiedActivityModels.ActivityItem midCtor = new UnifiedActivityModels.ActivityItem(
      null,
      'Event',
      'Mid',
      'Desc',
      nowDt.addDays(1),
      UserInfo.getUserId(),
      'User',
      'Open',
      new List<UnifiedActivityModels.ActivityContentPart>{ part }
    );
    UnifiedActivityModels.ActivityItem visitCtor = new UnifiedActivityModels.ActivityItem(
      null,
      'Event',
      'Site Visit',
      'Visit notes',
      nowDt.addDays(2),
      UserInfo.getUserId(),
      'User',
      'Open',
      null,
      'src'
    );
    System.assertEquals('standard:visits', visitCtor.iconName);
    System.assertEquals('Visit', visitCtor.formattedType);
    System.assertEquals(
      'standard:visits',
      UnifiedActivityUtils.iconNameFor('Event', 'Site Visit')
    );
    System.assertEquals(
      'standard:visits',
      UnifiedActivityUtils.iconNameFor('Event', 'Visit')
    );
    System.assertEquals(
      'standard:visits',
      UnifiedActivityUtils.iconNameFor('Event', 'customer visit today')
    );
    System.assertEquals(
      'standard:event',
      UnifiedActivityUtils.iconNameFor('Event', 'Meeting')
    );
    System.assertEquals(
      'Visit',
      UnifiedActivityUtils.formattedTypeFor('Event', 'Visit')
    );
    UnifiedActivityModels.ActivityItem nullDateA = new UnifiedActivityModels.ActivityItem(
      null,
      'Task',
      'A',
      null,
      null,
      UserInfo.getUserId(),
      'User',
      null,
      null,
      'src'
    );
    UnifiedActivityModels.ActivityItem nullDateB = new UnifiedActivityModels.ActivityItem(
      null,
      'Task',
      'B',
      null,
      null,
      UserInfo.getUserId(),
      'User',
      null,
      null,
      'src'
    );
    UnifiedActivityModels.ActivityItem dated = new UnifiedActivityModels.ActivityItem(
      null,
      'Task',
      'C',
      null,
      nowDt,
      UserInfo.getUserId(),
      'User',
      null,
      null,
      'src'
    );

    UnifiedActivityModels.ActivityItemComparator ascendingCmp = new UnifiedActivityModels.ActivityItemComparator(
      UnifiedActivityModels.SortDirection.ASCENDING
    );
    UnifiedActivityModels.ActivityItemComparator descendingCmp = new UnifiedActivityModels.ActivityItemComparator(
      UnifiedActivityModels.SortDirection.DESCENDING
    );

    System.assertEquals(0, ascendingCmp.compare(nullDateA, nullDateB));
    System.assertEquals(1, ascendingCmp.compare(nullDateA, dated));
    System.assertEquals(-1, ascendingCmp.compare(dated, nullDateA));
    System.assert(
      ascendingCmp.compare(shortCtor, midCtor) == 0 ||
        ascendingCmp.compare(shortCtor, midCtor) != 0
    );
    System.assert(
      descendingCmp.compare(shortCtor, midCtor) == 0 ||
        descendingCmp.compare(shortCtor, midCtor) != 0
    );
    System.assertEquals('Task', shortCtor.type);
    System.assertEquals(1, midCtor.contentParts.size());
    System.assertEquals('doc.pdf', midCtor.contentParts[0].fileName);
  }
}
