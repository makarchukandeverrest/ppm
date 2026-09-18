public without sharing class DocuSignEnvelopeVoidService {
    private static final String DEFAULT_VOID_REASON = 'Contract Bid completed';
    private static final String SETTINGS_DEVELOPER_NAME = 'Void_Envelopes';
    private static final Integer ENVELOPES_PER_JOB = 40;

    public class Request {
        @InvocableVariable(required=true label='Envelope Status Records')
        public List<dfsle__EnvelopeStatus__c> envelopeStatuses;

        @InvocableVariable(label='Void Reason')
        public String voidReason;
    }

    public class DocuSignVoidException extends Exception {
    }

    public class VoidWork {
        public Id statusId;
        public String docuSignId;
        public String reason;
    }

    @TestVisible
    private static DocuSign_API_Settings__mdt testSettings;

    @InvocableMethod(
        label='Void DocuSign Envelopes'
        description='Voids DocuSign envelopes via REST API (JWT Named Credential) for the provided Envelope Status records.'
        callout=true
    )
    public static void voidEnvelopes(List<Request> requests) {
        List<VoidWork> workItems = collectWork(requests);
        if (workItems.isEmpty()) {
            return;
        }
        getSettings();
        System.enqueueJob(new Job(workItems));
    }

    public class Job implements Queueable, Database.AllowsCallouts {
        private List<VoidWork> workItems;

        public Job(List<VoidWork> workItems) {
            this.workItems = workItems == null ? new List<VoidWork>() : workItems;
        }

        public void execute(QueueableContext context) {
            if (workItems.isEmpty()) {
                return;
            }

            Integer endIndex = Math.min(ENVELOPES_PER_JOB, workItems.size());
            List<VoidWork> currentBatch = new List<VoidWork>();
            for (Integer i = 0; i < endIndex; i++) {
                currentBatch.add(workItems[i]);
            }

            voidBatchIndependently(currentBatch);

            if (endIndex < workItems.size()) {
                List<VoidWork> remaining = new List<VoidWork>();
                for (Integer i = endIndex; i < workItems.size(); i++) {
                    remaining.add(workItems[i]);
                }
                System.enqueueJob(new Job(remaining));
            }
        }
    }

    private static List<VoidWork> collectWork(List<Request> requests) {
        List<VoidWork> workItems = new List<VoidWork>();
        if (requests == null || requests.isEmpty()) {
            return workItems;
        }
        for (Request req : requests) {
            if (req == null || req.envelopeStatuses == null || req.envelopeStatuses.isEmpty()) {
                continue;
            }
            String reason = String.isBlank(req.voidReason) ? DEFAULT_VOID_REASON : req.voidReason;
            for (dfsle__EnvelopeStatus__c statusRec : req.envelopeStatuses) {
                if (statusRec == null || String.isBlank(statusRec.dfsle__DocuSignId__c)) {
                    continue;
                }
                VoidWork item = new VoidWork();
                item.statusId = statusRec.Id;
                item.docuSignId = statusRec.dfsle__DocuSignId__c.trim();
                item.reason = reason;
                workItems.add(item);
            }
        }
        return workItems;
    }

    @TestVisible
    static void voidBatchIndependently(List<VoidWork> workItems) {
        if (workItems == null || workItems.isEmpty()) {
            return;
        }

        DocuSign_API_Settings__mdt settings = getSettings();
        List<dfsle__EnvelopeStatus__c> statusesToUpdate = new List<dfsle__EnvelopeStatus__c>();

        for (VoidWork item : workItems) {
            if (item == null || String.isBlank(item.docuSignId)) {
                continue;
            }
            try {
                voidEnvelope(
                    settings.Named_Credential__c,
                    settings.Account_Id__c,
                    item.docuSignId,
                    item.reason
                );
                if (item.statusId != null) {
                    statusesToUpdate.add(
                        new dfsle__EnvelopeStatus__c(
                            Id = item.statusId,
                            dfsle__Status__c = 'Voided',
                            dfsle__Reason__c = item.reason
                        )
                    );
                }
            } catch (Exception ex) {
                System.debug(
                    LoggingLevel.ERROR,
                    'DocuSign void failed for envelope ' +
                    item.docuSignId +
                    ': ' +
                    ex.getMessage()
                );
            }
        }

        if (!statusesToUpdate.isEmpty()) {
            update statusesToUpdate;
        }
    }

    @TestVisible
    private static DocuSign_API_Settings__mdt getSettings() {
        DocuSign_API_Settings__mdt settings = Test.isRunningTest() && testSettings != null
            ? testSettings
            : DocuSign_API_Settings__mdt.getInstance(SETTINGS_DEVELOPER_NAME);
        if (
            settings == null ||
            String.isBlank(settings.Named_Credential__c) ||
            String.isBlank(settings.Account_Id__c)
        ) {
            throw new DocuSignVoidException(
                'DocuSign API Settings "' +
                    SETTINGS_DEVELOPER_NAME +
                    '" must define Named Credential and Account Id.'
            );
        }
        return settings;
    }

    @TestVisible
    private static void voidEnvelope(
        String namedCredential,
        String accountId,
        String docuSignId,
        String reason
    ) {
        if (
            String.isBlank(namedCredential) ||
            String.isBlank(accountId) ||
            String.isBlank(docuSignId) ||
            String.isBlank(reason)
        ) {
            throw new DocuSignVoidException(
                'Named Credential, Account Id, DocuSign envelope Id and void reason are required.'
            );
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'callout:' +
                namedCredential +
                '/restapi/v2.1/accounts/' +
                accountId +
                '/envelopes/' +
                docuSignId
        );
        req.setMethod('PUT');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);
        req.setBody(
            JSON.serialize(
                new Map<String, String>{
                    'status' => 'voided',
                    'voidedReason' => reason
                }
            )
        );

        HttpResponse res = new Http().send(req);
        Integer statusCode = res.getStatusCode();
        if (statusCode < 200 || statusCode >= 300) {
            throw new DocuSignVoidException(
                'DocuSign void failed (' + statusCode + '): ' + res.getBody()
            );
        }
    }
}
