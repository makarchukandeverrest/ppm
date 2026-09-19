public with sharing class MassSendOpportunityService {
  /**
   * Proposal (Opportunity) mass send initialization: one row per selected Proposal
   * (no Account deduplication), PDFs only from files linked to that Proposal.
   */
  public static ContractMassSendController.InitResponse buildInitData(
    List<Id> inputIds,
    ContractMassSendController.InitResponse res
  ) {
    Map<Id, Opportunity> oppById = new Map<Id, Opportunity>(
      [
        SELECT
          Id,
          Name,
          AccountId,
          Account.Name,
          Account.Primary_Contact__c,
          Account.Primary_Contact__r.Email,
          Account.Regional_Manager__c,
          Regional_Manager__c,
          Customer_Primary_Contact__c,
          Customer_Primary_Contact__r.Email
        FROM Opportunity
        WHERE Id IN :inputIds
      ]
    );

    List<ContentDocumentLink> links = [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :inputIds
    ];

    Map<Id, Set<Id>> proposalToDocIds = new Map<Id, Set<Id>>();
    Set<Id> docIds = new Set<Id>();
    for (ContentDocumentLink l : links) {
      docIds.add(l.ContentDocumentId);
      if (!proposalToDocIds.containsKey(l.LinkedEntityId)) {
        proposalToDocIds.put(l.LinkedEntityId, new Set<Id>());
      }
      proposalToDocIds.get(l.LinkedEntityId).add(l.ContentDocumentId);
    }

    List<ContentVersion> cvs = docIds.isEmpty()
      ? new List<ContentVersion>()
      : [
          SELECT
            Id,
            Title,
            ContentDocumentId,
            VersionNumber,
            FileExtension,
            ContentDocument.LastModifiedDate
          FROM ContentVersion
          WHERE
            ContentDocumentId IN :docIds
            AND IsLatest = TRUE
            AND FileExtension = 'pdf'
          ORDER BY ContentDocument.LastModifiedDate DESC
        ];

    Map<Id, ContractMassSendController.ContractDto> latestByDoc = new Map<Id, ContractMassSendController.ContractDto>();
    for (ContentVersion cv : cvs) {
      ContractMassSendController.ContractDto cd = new ContractMassSendController.ContractDto();
      cd.contentVersionId = cv.Id;
      cd.contentDocumentId = cv.ContentDocumentId;
      cd.title = cv.Title;
      cd.versionNumber = Integer.valueOf(cv.VersionNumber);
      cd.fileExtension = cv.FileExtension;
      latestByDoc.put(cv.ContentDocumentId, cd);
    }

    res.customers = new List<ContractMassSendController.CustomerDto>();
    for (Id oppId : inputIds) {
      Opportunity opp = oppById.get(oppId);
      if (opp == null) {
        continue;
      }

      ContractMassSendController.CustomerDto dto = new ContractMassSendController.CustomerDto();
      dto.customerId = opp.Id;
      dto.customerName = opp.Name;
      dto.accountName = opp.AccountId != null ? opp.Account.Name : null;
      dto.regionalManagerId = opp.Regional_Manager__c != null
        ? opp.Regional_Manager__c
        : (opp.AccountId != null ? opp.Account.Regional_Manager__c : null);
      dto.contracts = new List<ContractMassSendController.ContractDto>();

      if (opp.Customer_Primary_Contact__c != null) {
        dto.customerEmail = opp.Customer_Primary_Contact__r != null
          ? opp.Customer_Primary_Contact__r.Email
          : null;
        dto.primaryContactMissing = opp.Customer_Primary_Contact__r == null;
      } else if (opp.AccountId != null) {
        dto.customerEmail = opp.Account.Primary_Contact__r != null
          ? opp.Account.Primary_Contact__r.Email
          : null;
        dto.primaryContactMissing = opp.Account.Primary_Contact__r == null;
      } else {
        dto.customerEmail = null;
        dto.primaryContactMissing = true;
      }

      if (proposalToDocIds.containsKey(opp.Id)) {
        for (Id docId : proposalToDocIds.get(opp.Id)) {
          if (latestByDoc.containsKey(docId)) {
            dto.contracts.add(latestByDoc.get(docId));
          }
        }
      }

      res.customers.add(dto);
    }

    res.templates = ContractMassSendController.loadPremierPoolTemplatesForUi();
    res.recentLogs = new List<ContractMassSendController.LogRowDto>();
    return res;
  }
}
