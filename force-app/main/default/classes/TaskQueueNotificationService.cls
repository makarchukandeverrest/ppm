public with sharing class TaskQueueNotificationService {
    private static final String NOTIFICATION_DEVELOPER_NAME = 'Task_Queue_Assignment_notification';
    private static final String REGIONAL_MANAGER_REQUEST_RECORD_TYPE = 'Regional_Manager_Request';

    private static Id regionalManagerRequestRecordTypeId;

    public static void notifyQueueMembers(List<Task> tasks, Map<Id, Task> oldMap) {
        if (tasks == null || tasks.isEmpty()) {
            return;
        }

        Id targetRecordTypeId = getRegionalManagerRequestRecordTypeId();
        if (targetRecordTypeId == null) {
            return;
        }

        List<Task> queueAssignedTasks = new List<Task>();
        Set<Id> queueIds = new Set<Id>();

        for (Task taskRecord : tasks) {
            if (taskRecord.RecordTypeId != targetRecordTypeId) {
                continue;
            }

            if (!isQueueOwner(taskRecord.OwnerId) || !isNewQueueAssignment(taskRecord, oldMap)) {
                continue;
            }

            queueAssignedTasks.add(taskRecord);
            queueIds.add(taskRecord.OwnerId);
        }

        if (queueAssignedTasks.isEmpty()) {
            return;
        }

        CustomNotificationType notificationType = getNotificationType();
        if (notificationType == null) {
            return;
        }

        Map<Id, Set<Id>> queueToUserIds = getQueueMemberUserIds(queueIds);
        Map<Id, String> queueNames = getQueueNames(queueIds);

        for (Task taskRecord : queueAssignedTasks) {
            Set<Id> recipientIds = queueToUserIds.get(taskRecord.OwnerId);
            if (recipientIds == null || recipientIds.isEmpty()) {
                continue;
            }

            sendNotification(
                notificationType.Id,
                taskRecord,
                queueNames.get(taskRecord.OwnerId),
                recipientIds
            );
        }
    }

    private static Boolean isQueueOwner(Id ownerId) {
        return ownerId != null && String.valueOf(ownerId).startsWith('00G');
    }

    private static Boolean isNewQueueAssignment(Task taskRecord, Map<Id, Task> oldMap) {
        if (oldMap == null) {
            return true;
        }

        Task oldTask = oldMap.get(taskRecord.Id);
        return oldTask == null || taskRecord.OwnerId != oldTask.OwnerId;
    }

    private static Id getRegionalManagerRequestRecordTypeId() {
        if (regionalManagerRequestRecordTypeId != null) {
            return regionalManagerRequestRecordTypeId;
        }

        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Task'
                AND DeveloperName = :REGIONAL_MANAGER_REQUEST_RECORD_TYPE
                AND IsActive = true
            LIMIT 1
        ];

        if (recordTypes.isEmpty()) {
            return null;
        }

        regionalManagerRequestRecordTypeId = recordTypes[0].Id;
        return regionalManagerRequestRecordTypeId;
    }

    private static CustomNotificationType getNotificationType() {
        List<CustomNotificationType> notificationTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_DEVELOPER_NAME
            LIMIT 1
        ];

        return notificationTypes.isEmpty() ? null : notificationTypes[0];
    }

    private static Map<Id, String> getQueueNames(Set<Id> queueIds) {
        Map<Id, String> queueNames = new Map<Id, String>();

        for (Group queueRecord : [
            SELECT Id, Name
            FROM Group
            WHERE Id IN :queueIds AND Type = 'Queue'
        ]) {
            queueNames.put(queueRecord.Id, queueRecord.Name);
        }

        return queueNames;
    }

    private static Map<Id, Set<Id>> getQueueMemberUserIds(Set<Id> queueIds) {
        Map<Id, Set<Id>> queueToUserIds = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> queueToRoleIds = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> queueToGroupIds = new Map<Id, Set<Id>>();

        for (Id queueId : queueIds) {
            queueToUserIds.put(queueId, new Set<Id>());
            queueToRoleIds.put(queueId, new Set<Id>());
            queueToGroupIds.put(queueId, new Set<Id>());
        }

        for (GroupMember groupMember : [
            SELECT GroupId, UserOrGroupId
            FROM GroupMember
            WHERE GroupId IN :queueIds
        ]) {
            String memberPrefix = String.valueOf(groupMember.UserOrGroupId).substring(0, 3);

            if (memberPrefix == '005') {
                queueToUserIds.get(groupMember.GroupId).add(groupMember.UserOrGroupId);
            } else if (memberPrefix == '00E') {
                queueToRoleIds.get(groupMember.GroupId).add(groupMember.UserOrGroupId);
            } else if (memberPrefix == '00G') {
                queueToGroupIds.get(groupMember.GroupId).add(groupMember.UserOrGroupId);
            }
        }

        Set<Id> allSeedRoleIds = new Set<Id>();
        for (Set<Id> roleIds : queueToRoleIds.values()) {
            allSeedRoleIds.addAll(roleIds);
        }

        Map<Id, Set<Id>> seedRoleToUserIds = getUsersBySeedRoles(allSeedRoleIds);

        for (Id queueId : queueIds) {
            Set<Id> userIds = queueToUserIds.get(queueId);

            for (Id seedRoleId : queueToRoleIds.get(queueId)) {
                if (seedRoleToUserIds.containsKey(seedRoleId)) {
                    userIds.addAll(seedRoleToUserIds.get(seedRoleId));
                }
            }

            for (Id groupId : queueToGroupIds.get(queueId)) {
                userIds.addAll(getUsersFromPublicGroup(groupId));
            }
        }

        return queueToUserIds;
    }

    private static Map<Id, Set<Id>> getUsersBySeedRoles(Set<Id> seedRoleIds) {
        Map<Id, Set<Id>> seedRoleToUserIds = new Map<Id, Set<Id>>();

        if (seedRoleIds.isEmpty()) {
            return seedRoleToUserIds;
        }

        Map<Id, Set<Id>> seedRoleToDescendantRoles = new Map<Id, Set<Id>>();

        for (Id seedRoleId : seedRoleIds) {
            seedRoleToDescendantRoles.put(
                seedRoleId,
                expandRolesWithSubordinates(new Set<Id>{ seedRoleId })
            );
            seedRoleToUserIds.put(seedRoleId, new Set<Id>());
        }

        Set<Id> allDescendantRoleIds = new Set<Id>();
        for (Set<Id> descendantRoleIds : seedRoleToDescendantRoles.values()) {
            allDescendantRoleIds.addAll(descendantRoleIds);
        }

        Map<Id, Set<Id>> roleToUserIds = new Map<Id, Set<Id>>();

        for (User activeUser : [
            SELECT Id, UserRoleId
            FROM User
            WHERE UserRoleId IN :allDescendantRoleIds AND IsActive = true
        ]) {
            if (!roleToUserIds.containsKey(activeUser.UserRoleId)) {
                roleToUserIds.put(activeUser.UserRoleId, new Set<Id>());
            }

            roleToUserIds.get(activeUser.UserRoleId).add(activeUser.Id);
        }

        for (Id seedRoleId : seedRoleIds) {
            for (Id roleId : seedRoleToDescendantRoles.get(seedRoleId)) {
                if (roleToUserIds.containsKey(roleId)) {
                    seedRoleToUserIds.get(seedRoleId).addAll(roleToUserIds.get(roleId));
                }
            }
        }

        return seedRoleToUserIds;
    }

    @TestVisible
    private static Set<Id> expandRolesWithSubordinates(Set<Id> seedRoleIds) {
        Set<Id> expandedRoleIds = new Set<Id>(seedRoleIds);
        Map<Id, UserRole> allRoles = new Map<Id, UserRole>([
            SELECT Id, ParentRoleId
            FROM UserRole
        ]);
        Boolean foundNewRole = true;

        while (foundNewRole) {
            foundNewRole = false;

            for (UserRole roleRecord : allRoles.values()) {
                if (
                    roleRecord.ParentRoleId != null &&
                    expandedRoleIds.contains(roleRecord.ParentRoleId) &&
                    !expandedRoleIds.contains(roleRecord.Id)
                ) {
                    expandedRoleIds.add(roleRecord.Id);
                    foundNewRole = true;
                }
            }
        }

        return expandedRoleIds;
    }

    private static Set<Id> getUsersFromPublicGroup(Id groupId) {
        Set<Id> userIds = new Set<Id>();
        Set<Id> roleIds = new Set<Id>();
        Set<Id> nestedGroupIds = new Set<Id>();

        for (GroupMember groupMember : [
            SELECT UserOrGroupId
            FROM GroupMember
            WHERE GroupId = :groupId
        ]) {
            String memberPrefix = String.valueOf(groupMember.UserOrGroupId).substring(0, 3);

            if (memberPrefix == '005') {
                userIds.add(groupMember.UserOrGroupId);
            } else if (memberPrefix == '00E') {
                roleIds.add(groupMember.UserOrGroupId);
            } else if (memberPrefix == '00G') {
                nestedGroupIds.add(groupMember.UserOrGroupId);
            }
        }

        for (Set<Id> roleMemberUserIds : getUsersBySeedRoles(roleIds).values()) {
            userIds.addAll(roleMemberUserIds);
        }

        for (Id nestedGroupId : nestedGroupIds) {
            userIds.addAll(getUsersFromPublicGroup(nestedGroupId));
        }

        return userIds;
    }

    private static void sendNotification(
        Id notificationTypeId,
        Task taskRecord,
        String queueName,
        Set<Id> recipientIds
    ) {
        String safeQueueName = String.isBlank(queueName) ? 'your queue' : queueName;
        String safeSubject = String.isBlank(taskRecord.Subject) ? 'New task' : taskRecord.Subject;

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(notificationTypeId);
        notification.setTitle('New task in ' + safeQueueName);
        notification.setBody(safeSubject + ' was assigned to ' + safeQueueName + '.');
        notification.setTargetId(taskRecord.Id);

        Set<String> recipientUserIds = new Set<String>();
        for (Id recipientId : recipientIds) {
            recipientUserIds.add(String.valueOf(recipientId));
        }

        try {
            notification.send(recipientUserIds);
        } catch (Exception ex) {
            System.debug('Task queue notification failed: ' + ex.getMessage());
        }
    }
}
