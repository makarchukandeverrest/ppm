public without sharing class AutomationTaskCreator {
  private static final String AUTOMATION_USER_NAME = 'Premier Pool Management';

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

    @InvocableVariable(
      label='Upsert Open Task'
      description='If true and an open Task already exists for WhatId + Task Key, update due date instead of inserting.'
    )
    public Boolean upsertOpenTask;

    @InvocableVariable(
      label='Task Key'
      description='Stable key stored in Description as [KEY:...]. Defaults to Subject.'
    )
    public String taskKey;
  }

  public class Result {
    @InvocableVariable(label='Task Id')
    public Id taskId;

    @InvocableVariable(label='Updated Existing')
    public Boolean updatedExisting;
  }

  @InvocableMethod(
    label='Create Automation Task'
    description='Creates or upserts Tasks assigned to Owner Id with Created By = Premier Pool Management when available.'
  )
  public static List<Result> createTasks(List<Request> requests) {
    Id createdById = getAutomationUserId();
    List<Result> results = new List<Result>();
    if (requests == null || requests.isEmpty()) {
      return results;
    }

    Set<Id> whatIds = new Set<Id>();
    for (Request request : requests) {
      if (request.whatId != null && request.upsertOpenTask == true) {
        whatIds.add(request.whatId);
      }
    }

    Map<String, Task> openByKey = loadOpenTasksByKey(whatIds);

    List<Task> toInsert = new List<Task>();
    List<Task> toUpdate = new List<Task>();
    List<Integer> insertIndexes = new List<Integer>();

    for (Integer i = 0; i < requests.size(); i++) {
      Request request = requests[i];
      Result result = new Result();
      result.updatedExisting = false;

      String key = resolveTaskKey(request);
      String mapKey = buildMapKey(request.whatId, key);

      if (
        request.upsertOpenTask == true &&
        request.whatId != null &&
        openByKey.containsKey(mapKey)
      ) {
        Task existing = openByKey.get(mapKey);
        if (request.activityDate != null) {
          existing.ActivityDate = request.activityDate;
        }
        if (request.ownerId != null) {
          existing.OwnerId = request.ownerId;
        }
        toUpdate.add(existing);
        result.taskId = existing.Id;
        result.updatedExisting = true;
      } else {
        Task created = new Task(
          OwnerId = request.ownerId,
          Subject = request.subject,
          WhatId = request.whatId,
          WhoId = request.whoId,
          Description = buildDescription(request, key),
          ActivityDate = request.activityDate,
          Status = String.isBlank(request.status)
            ? 'Not Started'
            : request.status,
          Priority = String.isBlank(request.priority)
            ? 'Normal'
            : request.priority
        );
        if (createdById != null) {
          created.CreatedById = createdById;
        }
        toInsert.add(created);
        insertIndexes.add(i);
      }
      results.add(result);
    }

    if (!toUpdate.isEmpty()) {
      update toUpdate;
    }
    if (!toInsert.isEmpty()) {
      insert toInsert;
      for (Integer j = 0; j < toInsert.size(); j++) {
        results[insertIndexes[j]].taskId = toInsert[j].Id;
      }
    }

    return results;
  }

  private static Map<String, Task> loadOpenTasksByKey(Set<Id> whatIds) {
    Map<String, Task> openByKey = new Map<String, Task>();
    if (whatIds == null || whatIds.isEmpty()) {
      return openByKey;
    }
    for (Task t : [
      SELECT
        Id,
        WhatId,
        Subject,
        Description,
        ActivityDate,
        OwnerId,
        Status,
        IsClosed
      FROM Task
      WHERE WhatId IN :whatIds AND IsClosed = FALSE
      ORDER BY CreatedDate DESC
    ]) {
      String key = extractTaskKey(t);
      String mapKey = buildMapKey(t.WhatId, key);
      if (!openByKey.containsKey(mapKey)) {
        openByKey.put(mapKey, t);
      }
    }
    return openByKey;
  }

  @TestVisible
  private static String resolveTaskKey(Request request) {
    if (request == null) {
      return null;
    }
    if (!String.isBlank(request.taskKey)) {
      return request.taskKey.trim();
    }
    return request.subject;
  }

  @TestVisible
  private static String buildDescription(Request request, String key) {
    String prefix = '[KEY:' + key + ']\n';
    if (String.isBlank(request.description)) {
      return prefix;
    }
    if (request.description.startsWith('[KEY:')) {
      return request.description;
    }
    return prefix + request.description;
  }

  @TestVisible
  private static String extractTaskKey(Task t) {
    if (t == null) {
      return null;
    }
    if (!String.isBlank(t.Description) && t.Description.startsWith('[KEY:')) {
      Integer endIdx = t.Description.indexOf(']');
      if (endIdx > 5) {
        return t.Description.substring(5, endIdx);
      }
    }
    return t.Subject;
  }

  private static String buildMapKey(Id whatId, String taskKey) {
    return String.valueOf(whatId) + '|' + (taskKey == null ? '' : taskKey);
  }

  private static Id getAutomationUserId() {
    if (automationUserIdOverride != null) {
      return automationUserIdOverride;
    }
    List<User> users = [
      SELECT Id
      FROM User
      WHERE Name = :AUTOMATION_USER_NAME AND IsActive = TRUE
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0].Id;
  }
}
