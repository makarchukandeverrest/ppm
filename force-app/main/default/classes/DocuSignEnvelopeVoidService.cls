public with sharing class DocuSignEnvelopeVoidService {
    private static final String DEFAULT_VOID_REASON = 'Contract Bid completed';
    private static final String SUPERSEDED_VOID_REASON = 'Superseded by a new contract envelope';
    private static final String SETTINGS_DEVELOPER_NAME = 'Void_Envelopes';
    private static final String INVALID_STATE_ERROR = 'ENVELOPE_CANNOT_VOID_INVALID_STATE';
    private static final Set<String> OPEN_STATUSES = new Set<String>{ 'Sent', 'Delivered' };
    private static final Set<String> VOIDABLE_STATUSES = new Set<String>{ 'sent', 'delivered' };
    @TestVisible
    private static final Integer NEW_ENVELOPE_WINDOW_HOURS = 24;

    public class Request {
        @InvocableVariable(required=true label='Envelope Status Records')
        public List<dfsle__EnvelopeStatus__c> envelopeStatuses;

        @InvocableVariable(label='Void Reason')
        public String voidReason;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Voided Count')
        public Integer voidedCount;

        @InvocableVariable(label='Skipped Count')
        public Integer skippedCount;

        @InvocableVariable(label='Message')
        public String message;
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

    private class DocuSignEnvelopePayload {
        public String status;
        public String errorCode;
        public String message;
    }

    private class VoidAttempt {
        Boolean voided;
        Boolean skipped;
        String salesforceStatus;
        String reason;

        VoidAttempt() {
            this.voided = false;
            this.skipped = false;
        }
    }

    @TestVisible
    private static DocuSign_API_Settings__mdt testSettings;

    @InvocableMethod(
        label='Void DocuSign Envelopes'
        description='Voids DocuSign envelopes via REST API (JWT Named Credential) for the provided Envelope Status records.'
        callout=true
    )
    public static List<Result> voidEnvelopes(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Boolean hasWork = false;
        for (Request req : requests) {
            if (req != null && req.envelopeStatuses != null && !req.envelopeStatuses.isEmpty()) {
                hasWork = true;
                break;
            }
        }
        if (!hasWork) {
            for (Integer i = 0; i < requests.size(); i++) {
                results.add(emptySuccessResult());
            }
            return results;
        }

        DocuSign_API_Settings__mdt settings = getSettings();
        List<dfsle__EnvelopeStatus__c> statusesToUpdate = new List<dfsle__EnvelopeStatus__c>();

        for (Request req : requests) {
            Result result = emptySuccessResult();
            if (req == null || req.envelopeStatuses == null || req.envelopeStatuses.isEmpty()) {
                results.add(result);
                continue;
            }

            String reason = String.isBlank(req.voidReason) ? DEFAULT_VOID_REASON : req.voidReason;
            for (dfsle__EnvelopeStatus__c statusRec : req.envelopeStatuses) {
                VoidAttempt attempt = voidOneEnvelope(settings, statusRec, reason);
                if (attempt.voided) {
                    result.voidedCount++;
                } else if (attempt.skipped) {
                    result.skippedCount++;
                }
                if (statusRec != null && statusRec.Id != null && attempt.salesforceStatus != null) {
                    dfsle__EnvelopeStatus__c updateRec = new dfsle__EnvelopeStatus__c(
                        Id = statusRec.Id,
                        dfsle__Status__c = attempt.salesforceStatus
                    );
                    if (attempt.voided) {
                        updateRec.dfsle__Reason__c = attempt.reason;
                    }
                    statusesToUpdate.add(updateRec);
                }
            }
            result.message = result.voidedCount +
                ' voided, ' +
                result.skippedCount +
                ' skipped';
            results.add(result);
        }

        if (!statusesToUpdate.isEmpty()) {
            update statusesToUpdate;
        }
        return results;
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
            List<Result> voidResults = voidEnvelopes(new List<Request>{ req });
            return voidResults.isEmpty() ? 0 : voidResults[0].voidedCount;
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

    private static Result emptySuccessResult() {
        Result result = new Result();
        result.success = true;
        result.voidedCount = 0;
        result.skippedCount = 0;
        return result;
    }

    private static VoidAttempt voidOneEnvelope(
        DocuSign_API_Settings__mdt settings,
        dfsle__EnvelopeStatus__c statusRec,
        String reason
    ) {
        VoidAttempt attempt = new VoidAttempt();
        if (statusRec == null || String.isBlank(statusRec.dfsle__DocuSignId__c)) {
            return attempt;
        }

        String liveStatus = getEnvelopeStatus(
            settings.Named_Credential__c,
            settings.Account_Id__c,
            statusRec.dfsle__DocuSignId__c
        );
        if (String.isBlank(liveStatus) || !isVoidable(liveStatus)) {
            attempt.skipped = true;
            attempt.salesforceStatus = toSalesforceStatus(liveStatus);
            return attempt;
        }

        Boolean voided = voidEnvelope(
            settings.Named_Credential__c,
            settings.Account_Id__c,
            statusRec.dfsle__DocuSignId__c,
            reason
        );
        if (voided) {
            attempt.voided = true;
            attempt.salesforceStatus = 'Voided';
            attempt.reason = reason;
            return attempt;
        }

        attempt.skipped = true;
        String refreshedStatus = getEnvelopeStatus(
            settings.Named_Credential__c,
            settings.Account_Id__c,
            statusRec.dfsle__DocuSignId__c
        );
        attempt.salesforceStatus = toSalesforceStatus(
            String.isBlank(refreshedStatus) ? liveStatus : refreshedStatus
        );
        return attempt;
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
    private static String getEnvelopeStatus(
        String namedCredential,
        String accountId,
        String docuSignId
    ) {
        HttpResponse res = sendEnvelopeRequest(namedCredential, accountId, docuSignId, 'GET', null);
        Integer statusCode = res.getStatusCode();
        if (statusCode == 404) {
            return null;
        }
        if (statusCode < 200 || statusCode >= 300) {
            throw new DocuSignVoidException(
                'DocuSign status check failed (' + statusCode + '): ' + res.getBody()
            );
        }
        return parseEnvelopeStatus(res.getBody());
    }

    @TestVisible
    private static Boolean voidEnvelope(
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

        HttpResponse res = sendEnvelopeRequest(
            namedCredential,
            accountId,
            docuSignId,
            'PUT',
            JSON.serialize(
                new Map<String, String>{
                    'status' => 'voided',
                    'voidedReason' => reason
                }
            )
        );
        Integer statusCode = res.getStatusCode();
        if (statusCode >= 200 && statusCode < 300) {
            return true;
        }
        if (isNonVoidableStateError(res.getBody())) {
            return false;
        }
        throw new DocuSignVoidException(
            'DocuSign void failed (' + statusCode + '): ' + res.getBody()
        );
    }

    private static HttpResponse sendEnvelopeRequest(
        String namedCredential,
        String accountId,
        String docuSignId,
        String method,
        String body
    ) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(buildEnvelopeEndpoint(namedCredential, accountId, docuSignId));
        req.setMethod(method);
        req.setTimeout(120000);
        if (body != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
        }
        return new Http().send(req);
    }

    private static String buildEnvelopeEndpoint(
        String namedCredential,
        String accountId,
        String docuSignId
    ) {
        return 'callout:' +
            namedCredential +
            '/restapi/v2.1/accounts/' +
            accountId +
            '/envelopes/' +
            docuSignId;
    }

    @TestVisible
    private static Boolean isVoidable(String docuSignStatus) {
        return String.isNotBlank(docuSignStatus) &&
            VOIDABLE_STATUSES.contains(docuSignStatus.trim().toLowerCase());
    }

    @TestVisible
    private static Boolean isNonVoidableStateError(String responseBody) {
        return String.isNotBlank(responseBody) && responseBody.contains(INVALID_STATE_ERROR);
    }

    @TestVisible
    private static String toSalesforceStatus(String docuSignStatus) {
        if (String.isBlank(docuSignStatus)) {
            return null;
        }
        String normalized = docuSignStatus.trim().toLowerCase();
        return normalized.substring(0, 1).toUpperCase() + normalized.substring(1);
    }

    private static String parseEnvelopeStatus(String body) {
        if (String.isBlank(body)) {
            return null;
        }
        try {
            DocuSignEnvelopePayload payload = (DocuSignEnvelopePayload) JSON.deserialize(
                body,
                DocuSignEnvelopePayload.class
            );
            return payload == null ? null : payload.status;
        } catch (Exception ex) {
            throw new DocuSignVoidException('Unable to parse DocuSign envelope status: ' + body);
        }
    }
}
