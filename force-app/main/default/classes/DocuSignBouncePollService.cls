public with sharing class DocuSignBouncePollService {
    @TestVisible
    private static final String SANDBOX_NAMED_CREDENTIAL = 'DocuSign';

    @TestVisible
    private static final String SANDBOX_AUTH_NAMED_CREDENTIAL = 'DocuSignAuth';

    @TestVisible
    private static final String PRODUCTION_NAMED_CREDENTIAL = 'ArtemDocuDevCredential';

    @TestVisible
    private static final String PRODUCTION_DOCUSIGN_ACCOUNT_ID = '78090461';

    @TestVisible
    private static final String STATUS_AUTO_RESPONDED = 'AutoResponded';

    private static final List<String> RECIPIENT_COLLECTION_KEYS = new List<String>{
        'signers',
        'carbonCopies',
        'certifiedDeliveries',
        'agents',
        'editors',
        'inPersonSigners',
        'intermediaries',
        'witnesses'
    };

    @TestVisible
    private static Boolean skipCalloutInTest = false;

    @TestVisible
    private static String testDocuSignAccountId;

    @TestVisible
    private static Map<String, String> testRecipientsJsonByEnvelopeId = new Map<String, String>();

    public static final Integer LOOKBACK_DAYS = 45;

    public class DocuSignBouncePollException extends Exception {
    }

    public static void stampExistingAutoResponded() {
        List<dfsle__RecipientStatus__c> alreadyBounced = [
            SELECT
                Id,
                dfsle__Email__c,
                dfsle__Status__c,
                dfsle__Reason__c,
                Email_Bounced__c,
                Bounce_Reason__c,
                dfsle__EnvelopeStatus__c,
                dfsle__EnvelopeStatus__r.dfsle__DocuSignId__c
            FROM dfsle__RecipientStatus__c
            WHERE Email_Bounced__c = FALSE AND dfsle__Status__c = :STATUS_AUTO_RESPONDED
        ];
        processRecipients(alreadyBounced);
    }

    public static void processRecipients(List<dfsle__RecipientStatus__c> recipients) {
        if (recipients == null || recipients.isEmpty()) {
            return;
        }

        List<dfsle__RecipientStatus__c> alreadyBounced = new List<dfsle__RecipientStatus__c>();
        Map<String, List<dfsle__RecipientStatus__c>> recipientsByEnvelopeId =
            new Map<String, List<dfsle__RecipientStatus__c>>();

        for (dfsle__RecipientStatus__c recipient : recipients) {
            if (recipient == null || recipient.Email_Bounced__c == true) {
                continue;
            }

            if (STATUS_AUTO_RESPONDED.equalsIgnoreCase(recipient.dfsle__Status__c)) {
                alreadyBounced.add(stampBounce(recipient, recipient.Bounce_Reason__c));
                continue;
            }

            String envelopeId = recipient.dfsle__EnvelopeStatus__r == null
                ? null
                : recipient.dfsle__EnvelopeStatus__r.dfsle__DocuSignId__c;
            if (String.isBlank(envelopeId) || String.isBlank(recipient.dfsle__Email__c)) {
                continue;
            }

            String normalizedEnvelopeId = envelopeId.trim();
            if (!recipientsByEnvelopeId.containsKey(normalizedEnvelopeId)) {
                recipientsByEnvelopeId.put(
                    normalizedEnvelopeId,
                    new List<dfsle__RecipientStatus__c>()
                );
            }
            recipientsByEnvelopeId.get(normalizedEnvelopeId).add(recipient);
        }

        List<dfsle__RecipientStatus__c> toUpdate = new List<dfsle__RecipientStatus__c>();
        toUpdate.addAll(alreadyBounced);

        if (!recipientsByEnvelopeId.isEmpty()) {
            String namedCredential = resolveNamedCredential();
            String docuSignAccountId = (Test.isRunningTest() && skipCalloutInTest == true)
                ? 'TEST_ACCOUNT'
                : resolveDocuSignAccountId();

            for (String envelopeId : recipientsByEnvelopeId.keySet()) {
                Map<String, String> bounceReasonByEmail = fetchBounceReasons(
                    namedCredential,
                    docuSignAccountId,
                    envelopeId
                );
                if (bounceReasonByEmail.isEmpty()) {
                    continue;
                }

                for (dfsle__RecipientStatus__c recipient : recipientsByEnvelopeId.get(envelopeId)) {
                    String emailKey = normalizeEmail(recipient.dfsle__Email__c);
                    if (!bounceReasonByEmail.containsKey(emailKey)) {
                        continue;
                    }
                    toUpdate.add(stampBounce(recipient, bounceReasonByEmail.get(emailKey)));
                }
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    @TestVisible
    private static dfsle__RecipientStatus__c stampBounce(
        dfsle__RecipientStatus__c recipient,
        String reason
    ) {
        recipient.dfsle__Status__c = STATUS_AUTO_RESPONDED;
        recipient.Email_Bounced__c = true;
        recipient.Bounced_Detected_At__c = System.now();
        recipient.dfsle__LastStatusUpdate__c = System.now();

        String normalizedReason = truncateReason(reason);
        if (String.isNotBlank(normalizedReason)) {
            recipient.Bounce_Reason__c = normalizedReason;
            if (String.isBlank(recipient.dfsle__Reason__c)) {
                recipient.dfsle__Reason__c = normalizedReason;
            }
        }
        return recipient;
    }

    @TestVisible
    private static Map<String, String> fetchBounceReasons(
        String namedCredential,
        String accountId,
        String envelopeId
    ) {
        Map<String, String> bounceReasonByEmail = new Map<String, String>();
        String jsonBody = fetchRecipientsJson(namedCredential, accountId, envelopeId);
        if (String.isBlank(jsonBody)) {
            return bounceReasonByEmail;
        }

        Map<String, Object> payload;
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        } catch (Exception parseError) {
            System.debug(
                LoggingLevel.WARN,
                'DocuSign bounce poll: could not parse recipients JSON for envelope ' +
                envelopeId +
                ': ' +
                parseError.getMessage()
            );
            return bounceReasonByEmail;
        }

        if (payload == null) {
            return bounceReasonByEmail;
        }

        for (String collectionKey : RECIPIENT_COLLECTION_KEYS) {
            List<Object> rows = (List<Object>) payload.get(collectionKey);
            if (rows == null) {
                continue;
            }
            for (Object row : rows) {
                Map<String, Object> recipientRow = (Map<String, Object>) row;
                if (recipientRow == null) {
                    continue;
                }
                String status = recipientRow.containsKey('status')
                    ? String.valueOf(recipientRow.get('status'))
                    : null;
                if (!STATUS_AUTO_RESPONDED.equalsIgnoreCase(status)) {
                    continue;
                }
                String emailKey = normalizeEmail(
                    recipientRow.containsKey('email') ? String.valueOf(recipientRow.get('email')) : null
                );
                if (String.isBlank(emailKey)) {
                    continue;
                }
                String reason = recipientRow.containsKey('autoRespondedReason')
                    ? String.valueOf(recipientRow.get('autoRespondedReason'))
                    : null;
                bounceReasonByEmail.put(emailKey, reason);
            }
        }

        return bounceReasonByEmail;
    }

    @TestVisible
    private static String fetchRecipientsJson(
        String namedCredential,
        String accountId,
        String envelopeId
    ) {
        if (Test.isRunningTest() && skipCalloutInTest == true) {
            return testRecipientsJsonByEnvelopeId.get(envelopeId);
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(buildRecipientsEndpoint(namedCredential, accountId, envelopeId));
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(120000);

        try {
            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() != 200) {
                System.debug(
                    LoggingLevel.WARN,
                    'DocuSign bounce poll: GET recipients envelope=' +
                    envelopeId +
                    ' status=' +
                    response.getStatusCode() +
                    ' body=' +
                    response.getBody()
                );
                return null;
            }
            return response.getBody();
        } catch (Exception calloutError) {
            System.debug(
                LoggingLevel.WARN,
                'DocuSign bounce poll: callout failed for envelope ' +
                envelopeId +
                ': ' +
                calloutError.getMessage()
            );
            return null;
        }
    }

    @TestVisible
    private static String buildRecipientsEndpoint(
        String namedCredential,
        String accountId,
        String envelopeId
    ) {
        return 'callout:' +
            namedCredential +
            '/restapi/v2.1/accounts/' +
            accountId +
            '/envelopes/' +
            envelopeId +
            '/recipients';
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
            throw new DocuSignBouncePollException(
                'Could not resolve DocuSign accountId: GET /oauth/userinfo status=' +
                response.getStatusCode() +
                ' body=' +
                response.getBody()
            );
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        List<Object> accounts = (List<Object>) payload.get('accounts');
        if (accounts == null || accounts.isEmpty()) {
            throw new DocuSignBouncePollException(
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
    private static String normalizeEmail(String email) {
        return String.isBlank(email) ? null : email.trim().toLowerCase();
    }

    @TestVisible
    private static String truncateReason(String reason) {
        if (String.isBlank(reason) || reason == 'null') {
            return null;
        }
        String trimmed = reason.trim();
        return trimmed.length() <= 255 ? trimmed : trimmed.substring(0, 255);
    }
}
