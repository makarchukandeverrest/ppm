public with sharing class WorkOrderEmailHandler implements Messaging.InboundEmailHandler{
    public Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        System.debug('Processing email: ' + email.subject);
        return result;
    }

    private void processEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        System.debug('Processing email: ' + email.subject);
    }
}