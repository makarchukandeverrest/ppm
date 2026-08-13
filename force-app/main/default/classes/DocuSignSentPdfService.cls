public with sharing class DocuSignSentPdfService {

    // Sandbox: DocuSign (demo.docusign.net). Production: ArtemDocuDevCredential (na4) — see DocuSignTests.cls.
    @TestVisible
    private static final String SANDBOX_NAMED_CREDENTIAL = 'DocuSign';

    @TestVisible
    private static final String SANDBOX_AUTH_NAMED_CREDENTIAL = 'DocuSignAuth';

    @TestVisible
    private static final String PRODUCTION_NAMED_CREDENTIAL = 'ArtemDocuDevCredential';

    @TestVisible
    private static final String PRODUCTION_DOCUSIGN_ACCOUNT_ID = '41191243';

    @TestVisible
    private static Boolean skipCalloutInTest = false;

    @TestVisible
    private static Blob testPdfBlob;

    @TestVisible
    private static String testDocuSignAccountId;

    public class DocuSignSentPdfException extends Exception {
    }

    public static void saveSentPdfFromEnvelope(
        Id accountId,
        Id sourceContentVersionId,
        String envelopeId
    ) {
        if (accountId == null || sourceContentVersionId == null || String.isBlank(envelopeId)) {
            return;
        }

        ContentVersion sourceCv = querySourceContentVersion(sourceContentVersionId);
        if (sourceCv == null || !requiresSentPdfCopy(sourceCv)) {
            return;
        }

        String pdfTitle = buildPdfTitle(sourceCv.Title);
        if (String.isBlank(pdfTitle)) {
            return;
        }

        Blob pdfBlob = fetchEnvelopeDocumentPdf(envelopeId);
        if (pdfBlob == null || pdfBlob.size() == 0) {
            throw new DocuSignSentPdfException(
                'DocuSign returned an empty PDF for envelope ' + envelopeId
            );
        }

        removeExistingPdfOnAccount(accountId, pdfTitle);

        ContentVersion pdfCv = new ContentVersion(
            Title = pdfTitle,
            PathOnClient = pdfTitle,
            VersionData = pdfBlob,
            IsMajorVersion = true,
            To_Sent__c = false,
            DocuSign_Envelope_Status__c = 'Sent'
        );
        insert pdfCv;

        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :pdfCv.Id
            LIMIT 1
        ].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = accountId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    @TestVisible
    private static ContentVersion querySourceContentVersion(Id sourceContentVersionId) {
        List<ContentVersion> rows = [
            SELECT Id, Title, FileExtension
            FROM ContentVersion
            WHERE Id = :sourceContentVersionId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public static Boolean requiresSentPdfCopy(ContentVersion sourceCv) {
        if (sourceCv == null || String.isBlank(sourceCv.FileExtension)) {
            return false;
        }
        return sourceCv.FileExtension.toLowerCase() != 'pdf';
    }

    @TestVisible
    private static String buildPdfTitle(String sourceTitle) {
        if (String.isBlank(sourceTitle)) {
            return null;
        }

        String normalizedTitle = sourceTitle.trim();
        String lowerTitle = normalizedTitle.toLowerCase();

        if (lowerTitle.endsWith('.docx')) {
            return normalizedTitle.substring(0, normalizedTitle.length() - 5) + '.pdf';
        }
        if (lowerTitle.endsWith('.doc')) {
            return normalizedTitle.substring(0, normalizedTitle.length() - 4) + '.pdf';
        }

        return normalizedTitle + '.pdf';
    }

    @TestVisible
    private static void removeExistingPdfOnAccount(Id accountId, String pdfTitle) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :accountId
        ];
        if (links.isEmpty()) {
            return;
        }

        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            contentDocumentIds.add(link.ContentDocumentId);
        }

        List<ContentVersion> existingPdfs = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
            AND IsLatest = true
            AND Title = :pdfTitle
        ];
        if (existingPdfs.isEmpty()) {
            return;
        }

        Set<Id> documentsToDelete = new Set<Id>();
        for (ContentVersion existingPdf : existingPdfs) {
            documentsToDelete.add(existingPdf.ContentDocumentId);
        }
        delete [SELECT Id FROM ContentDocument WHERE Id IN :documentsToDelete];
    }

    @TestVisible
    private static Boolean isSandboxOrg() {
        return [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
    }

    @TestVisible
    private static String resolveNamedCredential() {
        if (Test.isRunningTest()) {
            return SANDBOX_NAMED_CREDENTIAL;
        }
        return isSandboxOrg() ? SANDBOX_NAMED_CREDENTIAL : PRODUCTION_NAMED_CREDENTIAL;
    }

    @TestVisible
    private static String resolveDocuSignAccountId() {
        if (Test.isRunningTest() && String.isNotBlank(testDocuSignAccountId)) {
            return testDocuSignAccountId;
        }
        if (!isSandboxOrg()) {
            return PRODUCTION_DOCUSIGN_ACCOUNT_ID;
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + SANDBOX_AUTH_NAMED_CREDENTIAL + '/oauth/userinfo');
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200) {
            throw new DocuSignSentPdfException(
                'Could not resolve DocuSign accountId: GET /oauth/userinfo status=' +
                response.getStatusCode() +
                ' body=' +
                response.getBody()
            );
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        List<Object> accounts = (List<Object>) payload.get('accounts');
        if (accounts == null || accounts.isEmpty()) {
            throw new DocuSignSentPdfException(
                'Could not resolve DocuSign accountId: GET /oauth/userinfo returned no accounts'
            );
        }

        for (Object row : accounts) {
            Map<String, Object> accountRow = (Map<String, Object>) row;
            Object isDefault = accountRow.get('is_default');
            if (isDefault == true || 'true'.equalsIgnoreCase(String.valueOf(isDefault))) {
                return String.valueOf(accountRow.get('account_id'));
            }
        }

        Map<String, Object> firstAccount = (Map<String, Object>) accounts[0];
        return String.valueOf(firstAccount.get('account_id'));
    }

    @TestVisible
    private static Blob fetchEnvelopeDocumentPdf(String envelopeId) {
        if (Test.isRunningTest() && skipCalloutInTest == true) {
            return testPdfBlob != null ? testPdfBlob : Blob.valueOf('%PDF-1.4 test sent pdf');
        }

        String normalizedEnvelopeId = normalizeEnvelopeId(envelopeId);
        String namedCredential = resolveNamedCredential();
        String docuSignAccountId = resolveDocuSignAccountId();
        List<String> attemptErrors = new List<String>();

        List<String> documentIds = listEnvelopeDocumentIds(
            namedCredential,
            docuSignAccountId,
            normalizedEnvelopeId,
            attemptErrors
        );
        for (String documentId : documentIds) {
            Blob pdfBlob = tryDownloadDocument(
                namedCredential,
                docuSignAccountId,
                normalizedEnvelopeId,
                documentId,
                attemptErrors
            );
            if (pdfBlob != null) {
                return pdfBlob;
            }
        }

        Blob pdfBlob = tryDownloadDocument(
            namedCredential,
            docuSignAccountId,
            normalizedEnvelopeId,
            'combined',
            attemptErrors
        );
        if (pdfBlob != null) {
            return pdfBlob;
        }

        throw new DocuSignSentPdfException(
            'DocuSign PDF download failed for envelope ' +
            normalizedEnvelopeId +
            '. ' +
            String.join(attemptErrors, ' | ')
        );
    }

    @TestVisible
    private static String normalizeEnvelopeId(String envelopeId) {
        return envelopeId.trim();
    }

    @TestVisible
    private static Blob tryDownloadDocument(
        String namedCredential,
        String accountId,
        String envelopeId,
        String documentId,
        List<String> attemptErrors
    ) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(
            buildDocumentEndpoint(namedCredential, accountId, envelopeId, documentId)
        );
        request.setMethod('GET');
        request.setHeader('Accept', 'application/pdf');

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() == 200) {
            Blob body = response.getBodyAsBlob();
            if (body != null && body.size() > 0) {
                return body;
            }
            attemptErrors.add('GET documents/' + documentId + ' returned empty body');
            return null;
        }

        attemptErrors.add(
            'GET documents/' +
            documentId +
            ' status=' +
            response.getStatusCode() +
            ' body=' +
            response.getBody()
        );
        return null;
    }

    @TestVisible
    private static String buildDocumentEndpoint(
        String namedCredential,
        String accountId,
        String envelopeId,
        String documentId
    ) {
        return 'callout:' +
            namedCredential +
            '/restapi/v2.1/accounts/' +
            accountId +
            '/envelopes/' +
            envelopeId +
            '/documents/' +
            documentId +
            '?watermark=false';
    }

    @TestVisible
    private static List<String> listEnvelopeDocumentIds(
        String namedCredential,
        String accountId,
        String envelopeId,
        List<String> attemptErrors
    ) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(
            'callout:' +
            namedCredential +
            '/restapi/v2.1/accounts/' +
            accountId +
            '/envelopes/' +
            envelopeId +
            '/documents'
        );
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200) {
            attemptErrors.add(
                'GET documents list status=' +
                response.getStatusCode() +
                ' body=' +
                response.getBody()
            );
            return new List<String>{ '1' };
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        List<Object> envelopeDocuments = (List<Object>) payload.get('envelopeDocuments');
        if (envelopeDocuments == null || envelopeDocuments.isEmpty()) {
            attemptErrors.add('GET documents list returned no envelopeDocuments');
            return new List<String>{ '1' };
        }

        List<String> documentIds = new List<String>();
        for (Object row : envelopeDocuments) {
            Map<String, Object> documentRow = (Map<String, Object>) row;
            String type = documentRow.containsKey('type') ? String.valueOf(documentRow.get('type')) : null;
            if (type == 'summary' || type == 'certificate') {
                continue;
            }
            if (documentRow.containsKey('documentId')) {
                documentIds.add(String.valueOf(documentRow.get('documentId')));
            }
        }

        if (documentIds.isEmpty()) {
            return new List<String>{ '1' };
        }
        return documentIds;
    }
}
