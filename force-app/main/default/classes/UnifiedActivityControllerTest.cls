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
        List<UnifiedActivityController.ActivityItem> result;
        System.runAs(u) {
            result = UnifiedActivityController.getUnifiedActivities(acc.Id, 'DESC');
        }
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(3, result.size(), 'Expected Task, Event and FeedItem');

        Boolean foundTask = false;
        Boolean foundEvent = false;
        Boolean foundFeed = false;
        for (UnifiedActivityController.ActivityItem item : result) {
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
        List<UnifiedActivityController.ActivityItem> result;
        System.runAs(u) {
            result = UnifiedActivityController.getUnifiedActivities(acc.Id, 'DESC');
        }
        Test.stopTest();

        System.assert(result[0].createdDate >= result[1].createdDate, 'Descending sort should put newest first');
    }

    @IsTest
    static void testGetUnifiedActivities_emptyRecord() {
        Test.startTest();
        try {
            UnifiedActivityController.getUnifiedActivities(null, 'DESC');
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
        List<UnifiedActivityController.ActivityItem> result = UnifiedActivityController.getUnifiedActivities(acc.Id, 'DESC');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
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
