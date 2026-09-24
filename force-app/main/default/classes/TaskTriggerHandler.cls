public with sharing class TaskTriggerHandler extends TriggerHandler {
    List<Task> newList;
    List<Task> oldList;
    Map<Id, Task> oldMap;

    public TaskTriggerHandler() {
        this.newList = (List<Task>) Trigger.new;
        this.oldList = (List<Task>) Trigger.old;
        this.oldMap = (Map<Id, Task>) Trigger.oldMap;
    }

    protected override void beforeInsert() {
        TaskRegionalManagerRequestDefaults.applyBeforeInsert(this.newList);
    }

    protected override void afterInsert() {
        TaskQueueNotificationService.notifyQueueMembers(this.newList, null);
        ContractBidActivityStampService.recalculateLatestCallLog(collectCallParentIds(this.newList));
    }

    protected override void afterUpdate() {
        TaskQueueNotificationService.notifyQueueMembers(this.newList, this.oldMap);

        List<Task> changedTasks = new List<Task>();
        for (Task t : this.newList) {
            Task oldTask = this.oldMap.get(t.Id);
            if (t.WhatId != oldTask.WhatId || t.TaskSubtype != oldTask.TaskSubtype) {
                changedTasks.add(t);
                changedTasks.add(oldTask);
            }
        }
        ContractBidActivityStampService.recalculateLatestCallLog(collectCallParentIds(changedTasks));
    }

    protected override void afterDelete() {
        ContractBidActivityStampService.recalculateLatestCallLog(collectCallParentIds(this.oldList));
    }

    protected override void afterUndelete() {
        ContractBidActivityStampService.recalculateLatestCallLog(collectCallParentIds(this.newList));
    }

    private static Set<Id> collectCallParentIds(List<Task> tasks) {
        Set<Id> parentIds = new Set<Id>();
        for (Task t : tasks) {
            if (t.WhatId == null || t.TaskSubtype != 'Call') {
                continue;
            }
            Schema.SObjectType parentType = t.WhatId.getSObjectType();
            if (parentType == Contract_Bid__c.SObjectType || parentType == Account.SObjectType) {
                parentIds.add(t.WhatId);
            }
        }
        return parentIds;
    }
}
