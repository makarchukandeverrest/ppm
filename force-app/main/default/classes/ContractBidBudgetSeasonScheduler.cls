// Schedulable.execute runs as the user who scheduled the job. Schedule only as
// System Administrator so AutomationTaskCreator can set CreatedById.
public class ContractBidBudgetSeasonScheduler implements Schedulable {
  public static final String JOB_NAME = 'Contract Bid Budget Season Follow-up';
  // 1st of every month at 06:00 (org time).
  public static final String CRON_MONTHLY = '0 0 6 1 * ?';

  public void execute(SchedulableContext sc) {
    ContractBidBudgetSeasonService.createTasks();
  }

  public static Id scheduleMonthly() {
    abortExisting();
    return System.schedule(
      JOB_NAME,
      CRON_MONTHLY,
      new ContractBidBudgetSeasonScheduler()
    );
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
