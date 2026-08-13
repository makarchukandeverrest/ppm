public with sharing class TaskRegionalManagerRequestDefaults {
    public static void applyBeforeInsert(List<Task> tasks) {
        if (tasks == null || tasks.isEmpty()) {
            return;
        }

        Id targetRecordTypeId = TaskRecordTypeSelector.getRegionalManagerRequestRecordTypeId();
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
}
