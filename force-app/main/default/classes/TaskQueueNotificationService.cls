public with sharing class TaskQueueNotificationService {
    private static final String NOTIFICATION_DEVELOPER_NAME = 'Task_Queue_Assignment_notification';

    public static void notifyQueueMembers(List<Task> tasks, Map<Id, Task> oldMap) {
        if (tasks == null || tasks.isEmpty()) {
            return;
        }

        Id targetRecordTypeId = TaskRecordTypeSelector.getRegionalManagerRequestRecordTypeId();
        if (targetRecordTypeId == null) {
            return;
        }

        CustomNotificationType notificationType = TaskQueueSelector.getCustomNotificationType(NOTIFICATION_DEVELOPER_NAME);
        if (notificationType == null) {
            return;
        }

        List<Task> queueAssignedTasks = new List<Task>();
        Set<Id> ownerIds = new Set<Id>();

        for (Task taskRecord : tasks) {
            if (taskRecord.RecordTypeId != targetRecordTypeId) {
                continue;
            }

            if (!isNewQueueAssignment(taskRecord, oldMap)) {
                continue;
            }

            queueAssignedTasks.add(taskRecord);
            ownerIds.add(taskRecord.OwnerId);
        }

        if (queueAssignedTasks.isEmpty()) {
            return;
        }

        Map<Id, Group> queuesByOwnerId = TaskQueueSelector.getQueuesByIds(ownerIds);

        for (Task taskRecord : queueAssignedTasks) {
            Group queue = queuesByOwnerId.get(taskRecord.OwnerId);
            if (queue == null) {
                continue;
            }

            sendNotification(notificationType.Id, taskRecord, queue.Name);
        }
    }

    private static Boolean isNewQueueAssignment(Task taskRecord, Map<Id, Task> oldMap) {
        if (oldMap == null) {
            return true;
        }

        Task oldTask = oldMap.get(taskRecord.Id);
        return oldTask == null || taskRecord.OwnerId != oldTask.OwnerId;
    }

    private static void sendNotification(
        Id notificationTypeId,
        Task taskRecord,
        String queueName
    ) {
        String safeQueueName = String.isBlank(queueName) ? 'your queue' : queueName;
        String safeSubject = String.isBlank(taskRecord.Subject) ? 'New task' : taskRecord.Subject;

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(notificationTypeId);
        notification.setTitle('New task in ' + safeQueueName);
        notification.setBody(safeSubject + ' was assigned to ' + safeQueueName + '.');
        notification.setTargetId(taskRecord.Id);

        try {
            notification.send(new Set<String>{ String.valueOf(taskRecord.OwnerId) });
        } catch (Exception ex) {
            System.debug('Task queue notification failed: ' + ex.getMessage());
        }
    }
}
