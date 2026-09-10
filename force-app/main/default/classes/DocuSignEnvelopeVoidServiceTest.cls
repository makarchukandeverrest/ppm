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
        Test.setMock(HttpCalloutMock.class, new DocuSignVoidMock(200, '{"status":"voided"}'));
        DocuSignEnvelopeVoidService.testSettings = new DocuSign_API_Settings__mdt(
            Named_Credential__c = 'DocuSign',
            Account_Id__c = '12345'
        );

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
