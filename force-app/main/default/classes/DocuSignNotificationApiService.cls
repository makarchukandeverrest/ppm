public without sharing class DocuSignNotificationApiService {
  // Sandbox DocuSign NC fails JWT with consent_required. ArtemDocuDevCredential
  // is the working demo.docusign.net credential in this sandbox.
  @TestVisible
  private static final String SANDBOX_NAMED_CREDENTIAL = 'ArtemDocuDevCredential';
  @TestVisible
  private static final String PRODUCTION_NAMED_CREDENTIAL = 'ArtemDocuDevCredential';

  @TestVisible
  static String testAccountId;
  @TestVisible
  static String testNamedCredential;

  public class DocuSignNotificationException extends Exception {
  }

  public class Connection {
    public String namedCredential;
    public String accountId;

    public Connection(String namedCredential, String accountId) {
      this.namedCredential = namedCredential;
      this.accountId = accountId;
    }
  }

  public static Connection resolveConnection() {
    String namedCredential = String.isNotBlank(testNamedCredential)
      ? testNamedCredential
      : (isSandboxOrg()
          ? SANDBOX_NAMED_CREDENTIAL
          : PRODUCTION_NAMED_CREDENTIAL);
    String accountId = resolveAccountId(namedCredential);
    return new Connection(namedCredential, accountId);
  }

  public static void updateExpiration(
    String namedCredential,
    String accountId,
    String envelopeId,
    Integer expireAfterDays,
    Integer expireWarnDays,
    Boolean reminderEnabled,
    Integer reminderDelayDays,
    Integer reminderFrequencyDays
  ) {
    if (
      expireAfterDays == null ||
      expireAfterDays < 1 ||
      expireAfterDays > 999
    ) {
      throw new DocuSignNotificationException(
        'Expiration must be between 1 and 999 days after the envelope was sent.'
      );
    }
    if (
      expireWarnDays == null ||
      expireWarnDays < 0 ||
      expireWarnDays >= expireAfterDays ||
      expireWarnDays > 999
    ) {
      throw new DocuSignNotificationException(
        'Expiration warning must be between 0 and one day before expiration.'
      );
    }

    String endpoint = buildNotificationEndpoint(
      namedCredential,
      accountId,
      envelopeId
    );
    Map<String, Object> reminders = new Map<String, Object>();
    reminders.put('reminderEnabled', reminderEnabled == true ? 'true' : 'false');
    reminders.put(
      'reminderDelay',
      String.valueOf(reminderDelayDays == null ? 0 : reminderDelayDays)
    );
    reminders.put(
      'reminderFrequency',
      String.valueOf(
        reminderFrequencyDays == null ? 0 : reminderFrequencyDays
      )
    );

    Map<String, Object> expirations = new Map<String, Object>();
    expirations.put('expireEnabled', 'true');
    expirations.put('expireAfter', String.valueOf(expireAfterDays));
    expirations.put('expireWarn', String.valueOf(expireWarnDays));

    Map<String, Object> payload = new Map<String, Object>();
    payload.put('useAccountDefaults', 'false');
    payload.put('reminders', reminders);
    payload.put('expirations', expirations);
    putNotificationSettings(endpoint, payload);
  }

  @TestVisible
  static void putNotificationSettings(
    String endpoint,
    Map<String, Object> payload
  ) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(endpoint);
    request.setMethod('PUT');
    request.setHeader('Accept', 'application/json');
    request.setHeader('Content-Type', 'application/json');
    request.setBody(JSON.serialize(payload));
    request.setTimeout(120000);

    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      throw new DocuSignNotificationException(
        'PUT notification status=' +
          response.getStatusCode() +
          ' body=' +
          response.getBody()
      );
    }
  }

  public static String buildNotificationEndpoint(
    String namedCredential,
    String accountId,
    String envelopeId
  ) {
    if (
      String.isBlank(namedCredential) ||
      String.isBlank(accountId) ||
      String.isBlank(envelopeId)
    ) {
      throw new DocuSignNotificationException(
        'Named Credential, DocuSign account ID, and envelope ID are required.'
      );
    }
    return 'callout:' +
      namedCredential +
      '/restapi/v2.1/accounts/' +
      EncodingUtil.urlEncode(accountId, 'UTF-8') +
      '/envelopes/' +
      EncodingUtil.urlEncode(envelopeId, 'UTF-8') +
      '/notification';
  }

  @TestVisible
  static String resolveAccountId(String namedCredential) {
    if (String.isNotBlank(testAccountId)) {
      return testAccountId;
    }
    if (Test.isRunningTest()) {
      return 'TEST-DOCUSIGN-ACCOUNT';
    }

    HttpRequest request = new HttpRequest();
    request.setEndpoint(
      'callout:' + namedCredential + '/restapi/v2.1/login_information'
    );
    request.setMethod('GET');
    request.setHeader('Accept', 'application/json');
    request.setTimeout(120000);

    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() != 200 || String.isBlank(response.getBody())) {
      throw new DocuSignNotificationException(
        'Could not resolve DocuSign account ID: status=' +
          response.getStatusCode() +
          ' body=' +
          response.getBody()
      );
    }

    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      response.getBody()
    );
    List<Object> accounts = (List<Object>) payload.get('loginAccounts');
    if (accounts == null || accounts.isEmpty()) {
      throw new DocuSignNotificationException(
        'Could not resolve DocuSign account ID: no login accounts returned.'
      );
    }
    for (Object row : accounts) {
      Map<String, Object> account = (Map<String, Object>) row;
      if ('true'.equalsIgnoreCase(String.valueOf(account.get('isDefault')))) {
        return String.valueOf(account.get('accountId'));
      }
    }
    return String.valueOf(((Map<String, Object>) accounts[0]).get('accountId'));
  }

  private static Boolean isSandboxOrg() {
    return [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
  }
}
