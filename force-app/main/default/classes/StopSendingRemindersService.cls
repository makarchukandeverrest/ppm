public without sharing class StopSendingRemindersService {
    private static final String ENVELOPE_OBJECT = 'dfsle__Envelope__c';
    private static final String ENVELOPE_STATUS_OBJECT = 'dfsle__EnvelopeStatus__c';
    private static final Set<String> TERMINAL_STATUSES = new Set<String>{
        'completed',
        'voided',
        'declined',
        'deleted'
    };

    @TestVisible
    private static final String SANDBOX_NAMED_CREDENTIAL = 'DocuSign';
    @TestVisible
    private static final String SANDBOX_AUTH_NAMED_CREDENTIAL = 'DocuSignAuth';
    @TestVisible
    private static final String PRODUCTION_NAMED_CREDENTIAL = 'ArtemDocuDevCredential';
    @TestVisible
    private static final String PRODUCTION_DOCUSIGN_ACCOUNT_ID = '41191243';

    private static final Integer ENVELOPES_PER_JOB = 40;

    @TestVisible
    static Boolean performCallouts = !Test.isRunningTest();

    @TestVisible
    static String testDocuSignAccountId;

    public class DocuSignNotificationException extends Exception {
    }

    public static void disableForContractBids(Set<Id> bidIds) {
        if (bidIds == null || bidIds.isEmpty()) {
            return;
        }
        disableDocuSignReminders(collectEnvelopeIdsForBids(bidIds));
    }

    public static void disableForAccounts(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }
        disableDocuSignReminders(collectEnvelopeIdsForAccounts(accountIds));
    }

    public static void disableForProposals(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }
        disableDocuSignReminders(collectEnvelopeIdsForProposals(opportunityIds));
    }

    public class Job implements Queueable, Database.AllowsCallouts {
        private List<String> envelopeIds;

        public Job(List<String> envelopeIds) {
            this.envelopeIds = envelopeIds == null ? new List<String>() : envelopeIds;
        }

        public void execute(QueueableContext context) {
            if (envelopeIds.isEmpty()) {
                return;
            }

            Integer endIndex = Math.min(ENVELOPES_PER_JOB, envelopeIds.size());
            List<String> currentBatch = new List<String>();
            for (Integer i = 0; i < endIndex; i++) {
                currentBatch.add(envelopeIds[i]);
            }

            if (performCallouts == true) {
                disableRemindersInDocuSign(currentBatch);
            }

            if (endIndex < envelopeIds.size()) {
                List<String> remaining = new List<String>();
                for (Integer i = endIndex; i < envelopeIds.size(); i++) {
                    remaining.add(envelopeIds[i]);
                }
                System.enqueueJob(new Job(remaining));
            }
        }
    }

    private static void disableDocuSignReminders(Set<String> envelopeIds) {
        if (envelopeIds == null || envelopeIds.isEmpty()) {
            return;
        }
        System.enqueueJob(new Job(new List<String>(envelopeIds)));
    }

    private static Set<String> collectEnvelopeIdsForBids(Set<Id> bidIds) {
        Set<String> sourceIds = toStrings(bidIds);
        Set<String> envelopeIds = new Set<String>();
        envelopeIds.addAll(
            queryEnvelopeDocuSignIds('dfsle__SourceId__c IN :sourceIds', sourceIds, null, null)
        );
        envelopeIds.addAll(
            queryStatusDocuSignIds('dfsle__SourceId__c IN :sourceIds', sourceIds, null)
        );
        return envelopeIds;
    }

    private static Set<String> collectEnvelopeIdsForAccounts(Set<Id> accountIds) {
        Set<String> sourceIds = new Set<String>();
        for (Contract_Bid__c bid : [
            SELECT Id
            FROM Contract_Bid__c
            WHERE Customer__c IN :accountIds
        ]) {
            sourceIds.add((String) bid.Id);
        }

        Set<Id> dealIds = new Set<Id>();
        for (Opportunity opp : [
            SELECT Id
            FROM Opportunity
            WHERE AccountId IN :accountIds
        ]) {
            dealIds.add(opp.Id);
        }

        List<String> envelopeFilters = new List<String>{ 'Account__c IN :accountIds' };
        if (!sourceIds.isEmpty()) {
            envelopeFilters.add('dfsle__SourceId__c IN :sourceIds');
        }
        if (!dealIds.isEmpty()) {
            envelopeFilters.add('Deal__c IN :dealIds');
        }

        Set<String> envelopeIds = new Set<String>();
        envelopeIds.addAll(
            queryEnvelopeDocuSignIds(
                String.join(envelopeFilters, ' OR '),
                sourceIds,
                accountIds,
                dealIds
            )
        );

        List<String> statusFilters = new List<String>();
        if (!sourceIds.isEmpty()) {
            statusFilters.add('dfsle__SourceId__c IN :sourceIds');
        }
        if (!dealIds.isEmpty()) {
            statusFilters.add('dfsle__Opportunity__c IN :dealIds');
        }
        if (!statusFilters.isEmpty()) {
            envelopeIds.addAll(
                queryStatusDocuSignIds(String.join(statusFilters, ' OR '), sourceIds, dealIds)
            );
        }
        return envelopeIds;
    }

    private static Set<String> collectEnvelopeIdsForProposals(Set<Id> opportunityIds) {
        Set<String> sourceIds = toStrings(opportunityIds);
        Set<String> envelopeIds = new Set<String>();
        envelopeIds.addAll(
            queryEnvelopeDocuSignIds(
                'Deal__c IN :dealIds OR dfsle__SourceId__c IN :sourceIds',
                sourceIds,
                null,
                opportunityIds
            )
        );
        envelopeIds.addAll(
            queryStatusDocuSignIds(
                'dfsle__Opportunity__c IN :dealIds OR dfsle__SourceId__c IN :sourceIds',
                sourceIds,
                opportunityIds
            )
        );
        return envelopeIds;
    }

    private static Set<String> queryEnvelopeDocuSignIds(
        String filter,
        Set<String> sourceIds,
        Set<Id> accountIds,
        Set<Id> dealIds
    ) {
        Set<String> envelopeIds = new Set<String>();
        if (!hasObject(ENVELOPE_OBJECT) || String.isBlank(filter)) {
            return envelopeIds;
        }

        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(ENVELOPE_OBJECT)
            .getDescribe()
            .fields.getMap();
        List<String> selectFields = new List<String>{ 'Id', 'dfsle__DocuSignId__c' };
        if (fieldMap.containsKey('dfsle__remind__c')) {
            selectFields.add('dfsle__Remind__c');
        }
        if (fieldMap.containsKey('status__c')) {
            selectFields.add('Status__c');
        }

        List<SObject> envelopes;
        try {
            envelopes = Database.query(
                'SELECT ' +
                String.join(selectFields, ', ') +
                ' FROM dfsle__Envelope__c ' +
                'WHERE dfsle__DocuSignId__c != null AND (' +
                filter +
                ')'
            );
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'DocuSign envelope lookup failed: ' + ex.getMessage()
            );
            return envelopeIds;
        }

        List<SObject> toUpdate = new List<SObject>();
        for (SObject envelope : envelopes) {
            String statusValue = fieldMap.containsKey('status__c')
                ? (String) envelope.get('Status__c')
                : null;
            if (isTerminalStatus(statusValue)) {
                continue;
            }
            addEnvelopeId(envelopeIds, (String) envelope.get('dfsle__DocuSignId__c'));
            if (
                fieldMap.containsKey('dfsle__remind__c') &&
                (Boolean) envelope.get('dfsle__Remind__c') != false
            ) {
                envelope.put('dfsle__Remind__c', false);
                toUpdate.add(envelope);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return envelopeIds;
    }

    private static Set<String> queryStatusDocuSignIds(
        String filter,
        Set<String> sourceIds,
        Set<Id> dealIds
    ) {
        Set<String> envelopeIds = new Set<String>();
        if (!hasObject(ENVELOPE_STATUS_OBJECT) || String.isBlank(filter)) {
            return envelopeIds;
        }

        try {
            Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
                .get(ENVELOPE_STATUS_OBJECT)
                .getDescribe()
                .fields.getMap();
            List<String> selectFields = new List<String>{ 'dfsle__DocuSignId__c' };
            if (fieldMap.containsKey('dfsle__status__c')) {
                selectFields.add('dfsle__Status__c');
            }

            List<SObject> statuses = Database.query(
                'SELECT ' +
                String.join(selectFields, ', ') +
                ' FROM dfsle__EnvelopeStatus__c ' +
                'WHERE dfsle__DocuSignId__c != null AND (' +
                filter +
                ')'
            );
            for (SObject statusRow : statuses) {
                String statusValue = fieldMap.containsKey('dfsle__status__c')
                    ? (String) statusRow.get('dfsle__Status__c')
                    : null;
                if (isTerminalStatus(statusValue)) {
                    continue;
                }
                addEnvelopeId(envelopeIds, (String) statusRow.get('dfsle__DocuSignId__c'));
            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.FINER,
                'DocuSign envelope status lookup skipped: ' + ex.getMessage()
            );
        }
        return envelopeIds;
    }

    @TestVisible
    static void disableRemindersInDocuSign(List<String> envelopeIds) {
        if (envelopeIds == null || envelopeIds.isEmpty()) {
            return;
        }

        String namedCredential = resolveNamedCredential();
        String docuSignAccountId = resolveDocuSignAccountId();

        for (String envelopeId : envelopeIds) {
            if (String.isBlank(envelopeId)) {
                continue;
            }
            try {
                disableReminderForEnvelope(namedCredential, docuSignAccountId, envelopeId.trim());
            } catch (Exception ex) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Failed to disable DocuSign reminders for envelope ' +
                    envelopeId +
                    ': ' +
                    ex.getMessage()
                );
            }
        }
    }

    private static void disableReminderForEnvelope(
        String namedCredential,
        String accountId,
        String envelopeId
    ) {
        String endpoint = buildNotificationEndpoint(namedCredential, accountId, envelopeId);

        Map<String, Object> payload = getNotificationSettings(endpoint);
        payload.put('useAccountDefaults', 'false');

        Map<String, Object> reminders = payload.containsKey('reminders')
            ? (Map<String, Object>) payload.get('reminders')
            : new Map<String, Object>();
        if (reminders == null) {
            reminders = new Map<String, Object>();
        }
        reminders.put('reminderEnabled', 'false');
        reminders.put('reminderDelay', '0');
        reminders.put('reminderFrequency', '0');
        payload.put('reminders', reminders);

        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('PUT');
        request.setHeader('Accept', 'application/json');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(payload));
        request.setTimeout(120000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new DocuSignNotificationException(
                'PUT notification status=' +
                response.getStatusCode() +
                ' body=' +
                response.getBody()
            );
        }
    }

    private static Map<String, Object> getNotificationSettings(String endpoint) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(120000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200 || String.isBlank(response.getBody())) {
            return new Map<String, Object>();
        }

        Object parsed = JSON.deserializeUntyped(response.getBody());
        if (parsed instanceof Map<String, Object>) {
            return (Map<String, Object>) parsed;
        }
        return new Map<String, Object>();
    }

    @TestVisible
    static String buildNotificationEndpoint(
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
            '/notification';
    }

    @TestVisible
    static String resolveNamedCredential() {
        if (Test.isRunningTest()) {
            return SANDBOX_NAMED_CREDENTIAL;
        }
        return isSandboxOrg() ? SANDBOX_NAMED_CREDENTIAL : PRODUCTION_NAMED_CREDENTIAL;
    }

    @TestVisible
    static String resolveDocuSignAccountId() {
        if (Test.isRunningTest() && String.isNotBlank(testDocuSignAccountId)) {
            return testDocuSignAccountId;
        }
        if (Test.isRunningTest()) {
            return 'TEST-DOCUSIGN-ACCOUNT';
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
            throw new DocuSignNotificationException(
                'Could not resolve DocuSign accountId: GET /oauth/userinfo status=' +
                response.getStatusCode() +
                ' body=' +
                response.getBody()
            );
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        List<Object> accounts = (List<Object>) payload.get('accounts');
        if (accounts == null || accounts.isEmpty()) {
            throw new DocuSignNotificationException(
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

    private static Boolean isSandboxOrg() {
        return [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
    }

    private static Boolean isTerminalStatus(String status) {
        return String.isNotBlank(status) && TERMINAL_STATUSES.contains(status.trim().toLowerCase());
    }

    private static void addEnvelopeId(Set<String> envelopeIds, String envelopeId) {
        if (String.isNotBlank(envelopeId)) {
            envelopeIds.add(envelopeId.trim());
        }
    }

    private static Boolean hasObject(String objectName) {
        return Schema.getGlobalDescribe().containsKey(objectName);
    }

    private static Set<String> toStrings(Set<Id> ids) {
        Set<String> values = new Set<String>();
        for (Id recordId : ids) {
            if (recordId != null) {
                values.add((String) recordId);
            }
        }
        return values;
    }
}
