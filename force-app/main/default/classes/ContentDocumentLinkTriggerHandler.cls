public with sharing class ContentDocumentLinkTriggerHandler extends TriggerHandler {
    List<ContentDocumentLink> newList;

    public ContentDocumentLinkTriggerHandler() {
        this.newList = (List<ContentDocumentLink>) Trigger.new;
    }

    protected override void afterInsert() {
        List<ContentDocumentLink> accountLinks = new List<ContentDocumentLink>();
        for (ContentDocumentLink link : newList) {
            if (
                link.LinkedEntityId != null &&
                link.LinkedEntityId.getSObjectType() == Account.SObjectType
            ) {
                accountLinks.add(link);
            }
        }
        if (!accountLinks.isEmpty()) {
            ContentDocumentLinkWinterizationAssigner.assignWinterizationToCases(accountLinks);
        }
    }
}
