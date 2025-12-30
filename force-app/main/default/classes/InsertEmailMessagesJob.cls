public class InsertEmailMessagesJob implements Queueable {
    private List<EmailMessage> emails;

    public InsertEmailMessagesJob(List<EmailMessage> emails) {
        this.emails = emails.deepClone();
    }

    public void execute(QueueableContext qc) {
        insert emails;

        List<ContentDocumentLink> contentDocumentLinksToInsert = new List<ContentDocumentLink>();
        for (EmailMessage e : emails) {
            ContentDocumentLink cdl = new ContentDocumentLink(
                ContentDocumentId = e.TextBody, // fix this later
                LinkedEntityId = e.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
            contentDocumentLinksToInsert.add(cdl);
        }

        System.debug('Preparing to enqueue ContentDocumentLinks job: ' + contentDocumentLinksToInsert);

        if (!Test.isRunningTest()) {
            System.enqueueJob(new InsertContentDocumentLinksJob(contentDocumentLinksToInsert));
        }
    }
}