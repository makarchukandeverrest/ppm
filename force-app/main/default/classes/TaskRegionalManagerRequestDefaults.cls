public with sharing class TaskRegionalManagerRequestDefaults {
    private static final String RECORD_TYPE_DEVELOPER_NAME = 'Regional_Manager_Request';

    private static Id recordTypeId;

    public static void applyBeforeInsert(List<Task> tasks) {
        if (tasks == null || tasks.isEmpty()) {
            return;
        }

        Id targetRecordTypeId = getRecordTypeId();
        if (targetRecordTypeId == null) {
            return;
        }

        Date defaultDueDate = Date.today().addDays(1);

        for (Task taskRecord : tasks) {
            if (taskRecord.RecordTypeId == targetRecordTypeId && taskRecord.ActivityDate == null) {
                taskRecord.ActivityDate = defaultDueDate;
            }
        }
    }

    private static Id getRecordTypeId() {
        if (recordTypeId != null) {
            return recordTypeId;
        }

        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Task'
                AND DeveloperName = :RECORD_TYPE_DEVELOPER_NAME
                AND IsActive = true
            LIMIT 1
        ];

        if (recordTypes.isEmpty()) {
            return null;
        }

        recordTypeId = recordTypes[0].Id;
        return recordTypeId;
    }
}
