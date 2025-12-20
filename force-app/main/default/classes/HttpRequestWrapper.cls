public class HttpRequestWrapper {
    public String endpoint;
    public String method;
    public String body;
    public Map<String, String> headers;

    public Id contentVersionId;
    public Id contractBidId;

    public HttpRequest toRequest() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        if (body != null) req.setBody(body);
        if (headers != null) {
            for (String key : headers.keySet()) {
                req.setHeader(key, headers.get(key));
            }
        }
        return req;
    }
}