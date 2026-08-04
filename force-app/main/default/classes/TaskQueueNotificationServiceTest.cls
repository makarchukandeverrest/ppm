@IsTest
private class TaskQueueNotificationServiceTest {

    private static final String USERNAME_PREFIX = 'tqn.user';

    @TestSetup
    static void makeData() {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        Long ts = System.currentTimeMillis();

        List<User> users = new List<User>();
        for (Integer i = 0; i < 6; i++) {
            String username = USERNAME_PREFIX + i + '.' + ts + '@example.com';
            users.add(new User(
                Alias = ('q' + String.valueOf(Math.abs(Crypto.getRandomInteger()))).left(8),
                Email = username,
                EmailEncodingKey = 'UTF-8',
                LastName = 'QueueMember',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = standardProfile.Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                Username = username
            ));
        }
        insert users;

        UserRole parentRole = new UserRole(
            Name = 'TQN Parent Role ' + ts,
            DeveloperName = 'TQN_Parent_Role_' + ts
        );
        insert parentRole;
        UserRole childRole = new UserRole(
            Name = 'TQN Child Role ' + ts,
            DeveloperName = 'TQN_Child_Role_' + ts,
            ParentRoleId = parentRole.Id
        );
        insert childRole;

        // Queue with direct member
        Group directQueue = new Group(Name = 'TQN Direct ' + ts, Type = 'Queue');
        insert directQueue;
        insert new QueueSobject(QueueId = directQueue.Id, SobjectType = 'Task');
        insert new GroupMember(GroupId = directQueue.Id, UserOrGroupId = users[0].Id);

        // Public group and a queue that contains it
        Group publicGroup = new Group(Name = 'TQN Public ' + ts, Type = 'Regular');
        insert publicGroup;
        insert new GroupMember(GroupId = publicGroup.Id, UserOrGroupId = users[2].Id);

        Group groupQueue = new Group(Name = 'TQN Group ' + ts, Type = 'Queue');
        insert groupQueue;
        insert new QueueSobject(QueueId = groupQueue.Id, SobjectType = 'Task');
        insert new GroupMember(GroupId = groupQueue.Id, UserOrGroupId = publicGroup.Id);

        // Nested groups
        Group innerGroup = new Group(Name = 'TQN Inner ' + ts, Type = 'Regular');
        insert innerGroup;
        Group outerGroup = new Group(Name = 'TQN Outer ' + ts, Type = 'Regular');
        insert outerGroup;
        insert new List<GroupMember>{
            new GroupMember(GroupId = innerGroup.Id, UserOrGroupId = users[3].Id),
            new GroupMember(GroupId = outerGroup.Id, UserOrGroupId = innerGroup.Id)
        };

        Group nestedQueue = new Group(Name = 'TQN Nested ' + ts, Type = 'Queue');
        insert nestedQueue;
        insert new QueueSobject(QueueId = nestedQueue.Id, SobjectType = 'Task');
        insert new GroupMember(GroupId = nestedQueue.Id, UserOrGroupId = outerGroup.Id);

        // Empty queue and a plain queue for standard tasks
        Group emptyQueue = new Group(Name = 'TQN Empty ' + ts, Type = 'Queue');
        insert emptyQueue;
        insert new QueueSobject(QueueId = emptyQueue.Id, SobjectType = 'Task');

        Group standardQueue = new Group(Name = 'TQN Standard ' + ts, Type = 'Queue');
        insert standardQueue;
        insert new QueueSobject(QueueId = standardQueue.Id, SobjectType = 'Task');
    }

    @IsTest
    static void testNotifyQueueMembersOnInsert() {
        Group taskQueue = getQueue('TQN Direct');

        Test.startTest();
        Task queueTask = new Task(
            Subject = 'Queue notification test',
            OwnerId = taskQueue.Id,
            Status = 'Not Started',
            RecordTypeId = getRegionalManagerRequestRecordTypeId()
        );
        insert queueTask;
        Test.stopTest();

        Task insertedTask = [
            SELECT Id, OwnerId, Subject
            FROM Task
            WHERE Id = :queueTask.Id
        ];
        System.assertEquals(taskQueue.Id, insertedTask.OwnerId);
        System.assertEquals('Queue notification test', insertedTask.Subject);
    }

    @IsTest
    static void testNotifyQueueMembersOnOwnerChange() {
        User taskOwner = getUser(1);
        Group taskQueue = getQueue('TQN Direct');

        Task ownedTask = new Task(
            Subject = 'Owner change test',
            OwnerId = taskOwner.Id,
            Status = 'Not Started'
        );
        insert ownedTask;

        Test.startTest();
        ownedTask.OwnerId = taskQueue.Id;
        update ownedTask;
        Test.stopTest();

        Task updatedTask = [
            SELECT OwnerId
            FROM Task
            WHERE Id = :ownedTask.Id
        ];
        System.assertEquals(taskQueue.Id, updatedTask.OwnerId);
    }

    @IsTest
    static void testSkipsUserOwnedTasks() {
        User taskOwner = getUser(1);

        Test.startTest();
        Task userTask = new Task(
            Subject = 'User owned task',
            OwnerId = taskOwner.Id,
            Status = 'Not Started'
        );
        insert userTask;
        TaskQueueNotificationService.notifyQueueMembers(new List<Task>(), null);
        TaskQueueNotificationService.notifyQueueMembers(
            new List<Task>{ userTask },
            new Map<Id, Task>{ userTask.Id => userTask }
        );
        Test.stopTest();

        System.assertEquals(taskOwner.Id, userTask.OwnerId);
    }

    @IsTest
    static void testNotifyQueueMembersWithPublicGroupMember() {
        Group taskQueue = getQueue('TQN Group');

        Test.startTest();
        Task queueTask = new Task(
            Subject = 'Public group notification test',
            OwnerId = taskQueue.Id,
            Status = 'Not Started'
        );
        insert queueTask;
        Test.stopTest();

        System.assertEquals(taskQueue.Id, queueTask.OwnerId);
    }

    @IsTest
    static void testNotifyQueueMembersWithNestedPublicGroupMember() {
        Group taskQueue = getQueue('TQN Nested');

        Test.startTest();
        Task queueTask = new Task(
            Subject = 'Nested group notification test',
            OwnerId = taskQueue.Id,
            Status = 'Not Started'
        );
        insert queueTask;
        Test.stopTest();

        System.assertEquals(taskQueue.Id, queueTask.OwnerId);
    }

    @IsTest
    static void testSkipsQueueWithNoMembers() {
        Group emptyQueue = getQueue('TQN Empty');

        Test.startTest();
        Task queueTask = new Task(
            Subject = 'Empty queue test',
            OwnerId = emptyQueue.Id,
            Status = 'Not Started'
        );
        insert queueTask;
        Test.stopTest();

        System.assertEquals(emptyQueue.Id, queueTask.OwnerId);
    }

    @IsTest
    static void testSkipsQueueTasksWithoutRegionalManagerRequestRecordType() {
        Group taskQueue = getQueue('TQN Standard');
        User taskOwner = getUser(1);

        RecordType nonRegionalRecordType = getNonRegionalManagerRequestRecordType();

        Test.startTest();
        Task queueTask = new Task(
            Subject = 'Standard queue task',
            OwnerId = taskQueue.Id,
            Status = 'Not Started',
            RecordTypeId = nonRegionalRecordType != null ? nonRegionalRecordType.Id : null
        );
        insert queueTask;
        TaskQueueNotificationService.notifyQueueMembers(new List<Task>{ queueTask }, null);
        Test.stopTest();

        System.assertEquals(taskQueue.Id, queueTask.OwnerId);
    }

    @IsTest
    static void testSkipsWhenOwnerDoesNotChangeToQueue() {
        User taskOwner = getUser(1);
        Task ownedTask = new Task(
            Subject = 'No queue change',
            OwnerId = taskOwner.Id,
            Status = 'Not Started'
        );
        insert ownedTask;

        Task oldTask = ownedTask.clone(true, true, true, true);
        ownedTask.Subject = 'Updated subject';

        Test.startTest();
        update ownedTask;
        TaskQueueNotificationService.notifyQueueMembers(
            new List<Task>{ ownedTask },
            new Map<Id, Task>{ ownedTask.Id => oldTask }
        );
        Test.stopTest();

        System.assertEquals('Updated subject', ownedTask.Subject);
    }

    @IsTest
    static void testRegionalManagerRequestDefaultDueDate() {
        Task regionalManagerTask = new Task(
            Subject = 'Due date default test',
            Status = 'Not Started',
            RecordTypeId = getRegionalManagerRequestRecordTypeId()
        );

        Test.startTest();
        insert regionalManagerTask;
        Test.stopTest();

        Task insertedTask = [
            SELECT ActivityDate
            FROM Task
            WHERE Id = :regionalManagerTask.Id
        ];
        System.assertEquals(
            Date.today().addDays(1),
            insertedTask.ActivityDate,
            'Regional Manager Request tasks should default Due Date to tomorrow.'
        );
    }

    @IsTest
    static void testRegionalManagerRequestKeepsProvidedDueDate() {
        Date customDueDate = Date.today().addDays(5);
        Task regionalManagerTask = new Task(
            Subject = 'Custom due date test',
            Status = 'Not Started',
            ActivityDate = customDueDate,
            RecordTypeId = getRegionalManagerRequestRecordTypeId()
        );

        Test.startTest();
        insert regionalManagerTask;
        Test.stopTest();

        Task insertedTask = [
            SELECT ActivityDate
            FROM Task
            WHERE Id = :regionalManagerTask.Id
        ];
        System.assertEquals(customDueDate, insertedTask.ActivityDate);
    }

    @IsTest
    static void testExpandRolesWithSubordinates() {
        UserRole parentRole = [SELECT Id FROM UserRole WHERE DeveloperName LIKE 'TQN_Parent_Role_%' LIMIT 1];
        UserRole childRole = [SELECT Id FROM UserRole WHERE DeveloperName LIKE 'TQN_Child_Role_%' LIMIT 1];

        Test.startTest();
        Set<Id> expandedRoleIds = TaskQueueNotificationService.expandRolesWithSubordinates(
            new Set<Id>{ parentRole.Id }
        );
        Test.stopTest();

        System.assert(expandedRoleIds.contains(parentRole.Id));
        System.assert(expandedRoleIds.contains(childRole.Id));
    }

    private static User getUser(Integer index) {
        String usernamePattern = USERNAME_PREFIX + index + '.%';
        return [SELECT Id FROM User WHERE Username LIKE :usernamePattern LIMIT 1];
    }

    private static Group getQueue(String namePrefix) {
        return [SELECT Id FROM Group WHERE Name LIKE :('%' + namePrefix + '%') AND Type = 'Queue' LIMIT 1];
    }

    private static Id getRegionalManagerRequestRecordTypeId() {
        return [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Task' AND DeveloperName = 'Regional_Manager_Request'
            LIMIT 1
        ].Id;
    }

    private static RecordType getNonRegionalManagerRequestRecordType() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Task' AND DeveloperName != 'Regional_Manager_Request'
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0];
    }
}