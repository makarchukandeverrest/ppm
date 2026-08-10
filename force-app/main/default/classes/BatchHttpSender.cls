public with sharing class BatchHttpSender implements Database.Batchable<DocuSignDfsleEnvelopeService.DfsleEnvelopeSendRequest>, Database.AllowsCallouts {

    private List<DocuSignDfsleEnvelopeService.DfsleEnvelopeSendRequest> requestsToSend;

    public BatchHttpSender(List<DocuSignDfsleEnvelopeService.DfsleEnvelopeSendRequest> requests) {
        this.requestsToSend = requests;
    }

    public Iterable<DocuSignDfsleEnvelopeService.DfsleEnvelopeSendRequest> start(Database.BatchableContext bc) {
        return requestsToSend;
    }

    public void execute(Database.BatchableContext bc, List<DocuSignDfsleEnvelopeService.DfsleEnvelopeSendRequest> scope) {
        for (DocuSignDfsleEnvelopeService.DfsleEnvelopeSendRequest req : scope) {
            try {
                DocuSignDfsleEnvelopeService.sendEnvelope(
                    req.contractBidId,
                    req.mainContentVersionId,
                    req.signerEmail,
                    req.signerName,
                    req.isNewCustomer,
                    req.accountId,
                    req.secondaryContact,
                    req.ccUsers,
                    req.reminderValue,
                    req.daysBeforeExpires
                );
            } catch (Exception ex) {
                System.debug('DFSLE envelope send failed: ' + ex.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('All DFSLE envelope requests complete');
    }
}
