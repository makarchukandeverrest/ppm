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
    }
}