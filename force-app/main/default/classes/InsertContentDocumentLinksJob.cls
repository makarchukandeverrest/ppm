public class InsertContentDocumentLinksJob implements Queueable {
    private List<ContentDocumentLink> links;

    public InsertContentDocumentLinksJob(List<ContentDocumentLink> links) {
        this.links = links.deepClone();
    }

    public void execute(QueueableContext context) {
        System.debug('Inserting ContentDocumentLinks: ' + links);
        if (links != null && !links.isEmpty()) {
            insert links;
        }
    }
}