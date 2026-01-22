public with sharing class EmailThreadTriggerHandler extends TriggerHandler{
    List<Email_Platform__Email_Thread__c> newList;
    Map<Id,Email_Platform__Email_Thread__c> oldMap;

    public EmailThreadTriggerHandler() {
        this.newList = (List<Email_Platform__Email_Thread__c>) Trigger.new;
        this.oldMap = (Map<Id,Email_Platform__Email_Thread__c>) Trigger.oldMap;
    }

    protected override void afterInsert(){
        EmailThreadSharingService.grantAccessToEmailThread(newList);
	}
}
