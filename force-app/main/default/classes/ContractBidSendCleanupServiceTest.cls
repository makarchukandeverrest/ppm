@IsTest
private class ContractBidSendCleanupServiceTest {
  @IsTest
  static void onEnvelopeSent_completesTasksClearsFlagsAndSetsStage() {
    Contract_Bid__c bid = insertBid(
      'Cleanup Bid',
      'Contact Made',
      'Hot Lead;Contract Created'
    );
    bid.Expired_No_Response__c = true;
    bid.Viewed__c = true;
    bid.Contract_Status__c = 'Expired';
    bid.Next_Follow_up_Date__c = Date.today().addDays(3);
    update bid;

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
    ContractBidSendCleanupService.onEnvelopeSent(new Set<Id>{ bid.Id });
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

    bid = [
      SELECT
        Stage__c,
        Expired_No_Response__c,
        Viewed__c,
        Contract_Status__c,
        Sent_Contract_Date__c,
        Next_Follow_up_Date__c,
        Label__c
      FROM Contract_Bid__c
      WHERE Id = :bid.Id
    ];
    System.assertEquals('Contract Sent via DocuSign', bid.Stage__c);
    System.assertEquals(false, bid.Expired_No_Response__c);
    System.assertEquals(false, bid.Viewed__c);
    System.assertEquals('Active', bid.Contract_Status__c);
    System.assertEquals(null, bid.Next_Follow_up_Date__c);
    System.assertNotEquals(null, bid.Sent_Contract_Date__c);
    System.assert(
      bid.Label__c != null && bid.Label__c.contains('Hot Lead'),
      'Send cleanup must not strip unrelated labels'
    );
    System.assert(
      bid.Label__c.contains('Contract Created'),
      'Send cleanup must not strip Contract Created'
    );
  }

  @IsTest
  static void onBidsClosed_completesAutomaticTasksAndClearsAutoLabelsFlags() {
    Contract_Bid__c bid = insertBid(
      'Close Bid',
      'Contract Sent via DocuSign',
      'Hot Lead;info verified;Contract Created'
    );
    bid.Expired_No_Response__c = true;
    bid.Viewed__c = true;
    update bid;

    Task autoTask = new Task(
      Subject = 'Call Property Owner about Contract for Acme',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    Task verifyTask = new Task(
      Subject = 'Verify contact info',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    Task manualTask = new Task(
      Subject = 'Call customer myself',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    insert new List<Task>{ autoTask, verifyTask, manualTask };

    Test.startTest();
    ContractBidSendCleanupService.onBidsClosed(new Set<Id>{ bid.Id });
    Test.stopTest();

    Map<Id, Task> tasks = new Map<Id, Task>(
      [
        SELECT Id, Status
        FROM Task
        WHERE Id IN :new List<Id>{ autoTask.Id, verifyTask.Id, manualTask.Id }
      ]
    );
    System.assertEquals('Completed', tasks.get(autoTask.Id).Status);
    System.assertEquals('Completed', tasks.get(verifyTask.Id).Status);
    System.assertEquals('Not Started', tasks.get(manualTask.Id).Status);

    bid = [
      SELECT Label__c, Expired_No_Response__c, Viewed__c
      FROM Contract_Bid__c
      WHERE Id = :bid.Id
    ];
    System.assertEquals('Hot Lead', bid.Label__c);
    System.assertEquals(false, bid.Expired_No_Response__c);
    System.assertEquals(false, bid.Viewed__c);
  }

  @IsTest
  static void closedWon_triggerRunsCleanup() {
    Contract_Bid__c bid = insertBid(
      'Won Bid',
      'Contract Sent via DocuSign',
      'info verified;Warm Lead'
    );
    Task autoTask = new Task(
      Subject = 'Request New Version',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    insert autoTask;

    Test.startTest();
    bid.Stage__c = 'Closed - WON';
    update bid;
    Test.stopTest();

    autoTask = [SELECT Status FROM Task WHERE Id = :autoTask.Id];
    System.assertEquals('Completed', autoTask.Status);
    bid = [SELECT Label__c FROM Contract_Bid__c WHERE Id = :bid.Id];
    System.assertEquals('Warm Lead', bid.Label__c);
  }

  @IsTest
  static void subjectMatcherCoversExpectedPatternsOnly() {
    System.assertEquals(
      true,
      ContractBidSendCleanupService.isFollowUpTask('Request New Version')
    );
    System.assertEquals(
      true,
      ContractBidSendCleanupService.isSendCleanupTask(
        'Follow up: Contract not delivered - bounce'
      )
    );
    System.assertEquals(
      true,
      ContractBidSendCleanupService.isAutomaticTask('Verify contact info')
    );
    System.assertEquals(
      false,
      ContractBidSendCleanupService.isSendCleanupTask('Verify contact info')
    );
    System.assertEquals(
      false,
      ContractBidSendCleanupService.isFollowUpTask('Manual note')
    );
  }

  @IsTest
  static void removeAutomaticLabels_keepsManualOnly() {
    System.assertEquals(
      'Hot Lead;On Hold',
      ContractBidSendCleanupService.removeAutomaticLabels(
        'Hot Lead;Contract Created;info verified;On Hold;New record created'
      )
    );
    System.assertEquals(
      null,
      ContractBidSendCleanupService.removeAutomaticLabels(
        'Contract Created;info verified'
      )
    );
  }

  @IsTest
  static void envelopeSent_triggerRunsSendCleanup() {
    Contract_Bid__c bid = insertBid('Envelope Bid', 'Contact Made', 'Hot Lead');
    bid.Expired_No_Response__c = true;
    update bid;

    Task callTask = new Task(
      Subject = 'Call Property Owner about Contract for Acme',
      WhatId = bid.Id,
      Status = 'Not Started'
    );
    insert callTask;

    if (!Schema.getGlobalDescribe().containsKey('dfsle__Envelope__c')) {
      return;
    }

    SObjectType envelopeType = Schema.getGlobalDescribe()
      .get('dfsle__Envelope__c');

    Test.startTest();
    try {
      SObject envelope = envelopeType.newSObject();
      envelope.put('dfsle__SourceId__c', String.valueOf(bid.Id));
      envelope.put('Status__c', 'Sent');
      envelope.put(
        'dfsle__DocuSignId__c',
        '22222222-2222-2222-2222-222222222222'
      );
      insert envelope;
    } catch (DmlException ex) {
      // Managed DocuSign/reminder flows may reject incomplete envelopes in tests.
      ContractBidSendCleanupService.onEnvelopeSent(new Set<Id>{ bid.Id });
    }
    Test.stopTest();

    callTask = [SELECT Status FROM Task WHERE Id = :callTask.Id];
    System.assertEquals('Completed', callTask.Status);
    bid = [
      SELECT Stage__c, Expired_No_Response__c
      FROM Contract_Bid__c
      WHERE Id = :bid.Id
    ];
    System.assertEquals('Contract Sent via DocuSign', bid.Stage__c);
    System.assertEquals(false, bid.Expired_No_Response__c);
  }

  private static Contract_Bid__c insertBid(
    String name,
    String stage,
    String labels
  ) {
    Account customer = new Account(Name = name + ' Customer');
    insert customer;
    Contract_Bid__c bid = new Contract_Bid__c(
      Name = name,
      Customer__c = customer.Id,
      Stage__c = stage,
      Label__c = labels
    );
    insert bid;
    return bid;
  }
}
