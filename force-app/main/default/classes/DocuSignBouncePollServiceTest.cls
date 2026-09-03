@IsTest
private class DocuSignBouncePollServiceTest {
    private class RecipientsMock implements HttpCalloutMock {
        Integer statusCode;
        String body;

        RecipientsMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(body);
            return response;
        }
    }

    @TestSetup
    static void setupTestData() {
        dfsle__EnvelopeStatus__c envelopeStatus = new dfsle__EnvelopeStatus__c(
            dfsle__DocuSignId__c = 'env-bounce-1',
            dfsle__Status__c = 'Sent',
            dfsle__EmailSubject__c = 'Premier Pool Management Proposal',
            dfsle__Sent__c = System.now()
        );
        insert envelopeStatus;

        insert new dfsle__RecipientStatus__c(
            Name = 'Bounce Target',
            dfsle__EnvelopeStatus__c = envelopeStatus.Id,
            dfsle__Email__c = 'notreal@gmail.com',
            dfsle__Status__c = 'Sent',
            dfsle__Sent__c = System.now(),
            Email_Bounced__c = false
        );
    }

    @IsTest
    static void testProcessRecipients_stampsBounceFromApiJson() {
        dfsle__RecipientStatus__c recipient = queryTargetRecipient();

        DocuSignBouncePollService.skipCalloutInTest = true;
        DocuSignBouncePollService.testRecipientsJsonByEnvelopeId.put(
            'env-bounce-1',
            '{"signers":[{"email":"notreal@gmail.com","status":"autoresponded","autoRespondedReason":"Mailbox does not exist"}]}'
        );

        Test.startTest();
        DocuSignBouncePollService.processRecipients(new List<dfsle__RecipientStatus__c>{ recipient });
        Test.stopTest();

        dfsle__RecipientStatus__c updated = queryTargetRecipient();
        System.assertEquals('AutoResponded', updated.dfsle__Status__c);
        System.assertEquals(true, updated.Email_Bounced__c);
        System.assertEquals('Mailbox does not exist', updated.Bounce_Reason__c);
        System.assertNotEquals(null, updated.Bounced_Detected_At__c);
    }

    @IsTest
    static void testProcessRecipients_doesNotUpdateWhenStillSent() {
        dfsle__RecipientStatus__c recipient = queryTargetRecipient();

        DocuSignBouncePollService.skipCalloutInTest = true;
        DocuSignBouncePollService.testRecipientsJsonByEnvelopeId.put(
            'env-bounce-1',
            '{"signers":[{"email":"notreal@gmail.com","status":"sent"}]}'
        );

        Test.startTest();
        DocuSignBouncePollService.processRecipients(new List<dfsle__RecipientStatus__c>{ recipient });
        Test.stopTest();

        dfsle__RecipientStatus__c updated = queryTargetRecipient();
        System.assertEquals('Sent', updated.dfsle__Status__c);
        System.assertEquals(false, updated.Email_Bounced__c);
    }

    @IsTest
    static void testProcessRecipients_skipsAlreadyFlaggedBounce() {
        dfsle__RecipientStatus__c recipient = queryTargetRecipient();
        recipient.Email_Bounced__c = true;
        recipient.Bounce_Reason__c = 'Already flagged';
        update recipient;

        recipient = queryTargetRecipient();
        DocuSignBouncePollService.skipCalloutInTest = true;
        DocuSignBouncePollService.testRecipientsJsonByEnvelopeId.put(
            'env-bounce-1',
            '{"signers":[{"email":"notreal@gmail.com","status":"autoresponded","autoRespondedReason":"Should not overwrite"}]}'
        );

        Test.startTest();
        DocuSignBouncePollService.processRecipients(new List<dfsle__RecipientStatus__c>{ recipient });
        Test.stopTest();

        dfsle__RecipientStatus__c updated = queryTargetRecipient();
        System.assertEquals('Already flagged', updated.Bounce_Reason__c);
        System.assertEquals('Sent', updated.dfsle__Status__c);
    }

    @IsTest
    static void testProcessRecipients_stampsExistingAutoRespondedWithoutCallout() {
        dfsle__RecipientStatus__c recipient = queryTargetRecipient();
        recipient.dfsle__Status__c = 'AutoResponded';
        update recipient;

        recipient = queryTargetRecipient();

        Test.startTest();
        DocuSignBouncePollService.processRecipients(new List<dfsle__RecipientStatus__c>{ recipient });
        Test.stopTest();

        dfsle__RecipientStatus__c updated = queryTargetRecipient();
        System.assertEquals(true, updated.Email_Bounced__c);
        System.assertEquals('AutoResponded', updated.dfsle__Status__c);
        System.assertEquals(0, DocuSignBouncePollService.testRecipientsJsonByEnvelopeId.size());
    }

    @IsTest
    static void testProcessRecipients_httpCalloutMarksBounce() {
        dfsle__RecipientStatus__c recipient = queryTargetRecipient();
        DocuSignBouncePollService.testDocuSignAccountId = 'acct-1';
        Test.setMock(
            HttpCalloutMock.class,
            new RecipientsMock(
                200,
                '{"carbonCopies":[{"email":"cc@example.com","status":"sent"}],"signers":[{"email":"NotReal@gmail.com","status":"AutoResponded","autoRespondedReason":"Invalid mailbox"}]}'
            )
        );

        Test.startTest();
        DocuSignBouncePollService.processRecipients(new List<dfsle__RecipientStatus__c>{ recipient });
        Test.stopTest();

        dfsle__RecipientStatus__c updated = queryTargetRecipient();
        System.assertEquals(true, updated.Email_Bounced__c);
        System.assertEquals('Invalid mailbox', updated.Bounce_Reason__c);
    }

    @IsTest
    static void testProcessRecipients_httpErrorLeavesRecordUnchanged() {
        dfsle__RecipientStatus__c recipient = queryTargetRecipient();
        DocuSignBouncePollService.testDocuSignAccountId = 'acct-1';
        Test.setMock(HttpCalloutMock.class, new RecipientsMock(500, 'boom'));

        Test.startTest();
        DocuSignBouncePollService.processRecipients(new List<dfsle__RecipientStatus__c>{ recipient });
        Test.stopTest();

        dfsle__RecipientStatus__c updated = queryTargetRecipient();
        System.assertEquals('Sent', updated.dfsle__Status__c);
        System.assertEquals(false, updated.Email_Bounced__c);
    }

    @IsTest
    static void testBatchMarksBounce() {
        DocuSignBouncePollService.skipCalloutInTest = true;
        DocuSignBouncePollService.testRecipientsJsonByEnvelopeId.put(
            'env-bounce-1',
            '{"signers":[{"email":"notreal@gmail.com","status":"autoresponded","autoRespondedReason":"Hard bounce"}]}'
        );

        Test.startTest();
        Database.executeBatch(new DocuSignBouncePollBatch(), 20);
        Test.stopTest();

        dfsle__RecipientStatus__c updated = queryTargetRecipient();
        System.assertEquals(true, updated.Email_Bounced__c);
        System.assertEquals('Hard bounce', updated.Bounce_Reason__c);
    }

    @IsTest
    static void testSchedulerExecuteStartsBatch() {
        DocuSignBouncePollService.skipCalloutInTest = true;
        DocuSignBouncePollService.testRecipientsJsonByEnvelopeId.put(
            'env-bounce-1',
            '{"signers":[{"email":"notreal@gmail.com","status":"autoresponded"}]}'
        );

        Test.startTest();
        new DocuSignBouncePollScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(true, queryTargetRecipient().Email_Bounced__c);
    }

    @IsTest
    static void testScheduleHourlyCreatesCron() {
        Id jobId = DocuSignBouncePollScheduler.scheduleHourly();

        System.assertNotEquals(null, jobId);
        Integer jobs = [
            SELECT COUNT()
            FROM CronTrigger
            WHERE CronJobDetail.Name = :DocuSignBouncePollScheduler.JOB_NAME
        ];
        System.assertEquals(1, jobs);
        DocuSignBouncePollScheduler.abortExisting();
    }

    @IsTest
    static void testStampExistingAutoResponded() {
        dfsle__RecipientStatus__c recipient = queryTargetRecipient();
        recipient.dfsle__Status__c = 'AutoResponded';
        recipient.Email_Bounced__c = false;
        update recipient;

        Test.startTest();
        DocuSignBouncePollService.stampExistingAutoResponded();
        Test.stopTest();

        System.assertEquals(true, queryTargetRecipient().Email_Bounced__c);
    }

    @IsTest
    static void testProcessRecipients_emptyAndBlankEmail() {
        Test.startTest();
        DocuSignBouncePollService.processRecipients(null);
        DocuSignBouncePollService.processRecipients(new List<dfsle__RecipientStatus__c>());
        Test.stopTest();

        dfsle__RecipientStatus__c recipient = queryTargetRecipient();
        recipient.dfsle__Email__c = null;
        DocuSignBouncePollService.skipCalloutInTest = true;
        DocuSignBouncePollService.processRecipients(new List<dfsle__RecipientStatus__c>{ recipient });

        System.assertEquals(false, queryTargetRecipient().Email_Bounced__c);
    }

    private static dfsle__RecipientStatus__c queryTargetRecipient() {
        return [
            SELECT
                Id,
                dfsle__Email__c,
                dfsle__Status__c,
                dfsle__Reason__c,
                Email_Bounced__c,
                Bounce_Reason__c,
                Bounced_Detected_At__c,
                dfsle__EnvelopeStatus__c,
                dfsle__EnvelopeStatus__r.dfsle__DocuSignId__c
            FROM dfsle__RecipientStatus__c
            WHERE dfsle__Email__c = 'notreal@gmail.com' OR Name = 'Bounce Target'
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
    }
}
