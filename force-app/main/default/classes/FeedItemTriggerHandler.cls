public with sharing class FeedItemTriggerHandler extends TriggerHandler {
    List<FeedItem> newList;
    List<FeedItem> oldList;

    public FeedItemTriggerHandler() {
        this.newList = (List<FeedItem>) Trigger.new;
        this.oldList = (List<FeedItem>) Trigger.old;
    }

    protected override void afterInsert() {
        ContractBidActivityStampService.recalculateLatestPost(collectPostParentIds(this.newList));
    }

    protected override void afterDelete() {
        ContractBidActivityStampService.recalculateLatestPost(collectPostParentIds(this.oldList));
    }

    private static Set<Id> collectPostParentIds(List<FeedItem> feedItems) {
        Set<Id> parentIds = new Set<Id>();
        for (FeedItem item : feedItems) {
            if (!ContractBidActivityStampService.POST_TYPES.contains(item.Type)) {
                continue;
            }
            Schema.SObjectType parentType = item.ParentId.getSObjectType();
            if (parentType == Contract_Bid__c.SObjectType || parentType == Account.SObjectType) {
                parentIds.add(item.ParentId);
            }
        }
        return parentIds;
    }
}
