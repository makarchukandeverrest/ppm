public with sharing class DocuSignEnvelopeVoidService {
    private static final String DEFAULT_VOID_REASON = 'Contract Bid completed';
    private static final String SUPERSEDED_VOID_REASON = 'Superseded by a new contract envelope';
    private static final String SETTINGS_DEVELOPER_NAME = 'Void_Envelopes';
    private static final Set<String> OPEN_STATUSES = new Set<String>{ 'Sent', 'Delivered' };
    @TestVisible
    private static final Integer NEW_ENVELOPE_WINDOW_HOURS = 24;

    public class Request {
        @InvocableVariable(required=true label='Envelope Status Records')
        public List<dfsle__EnvelopeStatus__c> envelopeStatuses;

        @InvocableVariable(label='Void Reason')
        public String voidReason;
    }

    public class EnvelopeStatusDto {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String docuSignId;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String subject;
        @AuraEnabled
        public Datetime sentDate;
    }

    public class PreviousOpenEnvelopesResult {
        @AuraEnabled
        public Boolean hasPrevious;
        @AuraEnabled
        public Boolean newestIsRecent;
        @AuraEnabled
        public Integer previousCount;
        @AuraEnabled
        public EnvelopeStatusDto newest;
        @AuraEnabled
        public List<EnvelopeStatusDto> previous;

        public PreviousOpenEnvelopesResult() {
            this.hasPrevious = false;
            this.newestIsRecent = false;
            this.previousCount = 0;
            this.previous = new List<EnvelopeStatusDto>();
        }
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
            statusesToUpdate.addAll(voidEnvelopeStatuses(settings, req.envelopeStatuses, reason));
        }

        if (!statusesToUpdate.isEmpty()) {
            update statusesToUpdate;
        }
    }

    @AuraEnabled
    public static PreviousOpenEnvelopesResult getPreviousOpenEnvelopes(Id contractBidId) {
        try {
            return buildPreviousOpenEnvelopesResult(contractBidId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static Integer voidPreviousOpenEnvelopes(Id contractBidId) {
        try {
            PreviousOpenEnvelopesResult result = buildPreviousOpenEnvelopesResult(contractBidId);
            if (result == null || result.previous == null || result.previous.isEmpty()) {
                return 0;
            }

            List<dfsle__EnvelopeStatus__c> statusesToVoid = new List<dfsle__EnvelopeStatus__c>();
            for (EnvelopeStatusDto dto : result.previous) {
                if (dto == null || String.isBlank(dto.docuSignId)) {
                    continue;
                }
                dfsle__EnvelopeStatus__c statusRec = new dfsle__EnvelopeStatus__c(
                    dfsle__DocuSignId__c = dto.docuSignId
                );
                if (dto.id != null) {
                    statusRec.Id = dto.id;
                }
                statusesToVoid.add(statusRec);
            }

            Request req = new Request();
            req.envelopeStatuses = statusesToVoid;
            req.voidReason = SUPERSEDED_VOID_REASON;
            voidEnvelopes(new List<Request>{ req });
            return statusesToVoid.size();
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @TestVisible
    private static PreviousOpenEnvelopesResult buildPreviousOpenEnvelopesResult(Id contractBidId) {
        PreviousOpenEnvelopesResult result = new PreviousOpenEnvelopesResult();
        if (contractBidId == null) {
            return result;
        }

        List<dfsle__EnvelopeStatus__c> openStatuses = queryOpenEnvelopeStatuses(contractBidId);
        if (openStatuses.isEmpty()) {
            return result;
        }

        result.newest = toDto(openStatuses[0]);
        result.newestIsRecent = isRecent(result.newest == null ? null : result.newest.sentDate);
        for (Integer i = 1; i < openStatuses.size(); i++) {
            result.previous.add(toDto(openStatuses[i]));
        }
        result.previousCount = result.previous.size();
        result.hasPrevious = result.previousCount > 0;
        return result;
    }

    @TestVisible
    private static List<dfsle__EnvelopeStatus__c> queryOpenEnvelopeStatuses(Id contractBidId) {
        return [
            SELECT
                Id,
                Name,
                dfsle__DocuSignId__c,
                dfsle__Status__c,
                dfsle__EmailSubject__c,
                dfsle__Sent__c,
                CreatedDate
            FROM dfsle__EnvelopeStatus__c
            WHERE dfsle__SourceId__c = :contractBidId
            AND dfsle__Status__c IN :OPEN_STATUSES
            ORDER BY dfsle__Sent__c DESC NULLS LAST, CreatedDate DESC
        ];
    }

    private static EnvelopeStatusDto toDto(dfsle__EnvelopeStatus__c statusRec) {
        if (statusRec == null) {
            return null;
        }
        EnvelopeStatusDto dto = new EnvelopeStatusDto();
        dto.id = statusRec.Id;
        dto.docuSignId = statusRec.dfsle__DocuSignId__c;
        dto.status = statusRec.dfsle__Status__c;
        dto.subject = String.isBlank(statusRec.dfsle__EmailSubject__c)
            ? statusRec.Name
            : statusRec.dfsle__EmailSubject__c;
        dto.sentDate = statusRec.dfsle__Sent__c != null
            ? statusRec.dfsle__Sent__c
            : statusRec.CreatedDate;
        return dto;
    }

    @TestVisible
    private static Boolean isRecent(Datetime sentDate) {
        if (sentDate == null) {
            return false;
        }
        return sentDate >= Datetime.now().addHours(-NEW_ENVELOPE_WINDOW_HOURS);
    }

    private static List<dfsle__EnvelopeStatus__c> voidEnvelopeStatuses(
        DocuSign_API_Settings__mdt settings,
        List<dfsle__EnvelopeStatus__c> envelopeStatuses,
        String reason
    ) {
        List<dfsle__EnvelopeStatus__c> statusesToUpdate = new List<dfsle__EnvelopeStatus__c>();
        for (dfsle__EnvelopeStatus__c statusRec : envelopeStatuses) {
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
        return statusesToUpdate;
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
