public class SharePointFileDataMock implements HttpCalloutMock {
    
    // Success scenario with file content
    public static final String TEST_FILE_GUID = '{da2c3ea5-3954-44ee-a81e-9f2c31dfbfb8}';
    public static final Blob TEST_FILE_CONTENT = Blob.valueOf('Test file content');
    
    // Error scenario
    public static final String ERROR_FILE_GUID = '99999-99999-99999';
    public static final Integer ERROR_STATUS_CODE = 404;
    
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/octet-stream');
            res.setBodyAsBlob(TEST_FILE_CONTENT);
            res.setStatusCode(200);
        
        return res;
    }
}