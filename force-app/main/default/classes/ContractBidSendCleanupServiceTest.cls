@IsTest
private class ContractBidSendCleanupServiceTest {
  @IsTest
  static void completesMatchingOpenTasksAndLeavesOthers() {
    Contract_Bid__c bid = insertBid('Cleanup Bid');

    Task callTask = new Task(
      Subject = 'Call Property Owner about Contract for Acme',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    Task visitTask = new Task(
      Subject = 'On-site visit to Acme – Contract not signed',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    Task openedTask = new Task(
      Subject = 'Call about opened unsigned contract: Cleanup Bid',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    Task versionTask = new Task(
      Subject = 'Request New Version',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    Task manualTask = new Task(
      Subject = 'Manual follow up',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    insert new List<Task>{
      callTask,
      visitTask,
      openedTask,
      versionTask,
      manualTask
    };

    Test.startTest();
    ContractBidSendCleanupService.completeOpenFollowUpTasks(
      new Set<Id>{ bid.Id }
    );
    Test.stopTest();

    Map<Id, Task> tasks = new Map<Id, Task>(
      [
        SELECT Id, Status
        FROM Task
        WHERE
          Id IN :new List<Id>{
            callTask.Id,
            visitTask.Id,
            openedTask.Id,
            versionTask.Id,
            manualTask.Id
          }
      ]
    );

    System.assertEquals('Completed', tasks.get(callTask.Id).Status);
    System.assertEquals('Completed', tasks.get(visitTask.Id).Status);
    System.assertEquals('Completed', tasks.get(openedTask.Id).Status);
    System.assertEquals('Completed', tasks.get(versionTask.Id).Status);
    System.assertEquals('Not Started', tasks.get(manualTask.Id).Status);
  }

  @IsTest
  static void subjectMatcherCoversExpectedPatternsOnly() {
    System.assertEquals(
      true,
      ContractBidSendCleanupService.isFollowUpTask('Request New Version')
    );
    System.assertEquals(
      true,
      ContractBidSendCleanupService.isFollowUpTask(
        'Call about opened unsigned contract: Bid A'
      )
    );
    System.assertEquals(
      false,
      ContractBidSendCleanupService.isFollowUpTask('Verify contact info')
    );
  }

  private static Contract_Bid__c insertBid(String name) {
    Account customer = new Account(Name = name + ' Customer');
    insert customer;
    Contract_Bid__c bid = new Contract_Bid__c(
      Name = name,
      Customer__c = customer.Id,
      Stage__c = 'Contact Made'
    );
    insert bid;
    return bid;
  }
}
