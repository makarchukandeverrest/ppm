public without sharing class DocuSignCompletedEmailJob implements Queueable {
    private final List<Id> contentVersionIds;

    public DocuSignCompletedEmailJob(List<Id> contentVersionIds) {
        this.contentVersionIds = contentVersionIds == null
            ? new List<Id>()
            : new List<Id>(contentVersionIds);
    }

    public void execute(QueueableContext context) {
        DocuSignCompletedContractEmailService.sendForContentVersionIds(contentVersionIds);
    }
}
