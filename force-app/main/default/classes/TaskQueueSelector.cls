public with sharing class TaskQueueSelector {
    public static CustomNotificationType getCustomNotificationType(String developerName) {
        List<CustomNotificationType> notificationTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :developerName
            WITH USER_MODE
            LIMIT 1
        ];

        return notificationTypes.isEmpty() ? null : notificationTypes[0];
    }

    public static Map<Id, Group> getQueuesByIds(Set<Id> queueIds) {
        Map<Id, Group> queueById = new Map<Id, Group>();

        for (Group queueRecord : [
            SELECT Id, Name
            FROM Group
            WHERE Id IN :queueIds AND Type = 'Queue'
            WITH USER_MODE
        ]) {
            queueById.put(queueRecord.Id, queueRecord);
        }

        return queueById;
    }
}
