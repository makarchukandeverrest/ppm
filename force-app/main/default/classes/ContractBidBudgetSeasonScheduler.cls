// Must be scheduled by a System Administrator. Schedulable.execute runs as that
// user, which AutomationTaskCreator requires for CreatedById (Set Audit Fields).
public class ContractBidBudgetSeasonScheduler implements Schedulable {
  public void execute(SchedulableContext sc) {
    ContractBidBudgetSeasonService.createTasks();
  }
}
