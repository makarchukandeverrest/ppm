public with sharing class DocuSignEnvelopeVoidService {
    private static final String DEFAULT_VOID_REASON = 'Contract Bid completed';
    private static final String SETTINGS_DEVELOPER_NAME = 'Void_Envelopes';

    public class Request {
        @InvocableVariable(required=true label='Envelope Status Records')
        public List<dfsle__EnvelopeStatus__c> envelopeStatuses;

        @InvocableVariable(label='Void Reason')
        public String voidReason;
    }

    public class DocuSignVoidException extends Exception {
    }

    @TestVisible
    private static DocuSign_API_Settings__mdt testSettings;

    @InvocableMethod(
        label='Void DocuSign Envelopes'
        description='Voids DocuSign envelopes via REST API (JWT Named Credential) for the provided Envelope Status records.'
        callout=true
    )
    public static void voidEnvelopes(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Boolean hasWork = false;
        for (Request req : requests) {
            if (req != null && req.envelopeStatuses != null && !req.envelopeStatuses.isEmpty()) {
                hasWork = true;
                break;
            }
        }
        if (!hasWork) {
            return;
        }

        DocuSign_API_Settings__mdt settings = getSettings();
        List<dfsle__EnvelopeStatus__c> statusesToUpdate = new List<dfsle__EnvelopeStatus__c>();

        for (Request req : requests) {
            if (req == null || req.envelopeStatuses == null || req.envelopeStatuses.isEmpty()) {
                continue;
            }

            String reason = String.isBlank(req.voidReason) ? DEFAULT_VOID_REASON : req.voidReason;
            for (dfsle__EnvelopeStatus__c statusRec : req.envelopeStatuses) {
                if (statusRec == null || String.isBlank(statusRec.dfsle__DocuSignId__c)) {
                    continue;
                }

                voidEnvelope(
                    settings.Named_Credential__c,
                    settings.Account_Id__c,
                    statusRec.dfsle__DocuSignId__c,
                    reason
                );

                if (statusRec.Id != null) {
                    statusesToUpdate.add(
                        new dfsle__EnvelopeStatus__c(
                            Id = statusRec.Id,
                            dfsle__Status__c = 'Voided',
                            dfsle__Reason__c = reason
                        )
                    );
                }
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
