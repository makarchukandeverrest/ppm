public without sharing class AutomationTaskCreator {
  private static final String AUTOMATION_USER_NAME = 'Premier Pool Management';
  private static final String SYSTEM_ADMIN_PROFILE = 'System Administrator';

  public class AutomationTaskCreatorException extends Exception {
  }

  @TestVisible
  private static Id automationUserIdOverride;

  public class Request {
    @InvocableVariable(required=true label='Owner Id')
    public Id ownerId;

    @InvocableVariable(required=true label='Subject')
    public String subject;

    @InvocableVariable(label='Related To Id')
    public Id whatId;

    @InvocableVariable(label='Name Id')
    public Id whoId;

    @InvocableVariable(label='Description')
    public String description;

    @InvocableVariable(label='Due Date')
    public Date activityDate;

    @InvocableVariable(label='Status')
    public String status;

    @InvocableVariable(label='Priority')
    public String priority;
  }

  public class Result {
    @InvocableVariable(label='Task Id')
    public Id taskId;
  }

  @InvocableMethod(
    label='Create Automation Task'
    description='Budget Season only. Creates Tasks with Created By = Premier Pool Management. Must run as System Administrator (Set Audit Fields) — schedule ContractBidBudgetSeasonScheduler as that user.'
  )
  public static List<Result> createTasks(List<Request> requests) {
    assertSystemAdminContext();
    Id createdById = getAutomationUserId();
    List<Task> tasks = new List<Task>();

    for (Request request : requests) {
      tasks.add(
        new Task(
          OwnerId = request.ownerId,
          Subject = request.subject,
          WhatId = request.whatId,
          WhoId = request.whoId,
          Description = request.description,
          ActivityDate = request.activityDate,
          Status = String.isBlank(request.status)
            ? 'Not Started'
            : request.status,
          Priority = String.isBlank(request.priority)
            ? 'Normal'
            : request.priority,
          CreatedById = createdById
        )
      );
    }

    insert tasks;

    List<Result> results = new List<Result>();
    for (Task taskRecord : tasks) {
      Result result = new Result();
      result.taskId = taskRecord.Id;
      results.add(result);
    }
    return results;
  }

  private static void assertSystemAdminContext() {
    // CreatedById on insert requires Set Audit Fields; we only allow System Admin.
    String profileName = [
      SELECT Name
      FROM Profile
      WHERE Id = :UserInfo.getProfileId()
      LIMIT 1
    ]
    .Name;
    if (profileName != SYSTEM_ADMIN_PROFILE) {
      throw new AutomationTaskCreatorException(
        'AutomationTaskCreator must run as System Administrator (current profile: ' +
          profileName +
          '). Schedule the job / run the automation as that user.'
      );
    }
  }

  private static Id getAutomationUserId() {
    if (automationUserIdOverride != null) {
      return automationUserIdOverride;
    }
    List<User> automationUsers = [
      SELECT Id
      FROM User
      WHERE Name = :AUTOMATION_USER_NAME AND IsActive = TRUE
      LIMIT 1
    ];
    if (automationUsers.isEmpty()) {
      throw new AutomationTaskCreatorException(
        'Active user "' +
          AUTOMATION_USER_NAME +
          '" is required for AutomationTaskCreator CreatedById.'
      );
    }
    return automationUsers[0].Id;
  }
}
