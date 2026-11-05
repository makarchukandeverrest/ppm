public without sharing class ProposalDocCleanupJob implements Queueable {
  private final Set<Id> proposalIds;

  public ProposalDocCleanupJob(Set<Id> proposalIds) {
    this.proposalIds = proposalIds == null
      ? new Set<Id>()
      : new Set<Id>(proposalIds);
  }

  public void execute(QueueableContext context) {
    ProposalDocCleanupService.cleanup(proposalIds);
  }
}
