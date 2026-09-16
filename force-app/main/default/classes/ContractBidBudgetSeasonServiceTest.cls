@IsTest
private class ContractBidBudgetSeasonServiceTest {

    private static final List<String> MONTHS = new List<String>{
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    };

    @TestSetup
    static void setup() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User regionalManager = new User(
            FirstName = 'Regional',
            LastName = 'Manager',
            Email = 'budget.season.rm@example.com',
            Username = 'budget.season.rm.' + System.currentTimeMillis() + '@example.com',
            Alias = 'bsrm',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert regionalManager;

        Account customer = new Account(Name = 'Budget Season Customer');
        insert customer;

        String currentMonth = MONTHS[Date.today().month() - 1];
        String otherMonth = MONTHS[Math.mod(Date.today().month(), 12)];

        insert new List<Contract_Bid__c>{
            new Contract_Bid__c(
                Name = 'Current Month Bid',
                Customer__c = customer.Id,
                Budget_Season__c = currentMonth,
                Lead_Owner__c = regionalManager.Id
            ),
            new Contract_Bid__c(
                Name = 'Other Month Bid',
                Customer__c = customer.Id,
                Budget_Season__c = otherMonth,
                Lead_Owner__c = regionalManager.Id
            ),
            new Contract_Bid__c(
                Name = 'Current Month No Owner',
                Customer__c = customer.Id,
                Budget_Season__c = currentMonth
            )
        };
    }

    @IsTest
    static void createTasks_createsTaskOnlyForCurrentMonthWithRegionalManager() {
        User regionalManager = [
            SELECT Id
            FROM User
            WHERE Email = 'budget.season.rm@example.com'
            LIMIT 1
        ];
        Contract_Bid__c currentMonthBid = [
            SELECT Id
            FROM Contract_Bid__c
            WHERE Name = 'Current Month Bid'
            LIMIT 1
        ];
        Test.startTest();
        ContractBidBudgetSeasonService.createTasks();
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id, OwnerId, WhatId, Subject, Description, Status, Priority, ActivityDate
            FROM Task
            WHERE WhatId IN (SELECT Id FROM Contract_Bid__c)
        ];

        System.assertEquals(1, tasks.size(), 'Only the current-month bid with a Regional Manager should get a Task');
        Task createdTask = tasks[0];
        System.assertEquals(regionalManager.Id, createdTask.OwnerId);
        System.assertEquals(currentMonthBid.Id, createdTask.WhatId);
        System.assertEquals('Not Started', createdTask.Status);
        System.assertEquals('Normal', createdTask.Priority);
        System.assertEquals(Date.today(), createdTask.ActivityDate);
        System.assertEquals('Time to Follow up', createdTask.Subject);
        System.assert(
            createdTask.Description.contains('It\'s time to reach out to this pool.'),
            'Description should contain the follow-up body'
        );
    }

    @IsTest
    static void scheduler_executesCreateTasks() {
        Test.startTest();
        System.schedule(
            'ContractBidBudgetSeasonSchedulerTest',
            '0 0 0 1 1 ? 2099',
            new ContractBidBudgetSeasonScheduler()
        );
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id
            FROM Task
            WHERE WhatId IN (SELECT Id FROM Contract_Bid__c WHERE Name = 'Current Month Bid')
        ];
        System.assertEquals(1, tasks.size(), 'Scheduler should create the Regional Manager Task');
    }
}
