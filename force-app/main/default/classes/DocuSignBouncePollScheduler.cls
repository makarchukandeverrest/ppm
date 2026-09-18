public with sharing class DocuSignBouncePollScheduler implements Schedulable {
    public static final String JOB_NAME = 'DocuSign Bounce Poll Hourly';
    public static final String CRON_HOURLY = '0 20 * * * ?';

    public void execute(SchedulableContext sc) {
        DocuSignBouncePollService.stampExistingAutoResponded();
        Database.executeBatch(new DocuSignBouncePollBatch(), 20);
    }

    public static Id scheduleHourly() {
        abortExisting();
        return System.schedule(JOB_NAME, CRON_HOURLY, new DocuSignBouncePollScheduler());
    }

    public static void abortExisting() {
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
        ]) {
            System.abortJob(ct.Id);
        }
    }
}
