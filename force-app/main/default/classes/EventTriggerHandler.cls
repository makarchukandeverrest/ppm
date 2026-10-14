public with sharing class EventTriggerHandler extends TriggerHandler {
    List<Event> newList;
    List<Event> oldList;
    Map<Id, Event> oldMap;

    public EventTriggerHandler() {
        this.newList = (List<Event>) Trigger.new;
        this.oldList = (List<Event>) Trigger.old;
        this.oldMap = (Map<Id, Event>) Trigger.oldMap;
    }

    protected override void afterInsert() {
        ContractBidActivityStampService.recalculateActivityStats(collectActivityParentIds(this.newList));
    }

    protected override void afterUpdate() {
        List<Event> changedEvents = new List<Event>();
        for (Event e : this.newList) {
            Event oldEvent = this.oldMap.get(e.Id);
            if (e.WhatId != oldEvent.WhatId) {
                changedEvents.add(e);
                changedEvents.add(oldEvent);
            }
        }
        ContractBidActivityStampService.recalculateActivityStats(collectActivityParentIds(changedEvents));
    }

    protected override void afterDelete() {
        ContractBidActivityStampService.recalculateActivityStats(collectActivityParentIds(this.oldList));
    }

    protected override void afterUndelete() {
        ContractBidActivityStampService.recalculateActivityStats(collectActivityParentIds(this.newList));
    }

    private static Set<Id> collectActivityParentIds(List<Event> events) {
        Set<Id> parentIds = new Set<Id>();
        for (Event e : events) {
            if (e.WhatId == null) {
                continue;
            }
            Schema.SObjectType parentType = e.WhatId.getSObjectType();
            if (parentType == Contract_Bid__c.SObjectType || parentType == Account.SObjectType) {
                parentIds.add(e.WhatId);
            }
        }
        return parentIds;
    }
}
