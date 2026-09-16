public with sharing class ContractBidBudgetSeasonService {

    private static final String TASK_SUBJECT = 'Time to Follow up';
    private static final String TASK_DESCRIPTION =
        'Hi there!\n\n' +
        'It\'s time to reach out to this pool. Please contact the appropriate person to discuss their upcoming needs and potential opportunities for the next season.\n\n' +
        'Please document any updates or follow-up actions accordingly.';

    private static final List<String> MONTHS = new List<String>{
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    };

    public static void createTasks() {
        String currentMonth = MONTHS[Date.today().month() - 1];

        List<Contract_Bid__c> contractBids = [
            SELECT Id, Lead_Owner__c
            FROM Contract_Bid__c
            WHERE Budget_Season__c = :currentMonth
            AND Lead_Owner__c != null
        ];

        if (contractBids.isEmpty()) {
            return;
        }

        List<Task> tasksToInsert = new List<Task>();
        for (Contract_Bid__c bid : contractBids) {
            tasksToInsert.add(new Task(
                OwnerId = bid.Lead_Owner__c,
                WhatId = bid.Id,
                Subject = TASK_SUBJECT,
                Description = TASK_DESCRIPTION,
                Status = 'Not Started',
                Priority = 'Normal',
                ActivityDate = Date.today()
            ));
        }

        insert tasksToInsert;
    }
}
