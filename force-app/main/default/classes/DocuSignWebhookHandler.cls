@RestResource(urlMapping='/docusignEvents') //TODO IT IS NOT ACTUALLY USED. WORKAROUND ON ContentVersion TRIGGER
global without sharing class DocuSignWebhookHandler {

    global class DocuSignEnvelopeCompletedEvent {
        public String event;
        public String apiVersion;
        public String uri;
        public Integer retryCount;
        public Long configurationId;
        public String generatedDateTime;
        public EventData data;
    }

    global class EventData {
        public String accountId;
        public String userId;
        public String envelopeId;
        public EnvelopeSummary envelopeSummary;
    }

    global class EnvelopeSummary {
        public String status;
        public String emailSubject;
        public String completedDateTime;
    }

    @HttpPost
    global static void handlePost() {
            String body = RestContext.request.requestBody.toString();
            System.debug('Received DocuSign Webhook payload: ' + body);

            DocuSignEnvelopeCompletedEvent eventObj =
                (DocuSignEnvelopeCompletedEvent) JSON.deserialize(body, DocuSignEnvelopeCompletedEvent.class);
            System.debug('Received DocuSign Webhook eventObj: ' + eventObj.data.envelopeId);

            ContentVersion cv = [
                SELECT Id, Title, ContentDocumentId
                FROM ContentVersion
                WHERE DocuSign_Envelope_Id__c = :eventObj.data.envelopeId
                LIMIT 1
            ];

            
            ContentDocumentLink link = [
                SELECT LinkedEntityId
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :cv.ContentDocumentId
                LIMIT 1
            ];

            Opportunity opp = [
                SELECT Id, Name, Owner.Name
                FROM Opportunity
                WHERE Id = :link.LinkedEntityId
                LIMIT 1
            ];

            
            User sysAdmin = [
                SELECT Id, Name, Email
                FROM User
                WHERE Profile.Name = 'System Administrator'
                AND IsActive = TRUE
                LIMIT 1
            ];

            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(
                new String[] { 
                    //'gabriela@premierswim.com',
                    'artemus1295@gmail.com' 
                }
            ); // TODO Change to System Admin email
            mail.setSubject('DocuSign Envelope for Opportunity "' + opp.Name + '" was completed');
            
            String status = eventObj.data.envelopeSummary.status;
            String envelopeId = eventObj.data.envelopeId;
            String docTitle = cv.Title;

            mail.setPlainTextBody(
                'Hello,\n\n' +
                'The DocuSign envelope for Opportunity "' + opp.Name + '" has changed status to "' + status + '".\n\n' +
                'Document: ' + docTitle + '\n' +
                'Envelope ID: ' + envelopeId + '\n' +
                'Completed Date: ' + eventObj.data.envelopeSummary.completedDateTime + '\n\n' +
                'Best regards,\nSalesforce System'
            );

            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

            System.debug('Notification email sent to: ' + sysAdmin.Email);

    }

}