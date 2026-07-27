public with sharing class TaskTriggerHandler extends TriggerHandler {
    List<Task> newList;
    Map<Id, Task> oldMap;

    public TaskTriggerHandler() {
        this.newList = (List<Task>) Trigger.new;
        this.oldMap = (Map<Id, Task>) Trigger.oldMap;
    }

    protected override void beforeInsert() {
        TaskRegionalManagerRequestDefaults.applyBeforeInsert(this.newList);
    }

    protected override void afterInsert() {
        TaskQueueNotificationService.notifyQueueMembers(this.newList, null);
    }

    protected override void afterUpdate() {
        TaskQueueNotificationService.notifyQueueMembers(this.newList, this.oldMap);
    }
}
