@IsTest
private class DocuSignEnvelopeVoidServiceTest {
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

    @IsTest
    static void voidEnvelopes_withBlankRequests_doesNothing() {
        Test.startTest();
        DocuSignEnvelopeVoidService.voidEnvelopes(null);
        DocuSignEnvelopeVoidService.voidEnvelopes(new List<DocuSignEnvelopeVoidService.Request>());
        DocuSignEnvelopeVoidService.voidEnvelopes(
            new List<DocuSignEnvelopeVoidService.Request>{ new DocuSignEnvelopeVoidService.Request() }
        );
        Test.stopTest();
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
        Test.setMock(HttpCalloutMock.class, new DocuSignVoidMock(200, '{"status":"voided"}'));
        DocuSignEnvelopeVoidService.testSettings = new DocuSign_API_Settings__mdt(
            Named_Credential__c = 'DocuSign',
            Account_Id__c = '12345'
        );

        dfsle__EnvelopeStatus__c statusRec = new dfsle__EnvelopeStatus__c(
            dfsle__DocuSignId__c = '3e2c2af9-cc81-839e-81ce-8cb3848d05ec',
            dfsle__Status__c = 'Sent'
        );

        DocuSignEnvelopeVoidService.Request req = new DocuSignEnvelopeVoidService.Request();
        req.envelopeStatuses = new List<dfsle__EnvelopeStatus__c>{ statusRec };
        req.voidReason = 'Contract Bid completed';

        Test.startTest();
        DocuSignEnvelopeVoidService.voidEnvelopes(
            new List<DocuSignEnvelopeVoidService.Request>{ req }
        );
        Test.stopTest();
    }

    @IsTest
    static void voidEnvelope_throwsOnDocuSignError() {
        Test.setMock(HttpCalloutMock.class, new DocuSignVoidMock(400, '{"message":"bad request"}'));

        try {
            DocuSignEnvelopeVoidService.voidEnvelope(
                'DocuSign',
                '12345',
                '3e2c2af9-cc81-839e-81ce-8cb3848d05ec',
                'Contract Bid completed'
            );
            System.assert(false, 'Expected DocuSignVoidException');
        } catch (DocuSignEnvelopeVoidService.DocuSignVoidException ex) {
            System.assert(ex.getMessage().contains('400'));
        }
    }
}
