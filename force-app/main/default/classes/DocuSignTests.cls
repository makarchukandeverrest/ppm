public class DocuSignTests {
    public static void testing(){
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:ArtemDocuDevCredential/restapi/v2.1/accounts/41191243/envelopes');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody('{}');
        Http http = new Http();
        HTTPResponse res = http.send(req);
        System.debug('Response Status: ' + res.getStatus());
        System.debug('Response Body: ' + res.getBody());
	}
}