@IsTest
private class DocuSignNotificationApiServiceTest {
  private static String lastPutBody;
  private static Integer putCount;
  private static Integer getCount;

  @IsTest
  static void updateExpiration_mergesExistingNotificationSettings() {
    lastPutBody = null;
    putCount = 0;
    getCount = 0;
    Test.setMock(HttpCalloutMock.class, new NotificationMock());

    Test.startTest();
    DocuSignNotificationApiService.updateExpiration(
      'DocuSign',
      'account-1',
      'envelope-1',
      150,
      10,
      true,
      2,
      3
    );
    Test.stopTest();

    System.assertEquals(1, putCount);
    System.assertEquals(0, getCount);
    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      lastPutBody
    );
    System.assertEquals('false', payload.get('useAccountDefaults'));
    Map<String, Object> expirations = (Map<String, Object>) payload.get(
      'expirations'
    );
    System.assertEquals('true', expirations.get('expireEnabled'));
    System.assertEquals('150', expirations.get('expireAfter'));
    System.assertEquals('10', expirations.get('expireWarn'));
    Map<String, Object> reminders = (Map<String, Object>) payload.get(
      'reminders'
    );
    System.assertEquals('true', reminders.get('reminderEnabled'));
    System.assertEquals('2', reminders.get('reminderDelay'));
    System.assertEquals('3', reminders.get('reminderFrequency'));
  }

  @IsTest
  static void updateExpiration_writesRemindersFromSalesforceValues() {
    lastPutBody = null;
    putCount = 0;
    getCount = 0;
    Test.setMock(HttpCalloutMock.class, new NotificationMock());

    Test.startTest();
    DocuSignNotificationApiService.updateExpiration(
      'DocuSign',
      'account-1',
      'envelope-1',
      90,
      5,
      false,
      0,
      0
    );
    Test.stopTest();

    System.assertEquals(0, getCount);
    System.assertEquals(1, putCount);
    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      lastPutBody
    );
    Map<String, Object> reminders = (Map<String, Object>) payload.get(
      'reminders'
    );
    System.assertEquals('false', reminders.get('reminderEnabled'));
    System.assertEquals('0', reminders.get('reminderDelay'));
  }

  @IsTest
  static void validatesArgumentsAndBuildsEncodedEndpoint() {
    String endpoint = DocuSignNotificationApiService.buildNotificationEndpoint(
      'DocuSign',
      'account id',
      'envelope/id'
    );
    System.assertEquals(
      'callout:DocuSign/restapi/v2.1/accounts/account+id/envelopes/envelope%2Fid/notification',
      endpoint
    );

    Boolean invalidExpirationThrew = false;
    try {
      DocuSignNotificationApiService.updateExpiration(
        'DocuSign',
        'account',
        'envelope',
        0,
        0,
        false,
        0,
        0
      );
    } catch (DocuSignNotificationApiService.DocuSignNotificationException ex) {
      invalidExpirationThrew = true;
    }
    System.assertEquals(true, invalidExpirationThrew);

    Boolean invalidWarningThrew = false;
    try {
      DocuSignNotificationApiService.updateExpiration(
        'DocuSign',
        'account',
        'envelope',
        90,
        90,
        false,
        0,
        0
      );
    } catch (DocuSignNotificationApiService.DocuSignNotificationException ex) {
      invalidWarningThrew = true;
    }
    System.assertEquals(true, invalidWarningThrew);
  }

  @IsTest
  static void resolveConnection_usesTestOverrides() {
    DocuSignNotificationApiService.testNamedCredential = 'TestCredential';
    DocuSignNotificationApiService.testAccountId = 'TestAccount';

    DocuSignNotificationApiService.Connection connection = DocuSignNotificationApiService.resolveConnection();

    System.assertEquals('TestCredential', connection.namedCredential);
    System.assertEquals('TestAccount', connection.accountId);
  }

  @IsTest
  static void resolveConnection_usesOrgCredentialWhenOverridesAreBlank() {
    DocuSignNotificationApiService.testNamedCredential = null;
    DocuSignNotificationApiService.testAccountId = null;

    DocuSignNotificationApiService.Connection connection = DocuSignNotificationApiService.resolveConnection();

    System.assertEquals('ArtemDocuDevCredential', connection.namedCredential);
    System.assertEquals('TEST-DOCUSIGN-ACCOUNT', connection.accountId);
  }

  @IsTest
  static void updateExpiration_surfacesPutFailure() {
    Test.setMock(HttpCalloutMock.class, new FailureMock('PUT'));
    Boolean putThrew = false;
    try {
      DocuSignNotificationApiService.updateExpiration(
        'DocuSign',
        'account',
        'envelope',
        90,
        5,
        true,
        1,
        1
      );
    } catch (DocuSignNotificationApiService.DocuSignNotificationException ex) {
      putThrew = true;
      System.assert(ex.getMessage().contains('PUT notification status=500'));
    }
    System.assertEquals(true, putThrew);
  }

  @IsTest
  static void rejectsBlankNotificationEndpoint() {
    Boolean endpointThrew = false;
    try {
      DocuSignNotificationApiService.buildNotificationEndpoint(
        '',
        'account',
        'envelope'
      );
    } catch (DocuSignNotificationApiService.DocuSignNotificationException ex) {
      endpointThrew = true;
    }
    System.assertEquals(true, endpointThrew);
  }

  private class NotificationMock implements HttpCalloutMock {

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setHeader('Content-Type', 'application/json');
      if (request.getMethod() == 'GET') {
        getCount = getCount == null ? 1 : getCount + 1;
        response.setStatusCode(200);
        response.setBody('{}');
        return response;
      }
      putCount = putCount == null ? 1 : putCount + 1;
      lastPutBody = request.getBody();
      response.setStatusCode(200);
      response.setBody('{}');
      return response;
    }
  }

  private class FailureMock implements HttpCalloutMock {
    private String failingMethod;

    FailureMock(String failingMethod) {
      this.failingMethod = failingMethod;
    }

    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setHeader('Content-Type', 'application/json');
      if (request.getMethod() == failingMethod) {
        response.setStatusCode(500);
        response.setBody('{"error":"forced"}');
      } else {
        response.setStatusCode(200);
        response.setBody(
          '{"reminders":{"reminderEnabled":"true"},"expirations":{"expireEnabled":"true","expireAfter":"120","expireWarn":"5"}}'
        );
      }
      return response;
    }
  }
}
