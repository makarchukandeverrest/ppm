@IsTest
public class UnifiedActivityControllerTest {

    private static User createTestUser() {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String uniqueId = String.valueOf(Datetime.now().getTime()) + Crypto.getRandomInteger();
        String alias = 'tua' + uniqueId.left(5);
        User u = new User(
            FirstName = 'Test',
            LastName = 'UnifiedActivity',
            Alias = alias.left(8),
            Email = alias + '@test.com',
            Username = alias + uniqueId + '@test.com',
            CommunityNickname = alias + uniqueId.left(10),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    private static Account createTestAccount() {
        Account acc = new Account(Name = 'Unified Activity Test');
        insert acc;
        return acc;
    }

    private static UnifiedActivityModels.ActivityPageResult getActivities(
        Id recordId,
        String sortDirection,
        Integer pageSize,
        Integer offset,
        String activityType,
        String searchTerm
    ) {
        return getActivities(
            recordId,
            sortDirection,
            pageSize,
            offset,
            activityType,
            searchTerm,
            null,
            null
        );
    }

    private static UnifiedActivityModels.ActivityPageResult getActivities(
        Id recordId,
        String sortDirection,
        Integer pageSize,
        Integer offset,
        String activityType,
        String searchTerm,
        String relatedRecordConfig,
        String currentRecordLabel
    ) {
        return UnifiedActivityController.getUnifiedActivities(
            recordId,
            sortDirection,
            pageSize,
            offset,
            activityType,
            searchTerm,
            relatedRecordConfig,
            currentRecordLabel
        );
    }

    @IsTest
    static void testGetUnifiedActivities_returnsAllTypes() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();

            Task t = new Task(WhatId = acc.Id, Subject = 'Test Task', Status = 'Not Started');
            insert t;

            Event e = new Event(
                WhatId = acc.Id,
                Subject = 'Test Event',
                StartDateTime = Datetime.now().addHours(1),
                EndDateTime = Datetime.now().addHours(2),
                DurationInMinutes = 60
            );
            insert e;

            FeedItem fi = new FeedItem(ParentId = acc.Id, Body = 'Test Chatter post');
            insert fi;
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'DESC', 20, 0, 'All', null);
        }
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(3, result.totalCount, 'Expected Task, Event and FeedItem');
        System.assertEquals(3, result.items.size(), 'First page should include all records');

        Boolean foundTask = false;
        Boolean foundEvent = false;
        Boolean foundFeed = false;
        for (UnifiedActivityModels.ActivityItem item : result.items) {
            if (item.type == UnifiedActivityMapper.TYPE_TASK) {
                foundTask = true;
                System.assertEquals('Test Task', item.title);
            }
            if (item.type == UnifiedActivityMapper.TYPE_EVENT) {
                foundEvent = true;
                System.assertEquals('Test Event', item.title);
            }
            if (item.type == UnifiedActivityMapper.TYPE_FEED) {
                foundFeed = true;
                System.assert(!item.contentParts.isEmpty(), 'Feed item should have content parts');
                System.assertEquals('text', item.contentParts[0].partType);
                System.assertEquals('Test Chatter post', item.contentParts[0].text);
            }
        }
        System.assert(foundTask, 'Task should be present');
        System.assert(foundEvent, 'Event should be present');
        System.assert(foundFeed, 'FeedItem should be present');
    }

    @IsTest
    static void testGetUnifiedActivities_pagination() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();
            for (Integer index = 0; index < 5; index++) {
                insert new Task(
                    WhatId = acc.Id,
                    Subject = 'Task ' + index,
                    Status = 'Not Started'
                );
            }
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult firstPage;
        UnifiedActivityModels.ActivityPageResult secondPage;
        System.runAs(u) {
            firstPage = getActivities(acc.Id, 'DESC', 2, 0, 'All', null);
            secondPage = getActivities(acc.Id, 'DESC', 2, firstPage.nextOffset, 'All', null);
        }
        Test.stopTest();

        System.assertEquals(5, firstPage.totalCount);
        System.assertEquals(2, firstPage.items.size());
        System.assertEquals(true, firstPage.hasMore);
        System.assertEquals(2, secondPage.items.size());
        System.assertEquals(true, secondPage.hasMore);

        UnifiedActivityModels.ActivityPageResult thirdPage = getActivities(
            acc.Id,
            'DESC',
            2,
            secondPage.nextOffset,
            'All',
            null
        );
        System.assertEquals(1, thirdPage.items.size());
        System.assertEquals(false, thirdPage.hasMore);
    }

    @IsTest
    static void testGetUnifiedActivities_filtersByType() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();
            insert new Task(WhatId = acc.Id, Subject = 'Only Task', Status = 'Not Started');
            insert new FeedItem(ParentId = acc.Id, Body = 'Only Feed');
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'DESC', 20, 0, UnifiedActivityMapper.TYPE_TASK, null);
        }
        Test.stopTest();

        System.assertEquals(1, result.totalCount);
        System.assertEquals(UnifiedActivityMapper.TYPE_TASK, result.items[0].type);
    }

    @IsTest
    static void testGetUnifiedActivities_includesRelatedRecords() {
        Account acc = createTestAccount();
        Contact con = new Contact(LastName = 'Related Activity Test', AccountId = acc.Id);
        insert con;

        insert new Task(WhatId = acc.Id, Subject = 'Account Task', Status = 'Not Started');
        insert new Task(WhoId = con.Id, Subject = 'Contact Task', Status = 'Not Started');

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result = getActivities(
            con.Id,
            'DESC',
            20,
            0,
            'All',
            null,
            'AccountId:Account',
            'Contact'
        );
        Test.stopTest();

        System.assertEquals(2, result.totalCount, 'Should include Contact and Account activities');
    }

    @IsTest
    static void testGetUnifiedActivities_sortsDescending() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();
            Task t1 = new Task(WhatId = acc.Id, Subject = 'Older', Status = 'Not Started');
            insert t1;
            Task t2 = new Task(WhatId = acc.Id, Subject = 'Newer', Status = 'Not Started');
            insert t2;
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'DESC', 20, 0, 'All', null);
        }
        Test.stopTest();

        System.assert(result.items[0].createdDate >= result.items[1].createdDate, 'Descending sort should put newest first');
    }

    @IsTest
    static void testGetUnifiedActivities_emptyRecord() {
        Test.startTest();
        try {
            getActivities(null, 'DESC', 20, 0, 'All', null);
            System.assert(false, 'Expected UnifiedActivityException');
        } catch (UnifiedActivityException ex) {
            System.assertEquals('recordId is required', ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetUnifiedActivities_noRecords() {
        Account acc = createTestAccount();

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result = getActivities(acc.Id, 'DESC', 20, 0, 'All', null);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(0, result.totalCount);
        System.assertEquals(0, result.items.size());
        System.assertEquals(false, result.hasMore);
    }

    @IsTest
    static void testCreateChatterPost_validation() {
        Account acc = createTestAccount();

        Test.startTest();
        try {
            UnifiedActivityController.createChatterPost(null, 'Hello', null);
            System.assert(false, 'Expected UnifiedActivityException for null recordId');
        } catch (UnifiedActivityException ex) {
            System.assertEquals('recordId is required', ex.getMessage());
        }

        try {
            UnifiedActivityController.createChatterPost(acc.Id, null, null);
            System.assert(false, 'Expected UnifiedActivityException for blank body');
        } catch (UnifiedActivityException ex) {
            System.assertEquals('body is required', ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateChatterPost_success() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();
        }

        Test.startTest();
        System.runAs(u) {
            UnifiedActivityController.createChatterPost(acc.Id, 'Test post from composer', null);
        }
        Test.stopTest();

        List<FeedItem> posts = [SELECT Id, IsRichText FROM FeedItem WHERE ParentId = :acc.Id];
        System.assertEquals(1, posts.size(), 'Chatter post should be created');
        System.assertEquals(true, posts[0].IsRichText, 'Post should be rich text');
    }

    @IsTest
    static void testCreateChatterPost_richText() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();
        }

        Test.startTest();
        System.runAs(u) {
            UnifiedActivityController.createChatterPost(
                acc.Id,
                '<p><strong>Bold</strong> and <em>italic</em></p>',
                null
            );
        }
        Test.stopTest();

        FeedItem post = [
            SELECT Id, Body, IsRichText
            FROM FeedItem
            WHERE ParentId = :acc.Id
            LIMIT 1
        ];
        System.assertEquals(true, post.IsRichText);
        System.assert(post.Body.contains('Bold'), 'Rich text body should be preserved');
    }

    @IsTest
    static void testGetUnifiedActivities_emailAttachmentCount() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();

            EmailMessage emailMessage = new EmailMessage(
                Subject = 'Email with attachment',
                FromName = 'Stephanie Pratt',
                FromAddress = 'sender@example.com',
                ToAddress = 'recipient@example.com',
                TextBody = 'Body',
                Status = '3',
                Incoming = false,
                RelatedToId = acc.Id
            );
            insert emailMessage;

            ContentVersion contentVersion = new ContentVersion(
                Title = 'Attachment.pdf',
                PathOnClient = 'Attachment.pdf',
                VersionData = Blob.valueOf('pdf'),
                IsMajorVersion = true
            );
            insert contentVersion;

            contentVersion = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersion.Id
                LIMIT 1
            ];

            insert new ContentDocumentLink(
                ContentDocumentId = contentVersion.ContentDocumentId,
                LinkedEntityId = emailMessage.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'DESC', 20, 0, UnifiedActivityMapper.TYPE_EMAIL, null);
        }
        Test.stopTest();

        System.assertEquals(1, result.items.size(), 'Expected one email activity');
        System.assertEquals(
            UnifiedActivityMapper.TYPE_EMAIL,
            result.items[0].type
        );
        System.assertEquals(1, result.items[0].attachmentCount, 'Email should report one attachment');
        System.assertEquals(
            'Stephanie Pratt',
            result.items[0].createdByName,
            'Email activity should show FromName, not CreatedBy'
        );
    }

    @IsTest
    static void testGetUnifiedActivities_emailFallsBackToFromAddress() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();
            insert new EmailMessage(
                Subject = 'Email without from name',
                FromAddress = 'sender@example.com',
                ToAddress = 'recipient@example.com',
                TextBody = 'Body',
                Status = '3',
                Incoming = false,
                RelatedToId = acc.Id
            );
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'DESC', 20, 0, UnifiedActivityMapper.TYPE_EMAIL, null);
        }
        Test.stopTest();

        System.assertEquals(1, result.items.size(), 'Expected one email activity');
        System.assertEquals(
            'sender@example.com',
            result.items[0].createdByName,
            'Email activity should fall back to FromAddress when FromName is blank'
        );
    }

    @IsTest
    static void testGetUnifiedActivities_ascendingSort() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();
            insert new Task(WhatId = acc.Id, Subject = 'Older', Status = 'Not Started');
            insert new Task(WhatId = acc.Id, Subject = 'Newer', Status = 'Not Started');
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'ASC', 20, 0, 'All', null);
        }
        Test.stopTest();

        System.assert(result.items[0].createdDate <= result.items[1].createdDate, 'Ascending sort should put oldest first');
    }

    @IsTest
    static void testGetUnifiedActivities_searchTerm() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();
            insert new Task(WhatId = acc.Id, Subject = 'Match me', Status = 'Not Started');
            insert new Task(WhatId = acc.Id, Subject = 'Something else', Status = 'Not Started');
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'DESC', 20, 0, 'All', 'Match me');
        }
        Test.stopTest();

        System.assertEquals(1, result.totalCount, 'Search should filter to one matching task');
        System.assertEquals('Match me', result.items[0].title);
    }

    @IsTest
    static void testGetUnifiedActivities_invalidRelatedRecordConfig() {
        Account acc = createTestAccount();
        Contact con = new Contact(LastName = 'Invalid Config Test', AccountId = acc.Id);
        insert con;
        insert new Task(WhatId = acc.Id, Subject = 'Account Task', Status = 'Not Started');

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result = getActivities(
            con.Id,
            'DESC',
            20,
            0,
            'All',
            null,
            'Name:Name,AccountId:Account',
            'Contact'
        );
        Test.stopTest();

        System.assertEquals(1, result.totalCount, 'Should ignore invalid non-lookup field and use valid AccountId');
    }

    @IsTest
    static void testGetUnifiedActivities_offsetBeyondRange() {
        Account acc = createTestAccount();
        insert new Task(WhatId = acc.Id, Subject = 'Only', Status = 'Not Started');

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result = getActivities(acc.Id, 'DESC', 20, 100, 'All', null);
        Test.stopTest();

        System.assertEquals(1, result.totalCount);
        System.assertEquals(0, result.items.size());
        System.assertEquals(false, result.hasMore);
        System.assertEquals(100, result.nextOffset);
    }

    @IsTest
    static void testGetUnifiedActivities_emailLikeTask() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();
            insert new Task(
                WhatId = acc.Id,
                Subject = 'Email Task',
                Description = 'To: someone@example.com\nSubject: hello',
                Status = 'Not Started'
            );
            insert new Task(WhatId = acc.Id, Subject = 'Normal Task', Status = 'Not Started');
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'DESC', 20, 0, 'All', null);
        }
        Test.stopTest();

        System.assertEquals(1, result.totalCount, 'Email-like task should be excluded');
        System.assertEquals('Normal Task', result.items[0].title);
    }

    @IsTest(SeeAllData=true)
    static void testGetUnifiedActivities_contentPost() {
        User u = createTestUser();
        Account acc;
        ContentVersion cv;
        System.runAs(u) {
            acc = createTestAccount();
            cv = new ContentVersion(
                Title = 'Test File',
                PathOnClient = 'test.txt',
                VersionData = Blob.valueOf('data'),
                IsMajorVersion = true
            );
            insert cv;
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        }

        ConnectApi.FeedItemInput input = new ConnectApi.FeedItemInput();
        input.subjectId = acc.Id;
        input.feedElementType = ConnectApi.FeedElementType.FeedItem;

        ConnectApi.FilesCapabilityInput filesInput = new ConnectApi.FilesCapabilityInput();
        filesInput.items = new List<ConnectApi.FileIdInput>();
        ConnectApi.FileIdInput fileIdInput = new ConnectApi.FileIdInput();
        fileIdInput.id = cv.ContentDocumentId;
        filesInput.items.add(fileIdInput);

        input.capabilities = new ConnectApi.FeedElementCapabilitiesInput();
        input.capabilities.files = filesInput;

        Test.startTest();
        System.runAs(u) {
            ConnectApi.ChatterFeeds.postFeedElement(null, input);
        }
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'DESC', 20, 0, 'All', null);
        }
        Test.stopTest();

        System.assertEquals(1, result.totalCount);
        System.assertEquals('Test File', result.items[0].title);
        System.assert(!result.items[0].contentParts.isEmpty(), 'ContentPost should have image part');
        System.assertEquals('image', result.items[0].contentParts[0].partType);
    }

    @IsTest
    static void testGetUnifiedActivities_richTextFeed() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();
            FeedItem fi = new FeedItem(
                ParentId = acc.Id,
                Body = '<p>Hello <a href="http://example.com">link</a></p>',
                IsRichText = true
            );
            insert fi;
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'DESC', 20, 0, 'All', null);
        }
        Test.stopTest();

        System.assertEquals(1, result.totalCount);
        System.assert(!result.items[0].contentParts.isEmpty(), 'Rich text feed should have content parts');
    }

    @IsTest(SeeAllData=true)
    static void testCreateChatterPost_withInlineImage() {
        User u = createTestUser();
        Account acc;
        ContentVersion cv;
        System.runAs(u) {
            acc = createTestAccount();
            cv = new ContentVersion(
                Title = 'Inline Image',
                PathOnClient = 'img.png',
                VersionData = Blob.valueOf('PNG'),
                IsMajorVersion = true
            );
            insert cv;
        }
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        System.runAs(u) {
            UnifiedActivityController.createChatterPost(
                acc.Id,
                '<p>Hello <img src="sfdc://' + cv.ContentDocumentId + '"></p>',
                new List<String>{ cv.ContentDocumentId }
            );
        }
        Test.stopTest();

        List<FeedItem> posts = [SELECT Id FROM FeedItem WHERE ParentId = :acc.Id];
        System.assertEquals(1, posts.size(), 'Chatter post with inline image should be created');
    }

    @IsTest
    static void testGetUnifiedActivities_htmlEmailWithCid() {
        User u = createTestUser();
        Account acc;
        System.runAs(u) {
            acc = createTestAccount();
            EmailMessage em = new EmailMessage(
                Subject = 'HTML email',
                FromAddress = 'sender@example.com',
                ToAddress = 'recipient@example.com',
                HtmlBody = '<p>Image <img src="cid:abc123"></p>',
                Status = '3',
                Incoming = false,
                RelatedToId = acc.Id
            );
            insert em;

            ContentVersion cv = new ContentVersion(
                Title = 'Email Attachment',
                PathOnClient = 'att.png',
                VersionData = Blob.valueOf('PNG'),
                IsMajorVersion = true
            );
            insert cv;
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
            insert new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = em.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'DESC', 20, 0, UnifiedActivityMapper.TYPE_EMAIL, null);
        }
        Test.stopTest();

        System.assertEquals(1, result.items.size(), 'Expected one email activity');
        System.assert(result.items[0].description.contains('version/download/'), 'CID reference should be replaced');
    }

    @IsTest
    static void testGetUnifiedActivities_includesEmailsRelatedViaAccountContacts() {
        User u = createTestUser();
        Account customer;
        Contact customerContact;
        EmailMessage platformEmail;
        System.runAs(u) {
            customer = createTestAccount();
            customerContact = new Contact(
                LastName = 'Customer Contact',
                Email = 'customer.contact.' + String.valueOf(Crypto.getRandomInteger()) + '@example.com',
                AccountId = customer.Id
            );
            insert customerContact;

            Account unrelatedAccount = new Account(Name = 'Unrelated Email Parent');
            insert unrelatedAccount;

            platformEmail = new EmailMessage(
                Subject = 'Platform thread reply',
                FromAddress = 'sender@example.com',
                ToAddress = customerContact.Email,
                TextBody = 'Filed on an email thread, not the customer record',
                Status = '3',
                Incoming = false,
                RelatedToId = unrelatedAccount.Id
            );
            insert platformEmail;
            ensureEmailMessageRelation(platformEmail.Id, customerContact.Id);
        }

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(customer.Id, 'DESC', 20, 0, UnifiedActivityMapper.TYPE_EMAIL, null);
        }
        Test.stopTest();

        System.assertEquals(1, result.totalCount, 'Account feed should include emails related via customer contacts');
        System.assertEquals(platformEmail.Id, result.items[0].id);
        System.assertEquals('Platform thread reply', result.items[0].title);
    }

    @IsTest
    static void testGetUnifiedActivities_includesContactEmailsOnContractBid() {
        Account customer = createTestAccount();
        Contact customerContact = new Contact(
            LastName = 'Bid Contact',
            Email = 'bid.contact.' + String.valueOf(Crypto.getRandomInteger()) + '@example.com',
            AccountId = customer.Id
        );
        insert customerContact;

        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'Unified Bid Email Test',
            Customer__c = customer.Id,
            Stage__c = 'Information Verified'
        );
        insert bid;

        Email_Platform__Email_Thread__c thread = new Email_Platform__Email_Thread__c(
            Email_Platform__Thread_Identifier__c = 'unified-activity-' + String.valueOf(Crypto.getRandomInteger()),
            Email_Platform__Subject__c = 'Premier Pool Management',
            Email_Platform__From_Address__c = 'sender@example.com',
            Email_Platform__Recipient__c = customerContact.Id
        );
        insert thread;

        EmailMessage platformEmail = new EmailMessage(
            Subject = 'Re: Premier Pool Management',
            FromAddress = 'sender@example.com',
            ToAddress = customerContact.Email,
            TextBody = 'Reply filed on email thread',
            Status = '1',
            Incoming = false,
            RelatedToId = thread.Id
        );
        insert platformEmail;
        ensureEmailMessageRelation(platformEmail.Id, customerContact.Id);

        Test.startTest();
        UnifiedActivityModels.ActivityPageResult result = getActivities(
            bid.Id,
            'DESC',
            20,
            0,
            UnifiedActivityMapper.TYPE_EMAIL,
            null,
            'Customer__c:Customer',
            'Contract Bid'
        );
        Test.stopTest();

        System.assertEquals(1, result.totalCount, 'Contract Bid feed should include Email Platform replies for customer contacts');
        System.assertEquals(platformEmail.Id, result.items[0].id);
        System.assertEquals('Re: Premier Pool Management', result.items[0].title);
    }

    private static void ensureEmailMessageRelation(Id emailMessageId, Id relationId) {
        List<EmailMessageRelation> existing = [
            SELECT Id
            FROM EmailMessageRelation
            WHERE EmailMessageId = :emailMessageId AND RelationId = :relationId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return;
        }
        insert new EmailMessageRelation(
            EmailMessageId = emailMessageId,
            RelationId = relationId,
            RelationType = 'ToAddress'
        );
    }
}