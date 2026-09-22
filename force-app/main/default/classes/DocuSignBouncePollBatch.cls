public with sharing class DocuSignBouncePollBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime lookback = System.now().addDays(-DocuSignBouncePollService.LOOKBACK_DAYS);
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    dfsle__Email__c,
                    dfsle__Status__c,
                    dfsle__Reason__c,
                    Email_Bounced__c,
                    Bounce_Reason__c,
                    dfsle__EnvelopeStatus__c,
                    dfsle__EnvelopeStatus__r.dfsle__DocuSignId__c
                FROM dfsle__RecipientStatus__c
                WHERE
                    Email_Bounced__c = FALSE
                    AND dfsle__Status__c IN ('Sent', 'Delivered')
                    AND dfsle__EnvelopeStatus__r.dfsle__Status__c IN ('Sent', 'Delivered')
                    AND dfsle__EnvelopeStatus__r.dfsle__DocuSignId__c != NULL
                    AND dfsle__Sent__c >= :lookback
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        DocuSignBouncePollService.processRecipients((List<dfsle__RecipientStatus__c>) scope);
    }

    public void finish(Database.BatchableContext bc) {
    }
}
