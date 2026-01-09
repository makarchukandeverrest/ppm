public class ItemsSharePointScheduledJob implements Schedulable {

    public void execute(SchedulableContext sc) {
        try {
            Database.executeBatch(new ContentVersionFromItemsSharePointBatch(), 1);// Create ContentVersion and Links
        } finally {
            rescheduleJob();
        }
    }

    private static void rescheduleJob() {
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'ItemsSharePointScheduledJob']) {
            System.abortJob(ct.Id);
        }
        DateTime nextRunTime = DateTime.now().addMinutes(5);
        String cronExpression = nextRunTime.second() + ' ' +
                                nextRunTime.minute() + ' ' +
                                nextRunTime.hour() + ' ' +
                                nextRunTime.day() + ' ' +
                                nextRunTime.month() + ' ? ' +
                                nextRunTime.year();

        System.schedule('ItemsSharePointScheduledJob',
                        cronExpression,
                        new ItemsSharePointScheduledJob());
    }
}