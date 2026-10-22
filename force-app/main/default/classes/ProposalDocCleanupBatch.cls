/**
 * One-time / on-demand backfill: for closed and post-approval Proposals,
 * keep only the newest generated Proposal PDF and delete older drafts.
 *
 * Run once:
 *   Database.executeBatch(new ProposalDocCleanupBatch(), 50);
 */
public without sharing class ProposalDocCleanupBatch implements Database.Batchable<SObject> {
  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Opportunity
        WHERE
          IsClosed = TRUE
          OR StageName IN :ProposalDocCleanupService.BACKFILL_STAGES
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    Set<Id> proposalIds = new Set<Id>();
    for (SObject row : scope) {
      proposalIds.add(row.Id);
    }
    ProposalDocCleanupService.cleanupKeepLatest(proposalIds);
  }

  public void finish(Database.BatchableContext context) {
    System.debug(
      LoggingLevel.INFO,
      'ProposalDocCleanupBatch finished. JobId=' + context.getJobId()
    );
  }
}
