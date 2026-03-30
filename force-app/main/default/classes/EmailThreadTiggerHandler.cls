public with sharing class EmailThreadTiggerHandler extends TriggerHandler{
    List<Email_Platform__Email_Thread__c> newList;
    Map<Id,Email_Platform__Email_Thread__c> oldMap;

    public EmailThreadTiggerHandler() {
        this.newList = (List<Email_Platform__Email_Thread__c>) Trigger.new;
        this.oldMap = (Map<Id,Email_Platform__Email_Thread__c>) Trigger.oldMap;
    }

    protected override void afterInsert(){
        EmailThreadSharingService.grantAccessToEmailThread(newList);
	}
}