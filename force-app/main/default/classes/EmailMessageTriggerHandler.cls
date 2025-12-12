public with sharing class EmailMessageTriggerHandler extends TriggerHandler {
    Map<Id, EmailMessage> newMap;
    Map<Id, EmailMessage> oldMap;

    public EmailMessageTriggerHandler() {
        this.newMap = (Map<Id, EmailMessage>) Trigger.newMap;
        this.oldMap = (Map<Id, EmailMessage>) Trigger.oldMap;
    }

    protected override void afterUpdate() {
        List<EmailMessage> bouncedEmails = handleBouncedEmails();
        if (!bouncedEmails.isEmpty()) {
            BounceEmailController.handleBouncedContractBidPackage(bouncedEmails);
        }
    }

    private List<EmailMessage> handleBouncedEmails() {
        List<EmailMessage> newlyBouncedEmails = new List<EmailMessage>();
        for (EmailMessage e : this.newMap.values()) {
            if (
                e.IsBounced != this.oldMap.get(e.Id).IsBounced &&
                e.IsBounced == true &&
                e.Subject.contains('Premier Pool Management Proposal')
            ) {
                newlyBouncedEmails.add(e);
            }
        }
        return newlyBouncedEmails;
    }
}