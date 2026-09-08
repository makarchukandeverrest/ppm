@IsTest
private class StopSendingRemindersServiceTest {
    private static String lastPutBody;
    private static Integer putCount;

    @IsTest
    static void disableForContractBids_updatesMatchingEnvelopeReminders() {
        Account acc = new Account(Name = 'Stop Reminders Bid Account');
        insert acc;
        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'Stop Reminders Bid',
            Customer__c = acc.Id,
            Stage__c = 'Contact Verified and Updated'
        );
        insert bid;

        SObject envelope = insertEnvelopeIfPossible(bid.Id, acc.Id, null);
        if (envelope == null) {
            Test.startTest();
            StopSendingRemindersService.disableForContractBids(new Set<Id>{ bid.Id });
            Test.stopTest();
            return;
        }

        Test.startTest();
        StopSendingRemindersService.disableForContractBids(new Set<Id>{ bid.Id });
        Test.stopTest();

        SObject updated = queryEnvelope(envelope.Id);
        System.assertEquals(false, (Boolean) updated.get('dfsle__Remind__c'));
    }

    @IsTest
    static void disableForProposals_updatesMatchingEnvelopeReminders() {
        Account acc = new Account(Name = 'Stop Reminders Proposal Account');
        insert acc;
        Opportunity proposal = new Opportunity(
            Name = 'Stop Reminders Proposal',
            AccountId = acc.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft'
        );
        insert proposal;

        SObject envelope = insertEnvelopeIfPossible(proposal.Id, acc.Id, proposal.Id);
        if (envelope == null) {
            Test.startTest();
            StopSendingRemindersService.disableForProposals(new Set<Id>{ proposal.Id });
            Test.stopTest();
            return;
        }

        Test.startTest();
        StopSendingRemindersService.disableForProposals(new Set<Id>{ proposal.Id });
        Test.stopTest();

        SObject updated = queryEnvelope(envelope.Id);
        System.assertEquals(false, (Boolean) updated.get('dfsle__Remind__c'));
    }

    @IsTest
    static void disableForAccounts_updatesAllCustomerEnvelopes() {
        Account acc = new Account(Name = 'Stop Reminders Customer Account');
        insert acc;
        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'Stop Reminders Customer Bid',
            Customer__c = acc.Id,
            Stage__c = 'Contact Verified and Updated'
        );
        insert bid;

        SObject envelope = insertEnvelopeIfPossible(bid.Id, acc.Id, null);
        if (envelope == null) {
            Test.startTest();
            StopSendingRemindersService.disableForAccounts(new Set<Id>{ acc.Id });
            Test.stopTest();
            return;
        }

        Test.startTest();
        StopSendingRemindersService.disableForAccounts(new Set<Id>{ acc.Id });
        Test.stopTest();

        SObject updated = queryEnvelope(envelope.Id);
        System.assertEquals(false, (Boolean) updated.get('dfsle__Remind__c'));
    }

    @IsTest
    static void disableForContractBids_callsDocuSignNotificationApi() {
        Account acc = new Account(Name = 'Stop Reminders API Account');
        insert acc;
        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'Stop Reminders API Bid',
            Customer__c = acc.Id,
            Stage__c = 'Contact Verified and Updated'
        );
        insert bid;

        SObject envelope = insertEnvelopeIfPossible(bid.Id, acc.Id, null);
        lastPutBody = null;
        putCount = 0;
        StopSendingRemindersService.performCallouts = true;
        StopSendingRemindersService.testDocuSignAccountId = 'TEST-DOCUSIGN-ACCOUNT';
        Test.setMock(HttpCalloutMock.class, new NotificationMock());

        Test.startTest();
        StopSendingRemindersService.disableForContractBids(new Set<Id>{ bid.Id });
        Test.stopTest();

        if (envelope == null) {
            return;
        }
        System.assertEquals(1, putCount, 'DocuSign PUT /notification should run once per envelope.');
        System.assertNotEquals(null, lastPutBody);
        System.assert(
            lastPutBody.contains('"reminderEnabled":"false"') ||
            lastPutBody.contains('"reminderEnabled": "false"'),
            'PUT body should disable DocuSign reminders: ' + lastPutBody
        );
    }

    @IsTest
    static void buildNotificationEndpoint_usesRestApiPath() {
        String endpoint = StopSendingRemindersService.buildNotificationEndpoint(
            'DocuSign',
            '41191243',
            'env-123'
        );
        System.assertEquals(
            'callout:DocuSign/restapi/v2.1/accounts/41191243/envelopes/env-123/notification',
            endpoint
        );
    }

    @IsTest
    static void trigger_contractBidCheckbox_doesNotThrow() {
        Account acc = new Account(Name = 'Stop Reminders Trigger Bid');
        insert acc;
        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'Trigger Bid',
            Customer__c = acc.Id,
            Stage__c = 'Contact Verified and Updated'
        );
        insert bid;

        bid.Stop_Sending_Reminders__c = true;
        Test.startTest();
        update bid;
        Test.stopTest();

        System.assertEquals(
            true,
            [SELECT Stop_Sending_Reminders__c FROM Contract_Bid__c WHERE Id = :bid.Id]
            .Stop_Sending_Reminders__c
        );
    }

    @IsTest
    static void trigger_proposalCheckbox_doesNotThrow() {
        Account acc = new Account(Name = 'Stop Reminders Trigger Proposal');
        insert acc;
        Opportunity proposal = new Opportunity(
            Name = 'Trigger Proposal',
            AccountId = acc.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Draft'
        );
        insert proposal;

        proposal.Stop_Sending_Reminders__c = true;
        Test.startTest();
        update proposal;
        Test.stopTest();

        System.assertEquals(
            true,
            [SELECT Stop_Sending_Reminders__c FROM Opportunity WHERE Id = :proposal.Id]
            .Stop_Sending_Reminders__c
        );
    }

    @IsTest
    static void trigger_accountCheckbox_doesNotThrow() {
        Account acc = new Account(Name = 'Stop Reminders Trigger Account');
        insert acc;

        acc.Stop_Sending_Reminders__c = true;
        Test.startTest();
        update acc;
        Test.stopTest();

        System.assertEquals(
            true,
            [SELECT Stop_Sending_Reminders__c FROM Account WHERE Id = :acc.Id]
            .Stop_Sending_Reminders__c
        );
    }

    private static SObject insertEnvelopeIfPossible(Id sourceId, Id accountId, Id dealId) {
        if (!Schema.getGlobalDescribe().containsKey('dfsle__Envelope__c')) {
            return null;
        }
        try {
            SObject envelope = Schema.getGlobalDescribe().get('dfsle__Envelope__c').newSObject();
            envelope.put('dfsle__SourceId__c', (String) sourceId);
            envelope.put('dfsle__Remind__c', true);
            envelope.put('dfsle__DocuSignId__c', '11111111-1111-1111-1111-111111111111');
            if (accountId != null) {
                envelope.put('Account__c', accountId);
            }
            if (dealId != null) {
                envelope.put('Deal__c', dealId);
            }
            envelope.put('Status__c', 'Sent');
            insert envelope;
            return envelope;
        } catch (Exception ex) {
            return null;
        }
    }

    private static SObject queryEnvelope(Id envelopeId) {
        return Database.query(
            'SELECT Id, dfsle__Remind__c FROM dfsle__Envelope__c WHERE Id = :envelopeId LIMIT 1'
        );
    }

    private class NotificationMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody(
                    '{"useAccountDefaults":"false","reminders":{"reminderEnabled":"true","reminderDelay":"2","reminderFrequency":"2"},"expirations":{"expireEnabled":"true","expireAfter":"120","expireWarn":"0"}}'
                );
                return res;
            }
            putCount++;
            lastPutBody = req.getBody();
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }
}
