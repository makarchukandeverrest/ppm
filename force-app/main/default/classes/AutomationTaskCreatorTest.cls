@IsTest
private class AutomationTaskCreatorTest {
  @TestSetup
  static void setupTestData() {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];

    insert new List<User>{
      new User(
        FirstName = 'Premier Pool',
        LastName = 'Management',
        Email = 'ppm.automation@example.com',
        Username = 'ppm.automation.' +
          System.currentTimeMillis() +
          '@example.com',
        Alias = 'ppmusr',
        ProfileId = standardProfile.Id,
        TimeZoneSidKey = 'America/New_York',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
      ),
      new User(
        FirstName = 'Regional',
        LastName = 'Manager',
        Email = 'regional.manager@example.com',
        Username = 'regional.manager.' +
          System.currentTimeMillis() +
          '@example.com',
        Alias = 'regmgr',
        ProfileId = standardProfile.Id,
        TimeZoneSidKey = 'America/New_York',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
      )
    };

    insert new Account(Name = 'Automation Task Creator Account');
  }

  @IsTest
  static void createTasks_insertsTaskWithOwner() {
    User automationUser = [
      SELECT Id
      FROM User
      WHERE Email = 'ppm.automation@example.com'
      LIMIT 1
    ];
    User taskOwner = [
      SELECT Id
      FROM User
      WHERE Email = 'regional.manager@example.com'
      LIMIT 1
    ];
    Account accountRecord = [
      SELECT Id
      FROM Account
      WHERE Name = 'Automation Task Creator Account'
      LIMIT 1
    ];

    AutomationTaskCreator.automationUserIdOverride = automationUser.Id;

    AutomationTaskCreator.Request request = new AutomationTaskCreator.Request();
    request.ownerId = taskOwner.Id;
    request.subject = 'Call Property Owner about Proposal for Test';
    request.whatId = accountRecord.Id;
    request.description = 'Follow up';
    request.activityDate = Date.today().addDays(1);

    Test.startTest();
    List<AutomationTaskCreator.Result> results = AutomationTaskCreator.createTasks(
      new List<AutomationTaskCreator.Request>{ request }
    );
    Test.stopTest();

    Task created = [
      SELECT OwnerId, Subject, WhatId, Status, Priority
      FROM Task
      WHERE Id = :results[0].taskId
    ];
    System.assertEquals(taskOwner.Id, created.OwnerId);
    System.assertEquals(request.subject, created.Subject);
    System.assertEquals(accountRecord.Id, created.WhatId);
    System.assertEquals('Not Started', created.Status);
    System.assertEquals('Normal', created.Priority);
  }
}
