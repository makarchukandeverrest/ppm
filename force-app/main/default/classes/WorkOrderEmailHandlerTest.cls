@IsTest
private class WorkOrderEmailHandlerTest {

    /**
     * Main happy-path scenario:
     *  - WorkOrder with Quick_Books_WO_No__c = 137 exists
     *  - incoming email Subject and Body are like in the example
     *  - status is mapped to 'Proposal Approved / WO Created'
     *  - FeedItem with comment is created
     *  - Files and ContentDocumentLink are created for binary and text attachments
     */
    @IsTest
    static void testHandleInboundEmail_HappyPath() {
        // 1. Test data: WorkOrder
        WorkOrder wo = new WorkOrder(
            Subject               = 'Test WO',
            Status                = 'New',
            Quick_Books_WO_No__c  = '137'
        );
        insert wo;

        // 2. Simulate incoming email
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();

        email.subject = 'Re: New Work Order assigned: 137';
        email.fromAddress = 'tech@example.com';
        env.fromAddress = 'tech@example.com';

        email.plainTextBody =
            'Status: proposal approved\n' +
            'Comment: Pump was replaced and system tested. No leaks found\n' +
            '\n' +
            'Best regards,\n' +
            'John Doe\n' +
            'Service Technician';

        // Add one binary and one text attachment to cover handleAttachments
        Messaging.InboundEmail.BinaryAttachment binAtt = 
            new Messaging.InboundEmail.BinaryAttachment();
        binAtt.body = Blob.valueOf('binary body');
        binAtt.fileName = 'test-binary.pdf';
        binAtt.mimeTypeSubType = 'application/pdf';
        email.binaryAttachments = new List<Messaging.InboundEmail.BinaryAttachment>{ binAtt };

        Messaging.InboundEmail.TextAttachment textAtt = 
            new Messaging.InboundEmail.TextAttachment();
        textAtt.body = 'sample text attachment';
        textAtt.fileName = 'test-text.txt';
        textAtt.mimeTypeSubType = 'text/plain';
        email.textAttachments = new List<Messaging.InboundEmail.TextAttachment>{ textAtt };

        // 3. Invoke handler
        WorkOrderEmailHandler handler = new WorkOrderEmailHandler();

        Test.startTest();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, env);
        Test.stopTest();

        // 4. Assertions on result
        System.assertEquals(true, result.success, 'Email should be processed successfully');
        System.assertEquals(
            'Email processed, WorkOrderNumber: 137',
            result.message,
            'Message should contain WO number from subject'
        );

        // 5. Reload WorkOrder and verify status
        wo = [
            SELECT Id, Status
            FROM WorkOrder
            WHERE Id = :wo.Id
        ];

        System.assertEquals(
            'Proposal Approved / WO Created',
            wo.Status,
            'Status must be mapped from "proposal approved"'
        );

        // 6. Assert FeedItem created from comment
        FeedItem fi = [
            SELECT Id, ParentId, Body
            FROM FeedItem
            WHERE ParentId = :wo.Id
            LIMIT 1
        ];

        System.assert(fi != null, 'FeedItem must be created');
        System.assert(
            fi.Body.contains('Comment from tech@example.com'),
            'FeedItem body must contain fromAddress'
        );
        System.assert(
            fi.Body.contains('Pump was replaced and system tested. No leaks found'),
            'FeedItem body must contain comment text'
        );

        // 7. Assert Files and links
        // ContentVersion
        List<ContentVersion> cvs = [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Title IN ('test-binary.pdf', 'test-text.txt')
        ];
        System.assertEquals(2, cvs.size(), 'Two ContentVersion records should be created');

        // ContentDocumentLink
        List<ContentDocumentLink> links = [
            SELECT Id, LinkedEntityId, ContentDocumentId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :wo.Id
        ];
        System.assertEquals(2, links.size(), 'Two ContentDocumentLink records should be created');
        for (ContentDocumentLink cdl : links) {
            System.assertEquals('V', cdl.ShareType, 'ShareType should be Viewer');
            System.assertEquals('AllUsers', cdl.Visibility, 'Visibility should be AllUsers');
        }
    }

    /**
     * Negative scenario: Work Order number is not found in subject.
     * Verifies that success = false and WorkOrder is not modified.
     */
    @IsTest
    static void testHandleInboundEmail_NoWoNumber() {
        WorkOrder wo = new WorkOrder(
            Subject               = 'Test WO 2',
            Status                = 'New',
            Quick_Books_WO_No__c  = '999'
        );
        insert wo;

        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();

        // Subject without any WO number
        email.subject = 'New Work Order assigned';
        email.fromAddress = 'tech2@example.com';
        env.fromAddress = 'tech2@example.com';
        email.plainTextBody = 'Status: completed\nComment: done';

        WorkOrderEmailHandler handler = new WorkOrderEmailHandler();

        Test.startTest();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, env);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail when WO number not found in subject');
        System.assertEquals(
            'WorkOrderNumber not found in subject',
            result.message,
            'Message should describe the reason'
        );

        // WorkOrder must remain unchanged
        wo = [
            SELECT Id, Status
            FROM WorkOrder
            WHERE Id = :wo.Id
        ];
        System.assertEquals('New', wo.Status, 'Status must not be changed when WO number is not found');
    }
}