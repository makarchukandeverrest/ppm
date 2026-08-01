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

    private static UnifiedActivityController.ActivityPageResult getActivities(
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

    private static UnifiedActivityController.ActivityPageResult getActivities(
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
        UnifiedActivityController.ActivityPageResult result;
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
        for (UnifiedActivityController.ActivityItem item : result.items) {
            if (item.type == UnifiedActivityController.TYPE_TASK) {
                foundTask = true;
                System.assertEquals('Test Task', item.title);
            }
            if (item.type == UnifiedActivityController.TYPE_EVENT) {
                foundEvent = true;
                System.assertEquals('Test Event', item.title);
            }
            if (item.type == UnifiedActivityController.TYPE_FEED) {
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
        UnifiedActivityController.ActivityPageResult firstPage;
        UnifiedActivityController.ActivityPageResult secondPage;
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

        UnifiedActivityController.ActivityPageResult thirdPage = getActivities(
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
        UnifiedActivityController.ActivityPageResult result;
        System.runAs(u) {
            result = getActivities(acc.Id, 'DESC', 20, 0, UnifiedActivityController.TYPE_TASK, null);
        }
        Test.stopTest();

        System.assertEquals(1, result.totalCount);
        System.assertEquals(UnifiedActivityController.TYPE_TASK, result.items[0].type);
    }

    @IsTest
    static void testGetUnifiedActivities_includesRelatedRecords() {
        Account acc = createTestAccount();
        Contact con = new Contact(LastName = 'Related Activity Test', AccountId = acc.Id);
        insert con;

        insert new Task(WhatId = acc.Id, Subject = 'Account Task', Status = 'Not Started');
        insert new Task(WhoId = con.Id, Subject = 'Contact Task', Status = 'Not Started');

        Test.startTest();
        UnifiedActivityController.ActivityPageResult result = getActivities(
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
        UnifiedActivityController.ActivityPageResult result;
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
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (UnifiedActivityController.IllegalArgumentException ex) {
            System.assertEquals('recordId is required', ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetUnifiedActivities_noRecords() {
        Account acc = createTestAccount();

        Test.startTest();
        UnifiedActivityController.ActivityPageResult result = getActivities(acc.Id, 'DESC', 20, 0, 'All', null);
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
            UnifiedActivityController.createChatterPost(null, 'Hello');
            System.assert(false, 'Expected IllegalArgumentException for null recordId');
        } catch (UnifiedActivityController.IllegalArgumentException ex) {
            System.assertEquals('recordId is required', ex.getMessage());
        }

        try {
            UnifiedActivityController.createChatterPost(acc.Id, null);
            System.assert(false, 'Expected IllegalArgumentException for blank body');
        } catch (UnifiedActivityController.IllegalArgumentException ex) {
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
            UnifiedActivityController.createChatterPost(acc.Id, 'Test post from composer');
        }
        Test.stopTest();

        List<FeedItem> posts = [SELECT Id FROM FeedItem WHERE ParentId = :acc.Id];
        System.assertEquals(1, posts.size(), 'Chatter post should be created');
    }
}
