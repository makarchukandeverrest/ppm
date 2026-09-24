public without sharing class EmailMessageTriggerHandler extends TriggerHandler {
    Map<Id, EmailMessage> newMap;
    Map<Id, EmailMessage> oldMap;

    public EmailMessageTriggerHandler() {
        this.newMap = (Map<Id, EmailMessage>) Trigger.newMap;
        this.oldMap = (Map<Id, EmailMessage>) Trigger.oldMap;
    }

    // ---------------- afterInsert ----------------
    protected override void afterInsert() {
        List<EmailMessage> docuSignEmails = new List<EmailMessage>();

        for (EmailMessage em : newMap.values()) {
            if (em == null) {
                continue;
            }

            if (em.FromAddress != null
                && em.Subject != null
                && em.FromAddress.contains('@docusign.net')
                && em.Subject.contains('Completed:')
                && em.HasAttachment == true) {

                docuSignEmails.add(em);
            }
        }

        if (!docuSignEmails.isEmpty()) {
            DocuSignSignedFileAssigner.assignDocuments(docuSignEmails);
        }

        ContractBidActivityStampService.recalculateActivityStats(collectEmailParentIds(newMap.values()));
    }

    // ---------------- afterUpdate ----------------
    protected override void afterUpdate() {
        List<EmailMessage> bouncedEmails  = new List<EmailMessage>();
        List<EmailMessage> docuSignEmails = new List<EmailMessage>();

        for (EmailMessage em : newMap.values()) {
            EmailMessage oldEm = oldMap.get(em.Id);

            // Bounce
            if (em.IsBounced == true && (oldEm == null || oldEm.IsBounced != true)) {
                bouncedEmails.add(em);
            }

            if (em == null) {
                continue;
            }

            if (em.FromAddress != null
                && em.Subject != null
                && em.FromAddress.contains('@docusign.net')
                && em.Subject.contains('Completed:')
                && em.HasAttachment == true) {

                docuSignEmails.add(em);
            }
        }

        if (!bouncedEmails.isEmpty()) {
            BounceEmailFromEmailMessageHandler.handle(bouncedEmails);
        }

        if (!docuSignEmails.isEmpty()) {
            DocuSignSignedFileAssigner.assignDocuments(docuSignEmails);
        }

        List<EmailMessage> changedEmails = new List<EmailMessage>();
        for (EmailMessage em : newMap.values()) {
            EmailMessage oldEm = oldMap.get(em.Id);
            if (em.RelatedToId != oldEm.RelatedToId || em.Incoming != oldEm.Incoming
                || em.MessageDate != oldEm.MessageDate || em.Status != oldEm.Status) {
                changedEmails.add(em);
                changedEmails.add(oldEm);
            }
        }
        ContractBidActivityStampService.recalculateActivityStats(collectEmailParentIds(changedEmails));
    }

    protected override void afterDelete() {
        ContractBidActivityStampService.recalculateActivityStats(collectEmailParentIds(oldMap.values()));
    }

    protected override void afterUndelete() {
        ContractBidActivityStampService.recalculateActivityStats(collectEmailParentIds(newMap.values()));
    }

    private static Set<Id> collectEmailParentIds(List<EmailMessage> emails) {
        Set<Id> parentIds = new Set<Id>();
        for (EmailMessage em : emails) {
            if (em.RelatedToId == null) {
                continue;
            }
            Schema.SObjectType parentType = em.RelatedToId.getSObjectType();
            if (parentType == Contract_Bid__c.SObjectType || parentType == Account.SObjectType) {
                parentIds.add(em.RelatedToId);
            }
        }
        return parentIds;
    }
}