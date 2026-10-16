@IsTest
private class ProposalDocCleanupServiceTest {
  @TestSetup
  static void setupData() {
    insert new Account(Name = 'Cleanup Proposal Account');
  }

  @IsTest
  static void cleanup_DeletesOutdatedGeneratedDrafts() {
    Opportunity proposal = insertProposal('Cleanup Delete Drafts');
    Id draftDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal Draft',
      'Premier Proposal Draft.pdf',
      null,
      null,
      'Proposal Draft.pdf',
      'PDF'
    );
    Id supportingDocId = insertLinkedPdf(
      proposal.Id,
      'Supporting Attachment',
      'Supporting Attachment.pdf',
      null,
      null,
      null,
      null
    );
    Id certificateDocId = insertLinkedPdf(
      proposal.Id,
      'Certificate of Completion',
      'Certificate of Completion.pdf',
      null,
      null,
      null,
      null
    );
    Id finalDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal_completed',
      'Premier Proposal_completed.pdf',
      null,
      'Completed',
      null,
      null
    );

    Test.startTest();
    ProposalDocCleanupService.cleanup(new Set<Id>{ proposal.Id });
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :draftDocId],
      'Outdated generated draft should be deleted'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :finalDocId],
      'Final completed document should remain'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :supportingDocId],
      'Unrelated supporting attachment should remain'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :certificateDocId],
      'Completion certificate should remain'
    );
  }

  @IsTest
  static void cleanup_SkipsWhenFinalMissing() {
    Opportunity proposal = insertProposal('Cleanup Skip No Final');
    Id draftDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal Draft',
      'Premier Proposal Draft.pdf',
      null,
      null,
      'Proposal Draft.pdf',
      'PDF'
    );

    Test.startTest();
    ProposalDocCleanupService.cleanup(new Set<Id>{ proposal.Id });
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :draftDocId],
      'No deletions when final document cannot be identified'
    );
  }

  @IsTest
  static void nonCompletedStage_DoesNotEnqueueCleanup() {
    Opportunity proposal = insertProposal('Cleanup Before Complete');
    Id draftDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal Draft',
      'Premier Proposal Draft.pdf',
      null,
      null,
      'Proposal Draft.pdf',
      'PDF'
    );
    insertLinkedPdf(
      proposal.Id,
      'Premier Proposal_completed',
      'Premier Proposal_completed.pdf',
      null,
      'Completed',
      null,
      null
    );

    Test.startTest();
    proposal.StageName = 'Negotiation';
    update proposal;
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :draftDocId],
      'Cleanup must not run before completed stage'
    );
  }

  @IsTest
  static void enqueueForStageTransition_RunsCleanupOnApproved() {
    Opportunity proposal = insertProposal('Cleanup Enqueue Approved');
    Id draftDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal Draft',
      'Premier Proposal Draft.pdf',
      null,
      null,
      'Proposal Draft.pdf',
      'PDF'
    );
    Id finalDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal_completed',
      'Premier Proposal_completed.pdf',
      null,
      'Completed',
      null,
      null
    );

    Opportunity oldProposal = proposal.clone(true, true, false, false);
    oldProposal.StageName = 'Draft';
    proposal.StageName = 'Approved';

    Test.startTest();
    ProposalDocCleanupService.enqueueForStageTransition(
      new List<Opportunity>{ proposal },
      new Map<Id, Opportunity>{ proposal.Id => oldProposal }
    );
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :draftDocId],
      'Transition into Approved should delete outdated drafts'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :finalDocId],
      'Final document should remain after transition cleanup'
    );
  }

  @IsTest
  static void repeatedCleanup_IsIdempotent() {
    Opportunity proposal = insertProposal('Cleanup Idempotent');
    Id draftDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal Draft',
      'Premier Proposal Draft.pdf',
      null,
      null,
      'Proposal Draft.pdf',
      'PDF'
    );
    Id finalDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal_completed',
      'Premier Proposal_completed.pdf',
      'ENV-1',
      'Completed',
      null,
      null
    );

    ProposalDocCleanupService.cleanup(new Set<Id>{ proposal.Id });
    System.assertEquals(
      0,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :draftDocId]
    );

    Test.startTest();
    ProposalDocCleanupService.cleanup(new Set<Id>{ proposal.Id });
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :finalDocId],
      'Repeated cleanup must keep the final document'
    );
  }

  @IsTest
  static void keepsFilesWithEnvelopeId() {
    Opportunity proposal = insertProposal('Cleanup Keep Envelope');
    Id sentDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal Sent',
      'Premier Proposal Sent.pdf',
      'ENV-SENT',
      'Sent',
      'Proposal Sent.pdf',
      'PDF'
    );
    insertLinkedPdf(
      proposal.Id,
      'Premier Proposal_completed',
      'Premier Proposal_completed.pdf',
      null,
      'Completed',
      null,
      null
    );

    Test.startTest();
    ProposalDocCleanupService.cleanup(new Set<Id>{ proposal.Id });
    Test.stopTest();

    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :sentDocId],
      'Files with Envelope Id must be retained'
    );
  }

  @IsTest
  static void cleanupKeepLatest_KeepsNewestWithoutCompleted() {
    Opportunity proposal = insertProposal('Cleanup Keep Latest');
    Id olderDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal Older',
      'Premier Proposal Older.pdf',
      null,
      null,
      'Proposal Older.pdf',
      'PDF'
    );
    Id newerDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal Newer',
      'Premier Proposal Newer.pdf',
      null,
      null,
      'Proposal Newer.pdf',
      'PDF'
    );
    Id supportingDocId = insertLinkedPdf(
      proposal.Id,
      'Supporting Attachment',
      'Supporting Attachment.pdf',
      null,
      null,
      null,
      null
    );

    Test.startTest();
    ProposalDocCleanupService.cleanupKeepLatest(new Set<Id>{ proposal.Id });
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :olderDocId],
      'Older generated draft should be deleted'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :newerDocId],
      'Newest generated draft should remain even without completed marker'
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :supportingDocId],
      'Supporting attachment should remain'
    );
  }

  @IsTest
  static void cleanupKeepLatestBatch_RunsForBackfillStages() {
    Opportunity proposal = insertProposal('Cleanup Batch Proposal');
    proposal.StageName = 'Closed Won';
    update proposal;

    Id olderDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal Older',
      'Premier Proposal Older.pdf',
      null,
      null,
      'Proposal Older.pdf',
      'PDF'
    );
    insertLinkedPdf(
      proposal.Id,
      'Premier Proposal Newer',
      'Premier Proposal Newer.pdf',
      null,
      null,
      'Proposal Newer.pdf',
      'PDF'
    );

    Test.startTest();
    Database.executeBatch(new ProposalDocCleanupBatch(), 50);
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :olderDocId],
      'Batch keepLatest should delete older generated drafts'
    );
  }

  @IsTest
  static void queueableJob_RunsCleanup() {
    Opportunity proposal = insertProposal('Cleanup Queueable');
    Id draftDocId = insertLinkedPdf(
      proposal.Id,
      'Premier Proposal Draft',
      'Premier Proposal Draft.pdf',
      null,
      null,
      'Proposal Draft.pdf',
      'PDF'
    );
    insertLinkedPdf(
      proposal.Id,
      'Premier Proposal_completed',
      'Premier Proposal_completed.pdf',
      null,
      'Completed',
      null,
      null
    );

    Test.startTest();
    System.enqueueJob(new ProposalDocCleanupJob(new Set<Id>{ proposal.Id }));
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM ContentDocument WHERE Id = :draftDocId],
      'Queueable should delete outdated generated drafts'
    );
  }

  private static Opportunity insertProposal(String name) {
    Account acc = [
      SELECT Id
      FROM Account
      WHERE Name = 'Cleanup Proposal Account'
      LIMIT 1
    ];
    Opportunity proposal = new Opportunity(
      Name = name,
      AccountId = acc.Id,
      CloseDate = Date.today().addDays(30),
      StageName = 'Draft'
    );
    insert proposal;
    return proposal;
  }

  private static Id insertLinkedPdf(
    Id proposalId,
    String title,
    String pathOnClient,
    String envelopeId,
    String envelopeStatus,
    String generatedFileName,
    String generatedFileFormat
  ) {
    ContentVersion version = new ContentVersion(
      Title = title,
      PathOnClient = pathOnClient,
      VersionData = Blob.valueOf('pdf-' + title),
      IsMajorVersion = true,
      FirstPublishLocationId = proposalId,
      DocuSign_Envelope_Id__c = envelopeId,
      DocuSign_Envelope_Status__c = envelopeStatus,
      dfsle__GeneratedFileName__c = generatedFileName,
      dfsle__GeneratedFileFormat__c = generatedFileFormat
    );
    insert version;
    return [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
    ]
    .ContentDocumentId;
  }
}
