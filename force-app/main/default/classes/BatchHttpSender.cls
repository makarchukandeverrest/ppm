public with sharing class BatchHttpSender implements Database.Batchable<HttpRequestWrapper>,Database.AllowsCallouts {
    
    public List<HttpRequestWrapper> requestsToSend;

    public BatchHttpSender(List<HttpRequestWrapper> requests) {
        this.requestsToSend = requests;
    }

    public Iterable<HttpRequestWrapper> start(Database.BatchableContext bc) {
        return requestsToSend;
    }

    public void execute(Database.BatchableContext bc, List<HttpRequestWrapper> scope) {
        Http http = new Http();
        Integer calloutsMade = 0;
        Integer maxCallouts = Limits.getLimitCallouts() - Limits.getCallouts();

        List<String> contentTitles = new List<String>();
        Map<String, String> titleToEnvelopeId = new Map<String, String>();

        for (HttpRequestWrapper wrap : scope) {
            if (calloutsMade >= maxCallouts) {
                System.debug('Callout limit reached. Skipping remaining requests.');
                break;
            }

            try {
                HttpRequest req = wrap.toRequest();
                HttpResponse res = http.send(req);
                
                System.debug('Response Code: ' + res.getStatusCode());
                System.debug('Response Body: ' + res.getBody());
                calloutsMade++;

                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String envelopeId = (String) parsed.get('envelopeId');

                String requestBody = req.getBody();
                Map<String, Object> reqMap = (Map<String, Object>) JSON.deserializeUntyped(requestBody);

                List<Object> documents = (List<Object>) reqMap.get('documents');
                String docName = '';
                if (documents != null && documents.size() > 0) {
                    Map<String, Object> doc = (Map<String, Object>) documents[0];
                    docName = (String) doc.get('name');
                }

                contentTitles.add(docName);
                titleToEnvelopeId.put(docName, envelopeId);

            } catch (Exception ex) {
                System.debug('Callout failed: ' + ex.getMessage());
            }
        }

        List<ContentVersion> versions = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE Title IN :contentTitles
        ];

        Map<String, ContentVersion> contentMap = new Map<String, ContentVersion>();
        for (ContentVersion v : versions) {
            contentMap.put(v.Title, v);
        }

        if(!contentTitles.isEmpty()){
            for (String title : titleToEnvelopeId.keySet()) {
                ContentVersion version = contentMap.get(title);
                version.DocuSign_Envelope_Id__c = titleToEnvelopeId.get(title).toUpperCase();
                version.To_Sent__c = false;
            }
        }

        update contentMap.values();
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('All requests complete');
    }
}