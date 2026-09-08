@IsTest
private class DocuSignEnvelopeVoidServiceTest {
    private static final String SENT_ID = '3e2c2af9-cc81-839e-81ce-8cb3848d05ec';
    private static final String COMPLETED_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    private static final String INVALID_STATE_BODY =
        '{"errorCode":"ENVELOPE_CANNOT_VOID_INVALID_STATE","message":"Only envelopes in the \'Sent\' or \'Delivered\' states may be voided."}';

    private class DocuSignVoidMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String body;

        private DocuSignVoidMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            System.assertEquals('PUT', req.getMethod());
            System.assert(req.getEndpoint().contains('/envelopes/'));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    private class DocuSignApiMock implements HttpCalloutMock {
        private final Map<String, String> getStatusByEnvelopeId = new Map<String, String>();
        private final Integer putStatusCode;
        private final String putBody;
        Integer getCalls = 0;
        Integer putCalls = 0;

        private DocuSignApiMock(Integer putStatusCode, String putBody) {
            this.putStatusCode = putStatusCode;
            this.putBody = putBody;
        }

        private DocuSignApiMock withGetStatus(String envelopeId, String status) {
            getStatusByEnvelopeId.put(envelopeId, status);
            return this;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String envelopeId = envelopeIdFromEndpoint(req.getEndpoint());
            if (req.getMethod() == 'GET') {
                getCalls++;
                String status = getStatusByEnvelopeId.containsKey(envelopeId)
                    ? getStatusByEnvelopeId.get(envelopeId)
                    : 'sent';
                if (status == null) {
                    res.setStatusCode(404);
                    res.setBody('{"errorCode":"ENVELOPE_DOES_NOT_EXIST"}');
                    return res;
                }
                res.setStatusCode(200);
                res.setBody('{"status":"' + status + '"}');
                return res;
            }

            putCalls++;
            System.assert(req.getEndpoint().contains('/envelopes/'));
            res.setStatusCode(putStatusCode);
            res.setBody(putBody);
            return res;
        }

        private String envelopeIdFromEndpoint(String endpoint) {
            if (String.isBlank(endpoint)) {
                return null;
            }
            Integer lastSlash = endpoint.lastIndexOf('/');
            return lastSlash < 0 ? endpoint : endpoint.substring(lastSlash + 1);
        }
    }

    @IsTest
    static void voidEnvelopes_withBlankRequests_doesNothing() {
        Test.startTest();
        List<DocuSignEnvelopeVoidService.Result> nullResult =
            DocuSignEnvelopeVoidService.voidEnvelopes(null);
        List<DocuSignEnvelopeVoidService.Result> emptyResult =
            DocuSignEnvelopeVoidService.voidEnvelopes(
                new List<DocuSignEnvelopeVoidService.Request>()
            );
        List<DocuSignEnvelopeVoidService.Result> blankResult =
            DocuSignEnvelopeVoidService.voidEnvelopes(
                new List<DocuSignEnvelopeVoidService.Request>{
                    new DocuSignEnvelopeVoidService.Request()
                }
            );
        Test.stopTest();

        System.assertEquals(0, nullResult.size());
        System.assertEquals(0, emptyResult.size());
        System.assertEquals(1, blankResult.size());
        System.assertEquals(true, blankResult[0].success);
        System.assertEquals(0, blankResult[0].voidedCount);
    }

    @IsTest
    static void voidEnvelope_requiresInputs() {
        try {
            DocuSignEnvelopeVoidService.voidEnvelope(null, 'acc', 'id', 'reason');
            System.assert(false, 'Expected exception');
        } catch (DocuSignEnvelopeVoidService.DocuSignVoidException ex) {
            System.assert(ex.getMessage().contains('required'));
        }
    }

    @IsTest
    static void voidEnvelopes_voidsProvidedRecords() {
        DocuSignApiMock mock = new DocuSignApiMock(200, '{"status":"voided"}')
            .withGetStatus(SENT_ID, 'sent');
        Test.setMock(HttpCalloutMock.class, mock);
        assignTestSettings();

        DocuSignEnvelopeVoidService.Request req = newRequest(
            new List<dfsle__EnvelopeStatus__c>{ statusRec(SENT_ID, 'Sent') }
        );

        Test.startTest();
        List<DocuSignEnvelopeVoidService.Result> results =
            DocuSignEnvelopeVoidService.voidEnvelopes(
                new List<DocuSignEnvelopeVoidService.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(1, results[0].voidedCount);
        System.assertEquals(0, results[0].skippedCount);
        System.assertEquals(1, mock.getCalls);
        System.assertEquals(1, mock.putCalls);
    }

    @IsTest
    static void voidEnvelopes_skipsNonVoidableAndVoidsOpen() {
        DocuSignApiMock mock = new DocuSignApiMock(200, '{"status":"voided"}')
            .withGetStatus(COMPLETED_ID, 'completed')
            .withGetStatus(SENT_ID, 'delivered');
        Test.setMock(HttpCalloutMock.class, mock);
        assignTestSettings();

        DocuSignEnvelopeVoidService.Request req = newRequest(
            new List<dfsle__EnvelopeStatus__c>{
                statusRec(COMPLETED_ID, 'Sent'),
                statusRec(SENT_ID, 'Sent')
            }
        );

        Test.startTest();
        List<DocuSignEnvelopeVoidService.Result> results =
            DocuSignEnvelopeVoidService.voidEnvelopes(
                new List<DocuSignEnvelopeVoidService.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results[0].voidedCount);
        System.assertEquals(1, results[0].skippedCount);
        System.assertEquals(2, mock.getCalls);
        System.assertEquals(1, mock.putCalls);
    }

    @IsTest
    static void voidEnvelopes_skipsInvalidStateOnPut() {
        DocuSignApiMock mock = new DocuSignApiMock(400, INVALID_STATE_BODY)
            .withGetStatus(SENT_ID, 'sent');
        Test.setMock(HttpCalloutMock.class, mock);
        assignTestSettings();

        DocuSignEnvelopeVoidService.Request req = newRequest(
            new List<dfsle__EnvelopeStatus__c>{ statusRec(SENT_ID, 'Sent') }
        );

        Test.startTest();
        List<DocuSignEnvelopeVoidService.Result> results =
            DocuSignEnvelopeVoidService.voidEnvelopes(
                new List<DocuSignEnvelopeVoidService.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(0, results[0].voidedCount);
        System.assertEquals(1, results[0].skippedCount);
        System.assertEquals(1, mock.putCalls);
    }

    @IsTest
    static void voidEnvelope_throwsOnDocuSignError() {
        Test.setMock(HttpCalloutMock.class, new DocuSignVoidMock(400, '{"message":"bad request"}'));

        try {
            DocuSignEnvelopeVoidService.voidEnvelope(
                'DocuSign',
                '12345',
                SENT_ID,
                'Contract Bid completed'
            );
            System.assert(false, 'Expected DocuSignVoidException');
        } catch (DocuSignEnvelopeVoidService.DocuSignVoidException ex) {
            System.assert(ex.getMessage().contains('400'));
        }
    }

    @IsTest
    static void voidEnvelope_returnsFalseOnInvalidState() {
        Test.setMock(HttpCalloutMock.class, new DocuSignVoidMock(400, INVALID_STATE_BODY));

        Test.startTest();
        Boolean voided = DocuSignEnvelopeVoidService.voidEnvelope(
            'DocuSign',
            '12345',
            SENT_ID,
            'Contract Bid completed'
        );
        Test.stopTest();

        System.assertEquals(false, voided);
    }

    @IsTest
    static void helpers_normalizeVoidableStatus() {
        System.assertEquals(true, DocuSignEnvelopeVoidService.isVoidable('Sent'));
        System.assertEquals(true, DocuSignEnvelopeVoidService.isVoidable('delivered'));
        System.assertEquals(false, DocuSignEnvelopeVoidService.isVoidable('completed'));
        System.assertEquals(false, DocuSignEnvelopeVoidService.isVoidable(null));
        System.assertEquals('Completed', DocuSignEnvelopeVoidService.toSalesforceStatus('completed'));
        System.assertEquals(
            true,
            DocuSignEnvelopeVoidService.isNonVoidableStateError(INVALID_STATE_BODY)
        );
        System.assertEquals(
            false,
            DocuSignEnvelopeVoidService.isNonVoidableStateError('{"message":"bad request"}')
        );
    }

    @IsTest
    static void getPreviousOpenEnvelopes_blankId_returnsEmpty() {
        Test.startTest();
        DocuSignEnvelopeVoidService.PreviousOpenEnvelopesResult result =
            DocuSignEnvelopeVoidService.getPreviousOpenEnvelopes(null);
        Test.stopTest();

        System.assertEquals(false, result.hasPrevious);
        System.assertEquals(0, result.previousCount);
        System.assertEquals(true, result.previous.isEmpty());
    }

    @IsTest
    static void isRecent_usesTwentyFourHourWindow() {
        System.assertEquals(true, DocuSignEnvelopeVoidService.isRecent(Datetime.now()));
        System.assertEquals(
            false,
            DocuSignEnvelopeVoidService.isRecent(Datetime.now().addHours(-25))
        );
        System.assertEquals(false, DocuSignEnvelopeVoidService.isRecent(null));
    }

    @IsTest
    static void voidPreviousOpenEnvelopes_noPrevious_returnsZero() {
        Account acc = new Account(Name = 'Void Previous Account');
        insert acc;
        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'Void Previous Bid',
            Customer__c = acc.Id,
            Stage__c = 'Contact Verified and Updated'
        );
        insert bid;

        Test.startTest();
        Integer voidedCount = DocuSignEnvelopeVoidService.voidPreviousOpenEnvelopes(bid.Id);
        Test.stopTest();

        System.assertEquals(0, voidedCount);
    }

    @IsTest
    static void getPreviousOpenEnvelopes_splitsNewestFromPrevious() {
        Account acc = new Account(Name = 'Void Split Account');
        insert acc;
        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'Void Split Bid',
            Customer__c = acc.Id,
            Stage__c = 'Contract Sent via DocuSign'
        );
        insert bid;

        List<dfsle__EnvelopeStatus__c> inserted = insertOpenStatusesIfPossible(bid.Id);
        if (inserted.size() < 2) {
            return;
        }

        Test.startTest();
        DocuSignEnvelopeVoidService.PreviousOpenEnvelopesResult result =
            DocuSignEnvelopeVoidService.getPreviousOpenEnvelopes(bid.Id);
        Test.stopTest();

        System.assertEquals(true, result.hasPrevious);
        System.assertEquals(inserted.size() - 1, result.previousCount);
        System.assertNotEquals(null, result.newest);
        System.assertEquals(true, result.newestIsRecent);
    }

    @IsTest
    static void voidPreviousOpenEnvelopes_voidsPreviousOnly() {
        DocuSignApiMock mock = new DocuSignApiMock(200, '{"status":"voided"}');
        Test.setMock(HttpCalloutMock.class, mock);
        assignTestSettings();

        Account acc = new Account(Name = 'Void Previous Callout Account');
        insert acc;
        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'Void Previous Callout Bid',
            Customer__c = acc.Id,
            Stage__c = 'Contract Sent via DocuSign'
        );
        insert bid;

        List<dfsle__EnvelopeStatus__c> inserted = insertOpenStatusesIfPossible(bid.Id);
        if (inserted.size() < 2) {
            return;
        }

        Test.startTest();
        Integer voidedCount = DocuSignEnvelopeVoidService.voidPreviousOpenEnvelopes(bid.Id);
        Test.stopTest();

        System.assertEquals(inserted.size() - 1, voidedCount);
        System.assertEquals(inserted.size() - 1, mock.putCalls);
    }

    private static void assignTestSettings() {
        DocuSignEnvelopeVoidService.testSettings = new DocuSign_API_Settings__mdt(
            Named_Credential__c = 'DocuSign',
            Account_Id__c = '12345'
        );
    }

    private static DocuSignEnvelopeVoidService.Request newRequest(
        List<dfsle__EnvelopeStatus__c> statuses
    ) {
        DocuSignEnvelopeVoidService.Request req = new DocuSignEnvelopeVoidService.Request();
        req.envelopeStatuses = statuses;
        req.voidReason = 'Contract Bid completed';
        return req;
    }

    private static dfsle__EnvelopeStatus__c statusRec(String docuSignId, String status) {
        return new dfsle__EnvelopeStatus__c(
            dfsle__DocuSignId__c = docuSignId,
            dfsle__Status__c = status
        );
    }

    private static List<dfsle__EnvelopeStatus__c> insertOpenStatusesIfPossible(Id contractBidId) {
        List<dfsle__EnvelopeStatus__c> statuses = new List<dfsle__EnvelopeStatus__c>{
            new dfsle__EnvelopeStatus__c(
                dfsle__DocuSignId__c = '11111111-1111-1111-1111-111111111111',
                dfsle__Status__c = 'Sent',
                dfsle__SourceId__c = contractBidId,
                dfsle__Sent__c = Datetime.now()
            ),
            new dfsle__EnvelopeStatus__c(
                dfsle__DocuSignId__c = '22222222-2222-2222-2222-222222222222',
                dfsle__Status__c = 'Delivered',
                dfsle__SourceId__c = contractBidId,
                dfsle__Sent__c = Datetime.now().addHours(-2)
            )
        };
        try {
            insert statuses;
            return statuses;
        } catch (Exception ex) {
            return new List<dfsle__EnvelopeStatus__c>();
        }
    }
}
