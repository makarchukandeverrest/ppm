public class ContractBidBudgetSeasonScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        ContractBidBudgetSeasonService.createTasks();
    }
}
