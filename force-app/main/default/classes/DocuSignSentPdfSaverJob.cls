public class DocuSignSentPdfSaverJob implements Queueable, Database.AllowsCallouts {

    private Id accountId;
    private Id sourceContentVersionId;
    private String envelopeId;

    public DocuSignSentPdfSaverJob(
        Id accountId,
        Id sourceContentVersionId,
        String envelopeId
    ) {
        this.accountId = accountId;
        this.sourceContentVersionId = sourceContentVersionId;
        this.envelopeId = envelopeId;
    }

    public void execute(QueueableContext context) {
        try {
            DocuSignSentPdfService.saveSentPdfFromEnvelope(
                accountId,
                sourceContentVersionId,
                envelopeId
            );
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'Failed to save sent PDF copy for envelope ' +
                envelopeId +
                ': ' +
                ex.getMessage()
            );
            throw ex;
        }
    }
}
