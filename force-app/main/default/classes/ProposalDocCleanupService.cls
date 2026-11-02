public with sharing class ProposalDocCleanupService {
  public class ProposalDocCleanupException extends Exception {
  }

  @TestVisible
  private static final Set<String> COMPLETED_STAGES = new Set<String>{
    'Approved'
  };

  /**
   * Stages for one-time / batch backfill (closed + post-approval pipeline).
   * IsClosed proposals are always included by the batch query as well.
   */
  @TestVisible
  public static final Set<String> BACKFILL_STAGES = new Set<String>{
    'Approved',
    'WO Issued',
    'Invoiced - WO Completed',
    'Closed Won',
    'Abandoned'
  };

  private static final String COMPLETED_TOKEN = '_completed';
  private static final String COMPLETED_SUFFIX = ' - completed';
  private static final String CERTIFICATE_TOKEN = 'certificate';
  @TestVisible
  private static final String FEED_PREFIX = 'Proposal document cleanup: ';

  public static void enqueueForStageTransition(
    List<Opportunity> newList,
    Map<Id, Opportunity> oldMap
  ) {
    Set<Id> proposalIds = collectTransitionedProposalIds(newList, oldMap);
    if (proposalIds.isEmpty()) {
      return;
    }

    if (Test.isRunningTest()) {
      cleanup(proposalIds);
      return;
    }

    System.enqueueJob(new ProposalDocCleanupJob(proposalIds));
  }

  public static void cleanup(Set<Id> proposalIds) {
    if (proposalIds == null || proposalIds.isEmpty()) {
      return;
    }

    for (Id proposalId : proposalIds) {
      cleanupOne(proposalId);
    }
  }

  /**
   * Historical cleanup: among generated Proposal PDFs keep only the newest
   * (by ContentVersion.CreatedDate). Completed marker is not required.
   * Certificates, supporting attachments, Envelope-linked and shared files are kept.
   */
  public static void cleanupKeepLatest(Set<Id> proposalIds) {
    if (proposalIds == null || proposalIds.isEmpty()) {
      return;
    }

    for (Id proposalId : proposalIds) {
      cleanupKeepLatestOne(proposalId);
    }
  }

  @TestVisible
  private static void cleanupOne(Id proposalId) {
    List<ContentVersion> versions = queryLinkedVersions(proposalId);
    if (versions == null) {
      return;
    }

    if (!hasIdentifiableFinal(versions)) {
      logSkip(
        proposalId,
        'Final completed document not found or not identifiable'
      );
      return;
    }

    Set<Id> contentDocumentIds = collectDocumentIds(versions);
    Set<Id> sharedDocumentIds = findDocumentsLinkedElsewhere(
      contentDocumentIds,
      proposalId
    );
    Set<Id> documentsToDelete = new Set<Id>();

    for (ContentVersion version : versions) {
      if (
        isDeleteCandidate(version) &&
        !sharedDocumentIds.contains(version.ContentDocumentId)
      ) {
        documentsToDelete.add(version.ContentDocumentId);
      }
    }

    deleteDocuments(proposalId, documentsToDelete);
  }

  @TestVisible
  private static void cleanupKeepLatestOne(Id proposalId) {
    List<ContentVersion> versions = queryLinkedVersions(proposalId);
    if (versions == null) {
      return;
    }

    Set<Id> contentDocumentIds = collectDocumentIds(versions);
    Set<Id> sharedDocumentIds = findDocumentsLinkedElsewhere(
      contentDocumentIds,
      proposalId
    );

    List<ContentVersion> generatedVersions = new List<ContentVersion>();
    for (ContentVersion version : versions) {
      if (!isGeneratedProposalPdf(version)) {
        continue;
      }
      if (sharedDocumentIds.contains(version.ContentDocumentId)) {
        continue;
      }
      generatedVersions.add(version);
    }

    if (generatedVersions.size() <= 1) {
      System.debug(
        LoggingLevel.INFO,
        'ProposalDocCleanup keepLatest: nothing to delete for Proposal ' +
        proposalId
      );
      return;
    }

    ContentVersion keepVersion = generatedVersions[0];
    for (ContentVersion version : generatedVersions) {
      if (isNewerVersion(version, keepVersion)) {
        keepVersion = version;
      }
    }

    Set<Id> documentsToDelete = new Set<Id>();
    for (ContentVersion version : generatedVersions) {
      if (version.ContentDocumentId == keepVersion.ContentDocumentId) {
        continue;
      }
      // Prefer not to delete an older signed/completed file if a newer draft exists.
      if (isFinalDocument(version) || hasEnvelopeLink(version)) {
        continue;
      }
      documentsToDelete.add(version.ContentDocumentId);
    }

    deleteDocuments(proposalId, documentsToDelete);
  }

  private static List<ContentVersion> queryLinkedVersions(Id proposalId) {
    List<ContentDocumentLink> links = [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :proposalId
    ];
    if (links.isEmpty()) {
      logSkip(proposalId, 'No files linked to Proposal');
      return null;
    }

    Set<Id> contentDocumentIds = new Set<Id>();
    for (ContentDocumentLink link : links) {
      contentDocumentIds.add(link.ContentDocumentId);
    }

    List<ContentVersion> versions = [
      SELECT
        Id,
        Title,
        ContentDocumentId,
        FileExtension,
        CreatedDate,
        DocuSign_Envelope_Id__c,
        DocuSign_Envelope_Status__c,
        dfsle__GeneratedFileName__c,
        dfsle__GeneratedFileFormat__c
      FROM ContentVersion
      WHERE ContentDocumentId IN :contentDocumentIds AND IsLatest = TRUE
    ];
    if (versions.isEmpty()) {
      logSkip(proposalId, 'No latest ContentVersion rows found');
      return null;
    }
    return versions;
  }

  private static Set<Id> collectDocumentIds(List<ContentVersion> versions) {
    Set<Id> contentDocumentIds = new Set<Id>();
    for (ContentVersion version : versions) {
      contentDocumentIds.add(version.ContentDocumentId);
    }
    return contentDocumentIds;
  }

  private static void deleteDocuments(
    Id proposalId,
    Set<Id> documentsToDelete
  ) {
    if (documentsToDelete == null || documentsToDelete.isEmpty()) {
      System.debug(
        LoggingLevel.INFO,
        'ProposalDocCleanup: nothing to delete for Proposal ' + proposalId
      );
      return;
    }

    List<ContentDocument> documents = [
      SELECT Id
      FROM ContentDocument
      WHERE Id IN :documentsToDelete
    ];
    if (documents.isEmpty()) {
      return;
    }

    List<Database.DeleteResult> results = Database.delete(documents, false);
    Integer deletedCount = 0;
    List<String> errors = new List<String>();
    for (Database.DeleteResult result : results) {
      if (result.isSuccess()) {
        deletedCount++;
        continue;
      }
      for (Database.Error err : result.getErrors()) {
        errors.add(err.getMessage());
      }
    }

    if (!errors.isEmpty()) {
      String failMessage =
        FEED_PREFIX +
        'could not delete ' +
        errors.size() +
        ' file(s). ' +
        String.join(errors, '; ');
      postProposalFeed(proposalId, failMessage);
      throw new ProposalDocCleanupException(failMessage);
    }

    postProposalFeed(
      proposalId,
      FEED_PREFIX + 'removed ' + deletedCount + ' outdated generated PDF(s).'
    );
  }

  private static void postProposalFeed(Id proposalId, String body) {
    if (proposalId == null || String.isBlank(body)) {
      return;
    }
    try {
      insert new FeedItem(
        ParentId = proposalId,
        Body = body,
        Type = 'TextPost'
      );
    } catch (Exception feedEx) {
      System.debug(
        LoggingLevel.ERROR,
        'ProposalDocCleanup: failed to post feed for Proposal ' +
          proposalId +
          ': ' +
          feedEx.getMessage()
      );
    }
  }

  @TestVisible
  private static Set<Id> collectTransitionedProposalIds(
    List<Opportunity> newList,
    Map<Id, Opportunity> oldMap
  ) {
    Set<Id> proposalIds = new Set<Id>();
    if (newList == null || oldMap == null) {
      return proposalIds;
    }

    for (Opportunity proposal : newList) {
      Opportunity oldProposal = oldMap.get(proposal.Id);
      if (oldProposal == null) {
        continue;
      }
      if (
        COMPLETED_STAGES.contains(proposal.StageName) &&
        proposal.StageName != oldProposal.StageName
      ) {
        proposalIds.add(proposal.Id);
      }
    }
    return proposalIds;
  }

  @TestVisible
  private static Boolean hasIdentifiableFinal(List<ContentVersion> versions) {
    for (ContentVersion version : versions) {
      if (isFinalDocument(version)) {
        return true;
      }
    }
    return false;
  }

  @TestVisible
  private static Boolean isDeleteCandidate(ContentVersion version) {
    if (version == null || version.ContentDocumentId == null) {
      return false;
    }
    if (isFinalDocument(version) || hasEnvelopeLink(version)) {
      return false;
    }
    return isGeneratedProposalPdf(version);
  }

  @TestVisible
  private static Boolean isGeneratedProposalPdf(ContentVersion version) {
    if (version == null || version.ContentDocumentId == null) {
      return false;
    }
    if (!isPdf(version) || looksLikeCertificate(version)) {
      return false;
    }
    return looksLikeGeneratedProposalDocument(version);
  }

  private static Boolean isNewerVersion(
    ContentVersion candidate,
    ContentVersion currentKeep
  ) {
    if (candidate.CreatedDate > currentKeep.CreatedDate) {
      return true;
    }
    if (candidate.CreatedDate < currentKeep.CreatedDate) {
      return false;
    }
    // Same-second inserts in tests/batches: prefer higher Id (usually newer).
    return String.valueOf(candidate.Id)
        .compareTo(String.valueOf(currentKeep.Id)) > 0;
  }

  @TestVisible
  private static Boolean isFinalDocument(ContentVersion version) {
    if (version == null) {
      return false;
    }
    String title = version.Title != null ? version.Title.toLowerCase() : '';
    if (title.contains(COMPLETED_TOKEN) || title.contains(COMPLETED_SUFFIX)) {
      return true;
    }
    return version.DocuSign_Envelope_Status__c != null &&
      version.DocuSign_Envelope_Status__c.trim().equalsIgnoreCase('Completed');
  }

  private static Boolean hasEnvelopeLink(ContentVersion version) {
    return version != null &&
      String.isNotBlank(version.DocuSign_Envelope_Id__c);
  }

  private static Boolean isPdf(ContentVersion version) {
    return version != null &&
      version.FileExtension != null &&
      version.FileExtension.equalsIgnoreCase('pdf');
  }

  private static Boolean looksLikeCertificate(ContentVersion version) {
    return version != null &&
      version.Title != null &&
      version.Title.toLowerCase().contains(CERTIFICATE_TOKEN);
  }

  /**
   * Only DocuSign-generated files (dfsle generated fields), never title matching.
   * A hand-uploaded PDF whose title contains "proposal" must not be deleted.
   */
  @TestVisible
  private static Boolean looksLikeGeneratedProposalDocument(
    ContentVersion version
  ) {
    if (version == null) {
      return false;
    }
    return String.isNotBlank(version.dfsle__GeneratedFileName__c) ||
      String.isNotBlank(version.dfsle__GeneratedFileFormat__c);
  }

  private static Set<Id> findDocumentsLinkedElsewhere(
    Set<Id> contentDocumentIds,
    Id proposalId
  ) {
    Set<Id> sharedDocumentIds = new Set<Id>();
    if (
      contentDocumentIds == null ||
      contentDocumentIds.isEmpty() ||
      proposalId == null
    ) {
      return sharedDocumentIds;
    }

    for (ContentDocumentLink link : [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE ContentDocumentId IN :contentDocumentIds
    ]) {
      if (link.LinkedEntityId == null || link.LinkedEntityId == proposalId) {
        continue;
      }
      Schema.SObjectType linkedType = link.LinkedEntityId.getSObjectType();
      if (linkedType == User.SObjectType) {
        continue;
      }
      sharedDocumentIds.add(link.ContentDocumentId);
    }
    return sharedDocumentIds;
  }

  private static void logSkip(Id proposalId, String reason) {
    System.debug(
      LoggingLevel.WARN,
      'ProposalDocCleanup: skip Proposal ' + proposalId + ' — ' + reason
    );
  }
}
