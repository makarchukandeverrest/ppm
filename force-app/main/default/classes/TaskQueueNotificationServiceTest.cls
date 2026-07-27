@IsTest
private class TaskQueueNotificationServiceTest {
    @IsTest
    static void testNotifyQueueMembersOnInsert() {
        User queueMember = createStandardUser('queue.member@test.com');
        Group taskQueue = createTaskQueue('Notification Test Queue');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new GroupMember(
                GroupId = taskQueue.Id,
                UserOrGroupId = queueMember.Id
            );
        }

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
        User queueMember = createStandardUser('queue.member2@test.com');
        User taskOwner = createStandardUser('task.owner@test.com');
        Group taskQueue = createTaskQueue('Notification Update Queue');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new GroupMember(
                GroupId = taskQueue.Id,
                UserOrGroupId = queueMember.Id
            );
        }

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
        User taskOwner = createStandardUser('task.owner2@test.com');

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
        User groupMember = createStandardUser('queue.group.member@test.com');
        Group publicGroup = new Group(
            Name = 'Queue Public Group ' + System.currentTimeMillis(),
            Type = 'Regular'
        );
        insert publicGroup;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new GroupMember(
                GroupId = publicGroup.Id,
                UserOrGroupId = groupMember.Id
            );
        }

        Group taskQueue = createTaskQueue('Group Notification Queue');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new GroupMember(
                GroupId = taskQueue.Id,
                UserOrGroupId = publicGroup.Id
            );
        }

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
        User nestedGroupMember = createStandardUser('queue.nested.member@test.com');
        Group innerGroup = new Group(
            Name = 'Inner Queue Group ' + System.currentTimeMillis(),
            Type = 'Regular'
        );
        insert innerGroup;

        Group outerGroup = new Group(
            Name = 'Outer Queue Group ' + System.currentTimeMillis(),
            Type = 'Regular'
        );
        insert outerGroup;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<GroupMember>{
                new GroupMember(
                    GroupId = innerGroup.Id,
                    UserOrGroupId = nestedGroupMember.Id
                ),
                new GroupMember(
                    GroupId = outerGroup.Id,
                    UserOrGroupId = innerGroup.Id
                )
            };
        }

        Group taskQueue = createTaskQueue('Nested Group Notification Queue');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new GroupMember(
                GroupId = taskQueue.Id,
                UserOrGroupId = outerGroup.Id
            );
        }

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
        Group emptyQueue = createTaskQueue('Empty Notification Queue');

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
        User taskOwner = createStandardUser('task.owner3@test.com');
        Group taskQueue = createTaskQueue('Standard Task Queue');

        Test.startTest();
        Task queueTask = new Task(
            Subject = 'Standard queue task',
            OwnerId = taskQueue.Id,
            Status = 'Not Started'
        );
        insert queueTask;
        TaskQueueNotificationService.notifyQueueMembers(new List<Task>{ queueTask }, null);
        Test.stopTest();

        System.assertEquals(taskQueue.Id, queueTask.OwnerId);
    }

    @IsTest
    static void testSkipsWhenOwnerDoesNotChangeToQueue() {
        User taskOwner = createStandardUser('task.owner3@test.com');
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
        UserRole parentRole = new UserRole(
            Name = 'Coverage Parent Role ' + System.currentTimeMillis(),
            DeveloperName = 'Coverage_Parent_Role_' + System.currentTimeMillis()
        );
        insert parentRole;

        UserRole childRole = new UserRole(
            Name = 'Coverage Child Role ' + System.currentTimeMillis(),
            DeveloperName = 'Coverage_Child_Role_' + System.currentTimeMillis(),
            ParentRoleId = parentRole.Id
        );
        insert childRole;

        Test.startTest();
        Set<Id> expandedRoleIds = TaskQueueNotificationService.expandRolesWithSubordinates(
            new Set<Id>{ parentRole.Id }
        );
        Test.stopTest();

        System.assert(expandedRoleIds.contains(parentRole.Id));
        System.assert(expandedRoleIds.contains(childRole.Id));
    }

    private static User createStandardUser(String username) {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User testUser = new User(
            Alias = ('q' + String.valueOf(Math.abs(Crypto.getRandomInteger()))).left(8),
            Email = username,
            EmailEncodingKey = 'UTF-8',
            LastName = 'QueueMember',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = username + '.' + System.currentTimeMillis()
        );
        insert testUser;
        return testUser;
    }

    private static Id getRegionalManagerRequestRecordTypeId() {
        return [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Task' AND DeveloperName = 'Regional_Manager_Request'
            LIMIT 1
        ].Id;
    }

    private static Group createTaskQueue(String queueName) {
        Group taskQueue = new Group(
            Name = queueName,
            Type = 'Queue'
        );
        insert taskQueue;

        insert new QueueSobject(
            QueueId = taskQueue.Id,
            SobjectType = 'Task'
        );

        return taskQueue;
    }
}
