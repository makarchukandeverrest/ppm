public with sharing class ProposalDocCleanupService {
  @TestVisible
  private static final Set<String> COMPLETED_STAGES = new Set<String>{
    'Approved'
  };

  private static final String COMPLETED_TOKEN = '_completed';
  private static final String COMPLETED_SUFFIX = ' - completed';
  private static final String CERTIFICATE_TOKEN = 'certificate';

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

  @TestVisible
  private static void cleanupOne(Id proposalId) {
    List<ContentDocumentLink> links = [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :proposalId
    ];
    if (links.isEmpty()) {
      logSkip(proposalId, 'No files linked to Proposal');
      return;
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
        DocuSign_Envelope_Id__c,
        DocuSign_Envelope_Status__c,
        dfsle__GeneratedFileName__c,
        dfsle__GeneratedFileFormat__c
      FROM ContentVersion
      WHERE ContentDocumentId IN :contentDocumentIds AND IsLatest = TRUE
    ];
    if (versions.isEmpty()) {
      logSkip(proposalId, 'No latest ContentVersion rows found');
      return;
    }

    if (!hasIdentifiableFinal(versions)) {
      logSkip(
        proposalId,
        'Final completed document not found or not identifiable'
      );
      return;
    }

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

    if (documentsToDelete.isEmpty()) {
      System.debug(
        LoggingLevel.INFO,
        'ProposalDocCleanup: nothing to delete for Proposal ' + proposalId
      );
      return;
    }

    try {
      delete [SELECT Id FROM ContentDocument WHERE Id IN :documentsToDelete];
      System.debug(
        LoggingLevel.INFO,
        'ProposalDocCleanup: deleted ' +
          documentsToDelete.size() +
          ' ContentDocument(s) for Proposal ' +
          proposalId +
          ': ' +
          documentsToDelete
      );
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.ERROR,
        'ProposalDocCleanup: delete failed for Proposal ' +
          proposalId +
          ': ' +
          ex.getMessage() +
          '\n' +
          ex.getStackTraceString()
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
    if (!isPdf(version) || looksLikeCertificate(version)) {
      return false;
    }
    return looksLikeGeneratedProposalDocument(version);
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

  @TestVisible
  private static Boolean looksLikeGeneratedProposalDocument(
    ContentVersion version
  ) {
    if (version == null) {
      return false;
    }
    if (
      String.isNotBlank(version.dfsle__GeneratedFileName__c) ||
      String.isNotBlank(version.dfsle__GeneratedFileFormat__c)
    ) {
      return true;
    }
    return version.Title != null &&
      version.Title.toLowerCase().contains('proposal');
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
