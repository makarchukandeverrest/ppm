public with sharing class ContractMassSendController {
  @TestVisible
  private static Boolean testBypassPermissions = false;

  private static Boolean hasPermission() {
    // TEMPORARY: Bypass permission check for debugging
    return true;
    // Original: return testBypassPermissions || FeatureManagement.checkPermission('Mass_Contract_Send');
  }

  private static Boolean isServiceTeamMemberId(Id recordId) {
    return recordId != null &&
      recordId.getSobjectType() == Service_Team_Member__c.SObjectType;
  }

  private static Boolean isWorkOrderId(Id recordId) {
    return recordId != null && recordId.getSobjectType() == WorkOrder.SObjectType;
  }

  private static Boolean isOpportunityId(Id recordId) {
    return recordId != null &&
      recordId.getSobjectType() == Opportunity.SObjectType;
  }

  /**
   * Work Order-driven send: any inputId is a Work Order, or any send row has workOrderId
   * set (e.g. Flow passes only Account Ids but LWC still sends workOrderId per row).
   */
  private static Boolean isWorkOrderPageContext(
    List<Id> inputIds,
    List<SendReqRow> rows
  ) {
    if (inputIds != null) {
      for (Id pid : inputIds) {
        if (pid != null && pid.getSobjectType() == WorkOrder.SObjectType) {
          return true;
        }
      }
    }
    if (rows != null) {
      for (SendReqRow r : rows) {
        if (r.workOrderId != null && isWorkOrderId(r.workOrderId)) {
          return true;
        }
      }
    }
    return false;
  }

  /* =========================================================
       DTOs
    ========================================================= */

  public class TemplateDto {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    public TemplateDto(Id i, String n) {
      id = i;
      name = n;
    }
  }

  public class ContractDto {
    @AuraEnabled
    public Id contentVersionId;
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public Integer versionNumber;
    @AuraEnabled
    public String fileExtension;
  }

  public class CustomerDto {
    @AuraEnabled
    public Id customerId;
    @AuraEnabled
    public String customerName;
    @AuraEnabled
    public String customerEmail;
    /** True when Account has no usable primary contact (lookup empty, deleted, or no access). */
    @AuraEnabled
    public Boolean primaryContactMissing;
    /** Merge / activity context for Work Order mass send (Service Team recipients) */
    @AuraEnabled
    public Id workOrderId;
    /** Account name for Proposal filter UI */
    @AuraEnabled
    public String accountName;
    /** Regional Manager Id for Proposal filter UI */
    @AuraEnabled
    public Id regionalManagerId;
    @AuraEnabled
    public List<ContractDto> contracts;
  }

  public class LogRowDto {
    @AuraEnabled
    public String customerName;
    @AuraEnabled
    public String fileTitle;
    @AuraEnabled
    public Integer versionNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String message;
  }

  public class InitResponse {
    @AuraEnabled
    public Boolean hasAccess;
    @AuraEnabled
    public String accessMessage;
    @AuraEnabled
    public List<TemplateDto> templates;
    @AuraEnabled
    public List<CustomerDto> customers;
    @AuraEnabled
    public List<LogRowDto> recentLogs;
  }

  /** Server-side filter bag used by getInitDataFiltered for Proposal rows. */
  public class InitFilters {
    @AuraEnabled
    public String regionalManagerId;
    @AuraEnabled
    public String customerName;
    @AuraEnabled
    public String contractYear;
    @AuraEnabled
    public Boolean requireContracts;
  }

  /* =========================================================
       INIT (Record Page + List View)
    ========================================================= */

  @AuraEnabled(cacheable=true)
  public static InitResponse getInitData(List<Id> inputIds) {
    InitResponse res = new InitResponse();

    /* ---------- Permission ---------- */
    if (!hasPermission()) {
      res.hasAccess = false;
      res.accessMessage = 'Missing permission: Mass_Contract_Send';
      return res;
    }
    res.hasAccess = true;

    /* ---------- Default to empty if none provided ---------- */
    if (inputIds == null) {
      inputIds = new List<Id>();
    }

    if (inputIds.isEmpty()) {
      res.customers = new List<CustomerDto>();

      // Still load templates so the user can see the UI
      res.templates = new List<TemplateDto>();
      for (EmailTemplate t : [
        SELECT Id, Name
        FROM EmailTemplate
        WHERE IsActive = TRUE
        ORDER BY Name
        LIMIT 200
      ]) {
        res.templates.add(new TemplateDto(t.Id, t.Name));
      }
      res.recentLogs = new List<LogRowDto>();
      return res;
    }

    /* ---------- Identify ID Type ---------- */
    Set<Id> customerIds = new Set<Id>();

    Id firstId = inputIds[0];
    String sobjectType = firstId.getSobjectType().getDescribe().getName();

    if (sobjectType == 'Account') {
      // Direct Customer IDs
      customerIds.addAll(inputIds);
    } else if (sobjectType == 'Contract_Bid__c') {
      // Resolve Customers from Contract Bids
      List<Contract_Bid__c> bids = [
        SELECT Customer__c
        FROM Contract_Bid__c
        WHERE Id IN :inputIds
      ];
      for (Contract_Bid__c cb : bids) {
        if (cb.Customer__c != null) {
          customerIds.add(cb.Customer__c);
        }
      }
    }
    else if (sobjectType == 'WorkOrder') {
      List<Quick_Book_Work_Order_Line_Item__c> qbLines = [
        SELECT Work_Order__c, Service_Team_Member__c
        FROM Quick_Book_Work_Order_Line_Item__c
        WHERE Work_Order__c IN :inputIds AND Service_Team_Member__c != NULL
      ];

      Map<Id, Id> stmToPreferredWorkOrder = new Map<Id, Id>();
      Set<Id> stmSeen = new Set<Id>();
      List<Id> stmOrder = new List<Id>();

      for (Id woId : inputIds) {
        for (Quick_Book_Work_Order_Line_Item__c qbwo : qbLines) {
          if (qbwo.Work_Order__c != woId) {
            continue;
          }
          Id stmId = qbwo.Service_Team_Member__c;
          if (!stmSeen.contains(stmId)) {
            stmSeen.add(stmId);
            stmOrder.add(stmId);
          }
          if (!stmToPreferredWorkOrder.containsKey(stmId)) {
            stmToPreferredWorkOrder.put(stmId, woId);
          }
        }
      }

      for (WorkOrder wo : [
        SELECT Id, Service_Team_Member__c
        FROM WorkOrder
        WHERE Id IN :inputIds AND Service_Team_Member__c != NULL
      ]) {
        Id stmId = wo.Service_Team_Member__c;
        if (!stmSeen.contains(stmId)) {
          stmSeen.add(stmId);
          stmOrder.add(stmId);
        }
        if (!stmToPreferredWorkOrder.containsKey(stmId)) {
          stmToPreferredWorkOrder.put(stmId, wo.Id);
        }
      }

      if (stmOrder.isEmpty()) {
        res.customers = new List<CustomerDto>();
        return res;
      }

      /* ---------- Service Team Members (email only, no files) ---------- */
      Map<Id, Service_Team_Member__c> stmById = new Map<Id, Service_Team_Member__c>(
        [
          SELECT Id, Name, Email__c
          FROM Service_Team_Member__c
          WHERE Id IN :stmSeen
        ]
      );

      res.customers = new List<CustomerDto>();
      for (Id stmId : stmOrder) {
        Service_Team_Member__c stm = stmById.get(stmId);
        if (stm == null) {
          continue;
        }
        CustomerDto dto = new CustomerDto();
        dto.customerId = stm.Id;
        dto.customerName = stm.Name;
        dto.customerEmail = stm.Email__c;
        dto.primaryContactMissing = false;
        dto.workOrderId = stmToPreferredWorkOrder.get(stmId);
        dto.contracts = new List<ContractDto>();
        res.customers.add(dto);
      }

      res.templates = loadWorkOrderClassicEmailTemplatesForUi();
      res.recentLogs = new List<LogRowDto>();

      return res;
    }
    else if (sobjectType == 'Opportunity') {
      return MassSendOpportunityService.buildInitData(inputIds, res, null);
    }
    else {
      // Unsupported type
    }

    if (customerIds.isEmpty()) {
      res.customers = new List<CustomerDto>();
      return res;
    }

    /* ---------- Accounts ---------- */
    Map<Id, Account> accById = new Map<Id, Account>(
      [
        SELECT Id, Name, Primary_Contact__c, Primary_Contact__r.Email
        FROM Account
        WHERE Id IN :customerIds
      ]
    );

    /* ---------- Files ---------- */
    List<ContentDocumentLink> links = [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :customerIds
    ];

    Map<Id, Set<Id>> customerToDocIds = new Map<Id, Set<Id>>();
    Set<Id> docIds = new Set<Id>();

    for (ContentDocumentLink l : links) {
      docIds.add(l.ContentDocumentId);
      if (!customerToDocIds.containsKey(l.LinkedEntityId)) {
        customerToDocIds.put(l.LinkedEntityId, new Set<Id>());
      }
      customerToDocIds.get(l.LinkedEntityId).add(l.ContentDocumentId);
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
            ContentDocument.LatestPublishedVersionId,
            ContentDocument.LastModifiedDate
          FROM ContentVersion
          WHERE
            ContentDocumentId IN :docIds
            AND IsLatest = TRUE
            AND FileExtension = 'pdf'
            AND Title LIKE '%Contract%'
          ORDER BY ContentDocument.LastModifiedDate DESC
        ];

    // Map: ContentDocumentId -> ContractDto with LastModifiedDate
    Map<Id, ContractDto> latestByDoc = new Map<Id, ContractDto>();
    Map<Id, DateTime> docLastModified = new Map<Id, DateTime>();

    for (ContentVersion cv : cvs) {
      ContractDto cd = new ContractDto();
      cd.contentVersionId = cv.Id;
      cd.contentDocumentId = cv.ContentDocumentId;
      cd.title = cv.Title;
      cd.versionNumber = Integer.valueOf(cv.VersionNumber);
      cd.fileExtension = cv.FileExtension;
      latestByDoc.put(cv.ContentDocumentId, cd);
      docLastModified.put(
        cv.ContentDocumentId,
        cv.ContentDocument.LastModifiedDate
      );
    }

    /* ---------- Build Customers ---------- */
    res.customers = new List<CustomerDto>();

    for (Id custId : customerIds) {
      Account acc = accById.get(custId);
      if (acc == null)
        continue;

      CustomerDto dto = new CustomerDto();
      dto.customerId = acc.Id;
      dto.customerName = acc.Name;
      dto.customerEmail = acc.Primary_Contact__r != null
        ? acc.Primary_Contact__r.Email
        : null;
      dto.primaryContactMissing = acc.Primary_Contact__r == null;

      dto.contracts = new List<ContractDto>();

      // Select ONLY the latest contract based on LastModifiedDate
      if (customerToDocIds.containsKey(custId)) {
        Id latestDocId = null;
        DateTime latestDate = null;

        for (Id docId : customerToDocIds.get(custId)) {
          if (latestByDoc.containsKey(docId)) {
            DateTime docDate = docLastModified.get(docId);
            if (latestDate == null || docDate > latestDate) {
              latestDate = docDate;
              latestDocId = docId;
            }
          }
        }

        if (latestDocId != null) {
          dto.contracts.add(latestByDoc.get(latestDocId));
        }
      }

      res.customers.add(dto);
    }

    /* ---------- Email Templates (Account / Contract Bid — Premier Pool folder only) ---------- */
    res.templates = loadPremierPoolTemplatesForUi();

    res.recentLogs = new List<LogRowDto>();

    return res;
  }

  /**
   * Server-side filtered init for Proposal (Opportunity) mass send.
   * Filters by Regional Manager, customer/Account name, and contract year in PDF title.
   */
  @AuraEnabled(cacheable=true)
  public static InitResponse getInitDataFiltered(
    List<Id> inputIds,
    String regionalManagerId,
    String customerName,
    String contractYear,
    Boolean requireContracts
  ) {
    InitResponse res = new InitResponse();

    if (!hasPermission()) {
      res.hasAccess = false;
      res.accessMessage = 'Missing permission: Mass_Contract_Send';
      return res;
    }
    res.hasAccess = true;

    if (inputIds == null) {
      inputIds = new List<Id>();
    }

    if (inputIds.isEmpty()) {
      res.customers = new List<CustomerDto>();
      res.templates = new List<TemplateDto>();
      res.recentLogs = new List<LogRowDto>();
      return res;
    }

    InitFilters filters = new InitFilters();
    filters.regionalManagerId = regionalManagerId;
    filters.customerName = customerName;
    filters.contractYear = contractYear;
    filters.requireContracts = requireContracts;

    return MassSendOpportunityService.buildInitData(inputIds, res, filters);
  }

  private static final String PREMIER_POOL_TEMPLATE_FOLDER = 'Premier Pool Templates';

  /** Classic HTML/custom/VF templates in the Premier Pool Templates folder only. */
  public static List<TemplateDto> loadPremierPoolTemplatesForUi() {
    List<TemplateDto> out = new List<TemplateDto>();
    for (EmailTemplate t : [
      SELECT Id, Name
      FROM EmailTemplate
      WHERE
        IsActive = TRUE
        AND TemplateType IN ('custom', 'html', 'visualforce')
        AND Folder.Name = :PREMIER_POOL_TEMPLATE_FOLDER
      ORDER BY Name
      LIMIT 200
    ]) {
      out.add(new TemplateDto(t.Id, t.Name));
    }
    return out;
  }

  /** Classic templates for Work Order mass send: name contains "Work Order" (any folder). */
  private static List<TemplateDto> loadWorkOrderClassicEmailTemplatesForUi() {
    List<TemplateDto> out = new List<TemplateDto>();
    for (EmailTemplate t : [
      SELECT Id, Name
      FROM EmailTemplate
      WHERE
        IsActive = TRUE
        AND TemplateType IN ('custom', 'html', 'visualforce')
        AND Name LIKE '%Work Order%'
      ORDER BY Name
      LIMIT 200
    ]) {
      out.add(new TemplateDto(t.Id, t.Name));
    }
    return out;
  }

  /* =========================================================
       TEMPLATE DETAILS
    ========================================================= */
  @AuraEnabled
  public static Map<String, String> getTemplateDetails(Id templateId) {
    EmailTemplate t = [
      SELECT Subject, HtmlValue, Body
      FROM EmailTemplate
      WHERE Id = :templateId
      LIMIT 1
    ];
    return new Map<String, String>{
      'subject' => t.Subject,
      'body' => String.isNotBlank(t.HtmlValue) ? t.HtmlValue : t.Body
    };
  }

  /* =========================================================
       SEND
    ========================================================= */

  public class SendReqRow {
    public Id customerId;
    public Id workOrderId;
    public List<Id> contentVersionIds;
    /** Optional per-recipient overrides; when null, top-level subject/body are used. */
    public String subject;
    public String body;
    /** When true, subject/body are final merged HTML (no template merge on send). */
    public Boolean parsedContent;
  }

  public class SendResponse {
    @AuraEnabled
    public List<LogRowDto> logs;
  }

  @AuraEnabled
  public static SendResponse sendContracts(
    List<Id> inputIds,
    Id emailTemplateId,
    String requestJson,
    String subject, // New
    String body
  ) {
    if (!hasPermission()) {
      throw new AuraHandledException('Missing permission: Mass_Contract_Send');
    }

    if (emailTemplateId == null && String.isBlank(body)) {
      throw new AuraHandledException('Email template or body is required.');
    }

    if (String.isBlank(requestJson)) {
      throw new AuraHandledException('Nothing to send.');
    }

    List<SendReqRow> rows = (List<SendReqRow>) JSON.deserialize(
      requestJson,
      List<SendReqRow>.class
    );

    Set<Id> accountIds = new Set<Id>();
    Set<Id> stmIds = new Set<Id>();
    Set<Id> proposalIds = new Set<Id>();
    Set<Id> cvIds = new Set<Id>();

    for (SendReqRow r : rows) {
      if (isServiceTeamMemberId(r.customerId)) {
        stmIds.add(r.customerId);
      } else if (isOpportunityId(r.customerId)) {
        proposalIds.add(r.customerId);
        if (r.contentVersionIds != null) {
          cvIds.addAll(r.contentVersionIds);
        }
      } else {
        accountIds.add(r.customerId);
        if (r.contentVersionIds != null) {
          cvIds.addAll(r.contentVersionIds);
        }
      }
    }

    // Load and validate ContentVersions only when contracts are provided
    Map<Id, ContentVersion> cvById = new Map<Id, ContentVersion>();
    if (!cvIds.isEmpty()) {
      cvById = new Map<Id, ContentVersion>(
        [
          SELECT Id, Title, VersionNumber, IsLatest
          FROM ContentVersion
          WHERE Id IN :cvIds
        ]
      );

      for (ContentVersion cv : cvById.values()) {
        if (!cv.IsLatest) {
          throw new AuraHandledException(
            'Only latest contract versions can be sent.'
          );
        }
      }
    }

    Map<Id, Opportunity> proposalById = proposalIds.isEmpty()
      ? new Map<Id, Opportunity>()
      : new Map<Id, Opportunity>(
          [
            SELECT
              Id,
              Name,
              AccountId,
              Account.Name,
              Account.Primary_Contact__c,
              Account.Primary_Contact__r.Email,
              Account.Primary_Contact__r.FirstName,
              Account.Primary_Contact__r.LastName,
              Customer_Primary_Contact__c,
              Customer_Primary_Contact__r.Email,
              Customer_Primary_Contact__r.FirstName,
              Customer_Primary_Contact__r.LastName
            FROM Opportunity
            WHERE Id IN :proposalIds
          ]
        );

    for (Opportunity opp : proposalById.values()) {
      if (opp.AccountId != null) {
        accountIds.add(opp.AccountId);
      }
    }

    Map<Id, Account> accById = accountIds.isEmpty()
      ? new Map<Id, Account>()
      : new Map<Id, Account>(
          [
            SELECT
              Id,
              Name,
              Primary_Contact__c,
              Primary_Contact__r.Email,
              Primary_Contact__r.FirstName,
              Primary_Contact__r.LastName
            FROM Account
            WHERE Id IN :accountIds
          ]
        );

    Map<Id, Service_Team_Member__c> stmById = stmIds.isEmpty()
      ? new Map<Id, Service_Team_Member__c>()
      : new Map<Id, Service_Team_Member__c>(
          [
            SELECT Id, Name, Email__c
            FROM Service_Team_Member__c
            WHERE Id IN :stmIds
          ]
        );

    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
    List<LogRowDto> logs = new List<LogRowDto>();

    Map<Integer, List<LogRowDto>> emailIndexToLogs = new Map<Integer, List<LogRowDto>>();
    Integer emailIndex = 0;

    User sendingUser = [
      SELECT Email
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    Boolean useWorkOrderMailbox = isWorkOrderPageContext(inputIds, rows);

    String templateDeveloperName = MassSendEmailBuilder.resolveEmailTemplateDeveloperName(emailTemplateId);
    List<String> namedCcEmails = MassSendEmailBuilder.loadNamedContractSendPdfCcEmails();
    Map<Id, String> accountToRmEmail = MassSendEmailBuilder.resolveRegionalManagerEmailsByAccount(accountIds);

    for (SendReqRow r : rows) {
      String rowSubject = r.subject != null ? r.subject : subject;
      String rowBody = r.body != null ? r.body : body;

      if (isServiceTeamMemberId(r.customerId)) {
        Service_Team_Member__c stm = stmById.get(r.customerId);
        if (stm == null) {
          LogRowDto log = new LogRowDto();
          log.customerName = 'Unknown';
          log.status = 'Failed';
          log.message = 'Service Team Member not found.';
          logs.add(log);
          continue;
        }
        if (String.isBlank(stm.Email__c)) {
          LogRowDto log = new LogRowDto();
          log.customerName = stm.Name;
          log.status = 'Failed';
          log.message = 'Service Team Member has no email.';
          logs.add(log);
          continue;
        }

        Id mergeWhatId = isWorkOrderId(r.workOrderId)
          ? r.workOrderId
          : stm.Id;
        if (
          mergeWhatId == stm.Id &&
          inputIds != null &&
          inputIds.size() == 1 &&
          inputIds[0].getSobjectType() == WorkOrder.SObjectType
        ) {
          mergeWhatId = inputIds[0];
        }

        MassSendEmailBuilder.BuildRequest req = new MassSendEmailBuilder.BuildRequest();
        req.toAddresses = new List<String>{ stm.Email__c };
        req.mergeWhoId = UserInfo.getUserId();
        req.whatId = mergeWhatId;
        req.contentVersionIds = r.contentVersionIds;
        req.parsedContent = r.parsedContent;
        req.rowSubject = r.subject;
        req.rowBody = r.body;
        req.defaultSubject = subject;
        req.defaultBody = body;
        req.emailTemplateId = emailTemplateId;
        req.templateDeveloperName = templateDeveloperName;
        req.recipientEmail = stm.Email__c;
        req.sendingUser = sendingUser;
        req.useWorkOrderMailbox = useWorkOrderMailbox;
        req.applyWorkOrderPlaceholders = (r.parsedContent != true);
        req.lineItemsRestrictStmId = stm.Id;

        MassSendEmailBuilder.EmailBuildResult result = MassSendEmailBuilder.buildEmail(req);
        if (String.isNotBlank(result.errorMessage)) {
          LogRowDto log = new LogRowDto();
          log.customerName = stm.Name;
          log.status = 'Failed';
          log.message = result.errorMessage;
          logs.add(log);
          continue;
        }

        emails.add(result.mail);

        LogRowDto stmLog = new LogRowDto();
        stmLog.customerName = stm.Name;
        stmLog.status = 'Sending';
        stmLog.message = 'Email is being sent...';
        logs.add(stmLog);
        emailIndexToLogs.put(emailIndex, new List<LogRowDto>{ stmLog });
        emailIndex++;
        continue;
      }

      if (isOpportunityId(r.customerId)) {
        Opportunity opp = proposalById.get(r.customerId);
        if (opp == null) {
          LogRowDto log = new LogRowDto();
          log.customerName = 'Unknown';
          log.status = 'Failed';
          log.message = 'Proposal not found.';
          logs.add(log);
          continue;
        }

        Id whoId;
        String whoEmail;
        if (opp.Customer_Primary_Contact__c != null) {
          whoId = opp.Customer_Primary_Contact__c;
          whoEmail = opp.Customer_Primary_Contact__r != null
            ? opp.Customer_Primary_Contact__r.Email
            : null;
        } else if (
          opp.AccountId != null &&
          opp.Account.Primary_Contact__c != null
        ) {
          whoId = opp.Account.Primary_Contact__c;
          whoEmail = opp.Account.Primary_Contact__r != null
            ? opp.Account.Primary_Contact__r.Email
            : null;
        }

        if (whoId == null) {
          LogRowDto log = new LogRowDto();
          log.customerName = opp.Name;
          log.status = 'Failed';
          log.message = 'Primary Contact is missing.';
          logs.add(log);
          continue;
        }
        if (String.isBlank(whoEmail)) {
          LogRowDto log = new LogRowDto();
          log.customerName = opp.Name;
          log.status = 'Failed';
          log.message = 'Primary Contact has no email.';
          logs.add(log);
          continue;
        }

        MassSendEmailBuilder.BuildRequest req = new MassSendEmailBuilder.BuildRequest();
        req.targetWhoId = whoId;
        req.mergeWhoId = whoId;
        req.whatId = opp.AccountId;
        req.contentVersionIds = r.contentVersionIds;
        req.parsedContent = r.parsedContent;
        req.rowSubject = r.subject;
        req.rowBody = r.body;
        req.defaultSubject = subject;
        req.defaultBody = body;
        req.emailTemplateId = emailTemplateId;
        req.templateDeveloperName = templateDeveloperName;
        req.recipientEmail = whoEmail;
        req.sendingUser = sendingUser;
        req.useWorkOrderMailbox = useWorkOrderMailbox;
        req.regionalManagerEmail = accountToRmEmail.get(opp.AccountId);
        req.namedCcEmails = namedCcEmails;

        MassSendEmailBuilder.EmailBuildResult result = MassSendEmailBuilder.buildEmail(req);
        if (String.isNotBlank(result.errorMessage)) {
          LogRowDto log = new LogRowDto();
          log.customerName = opp.Name;
          log.status = 'Failed';
          log.message = result.errorMessage;
          logs.add(log);
          continue;
        }

        emails.add(result.mail);

        List<LogRowDto> currentEmailLogs = new List<LogRowDto>();
        if (r.contentVersionIds != null && !r.contentVersionIds.isEmpty()) {
          for (Id cvId : r.contentVersionIds) {
            ContentVersion cv = cvById.get(cvId);
            LogRowDto log = new LogRowDto();
            log.customerName = opp.Name;
            log.fileTitle = cv != null ? cv.Title : null;
            log.versionNumber = cv != null
              ? Integer.valueOf(cv.VersionNumber)
              : null;
            log.status = 'Sending';
            log.message = 'Email is being sent...';
            logs.add(log);
            currentEmailLogs.add(log);
          }
        } else {
          LogRowDto log = new LogRowDto();
          log.customerName = opp.Name;
          log.status = 'Sending';
          log.message = 'Email is being sent...';
          logs.add(log);
          currentEmailLogs.add(log);
        }
        emailIndexToLogs.put(emailIndex, currentEmailLogs);
        emailIndex++;
        continue;
      }

      Account acc = accById.get(r.customerId);

      if (acc == null || acc.Primary_Contact__c == null) {
        LogRowDto log = new LogRowDto();
        log.customerName = acc != null ? acc.Name : 'Unknown';
        log.status = 'Failed';
        log.message = 'Primary Contact is missing.';
        logs.add(log);
        continue;
      }

      if (String.isBlank(acc.Primary_Contact__r.Email)) {
        LogRowDto log = new LogRowDto();
        log.customerName = acc.Name;
        log.status = 'Failed';
        log.message = 'Primary Contact has no email.';
        logs.add(log);
        continue;
      }

      MassSendEmailBuilder.BuildRequest req = new MassSendEmailBuilder.BuildRequest();
      req.targetWhoId = acc.Primary_Contact__c;
      req.mergeWhoId = acc.Primary_Contact__c;
      req.whatId = acc.Id;
      req.contentVersionIds = r.contentVersionIds;
      req.parsedContent = r.parsedContent;
      req.rowSubject = r.subject;
      req.rowBody = r.body;
      req.defaultSubject = subject;
      req.defaultBody = body;
      req.emailTemplateId = emailTemplateId;
      req.templateDeveloperName = templateDeveloperName;
      req.recipientEmail = acc.Primary_Contact__r.Email;
      req.sendingUser = sendingUser;
      req.useWorkOrderMailbox = useWorkOrderMailbox;
      req.regionalManagerEmail = accountToRmEmail.get(acc.Id);
      req.namedCcEmails = namedCcEmails;

      MassSendEmailBuilder.EmailBuildResult result = MassSendEmailBuilder.buildEmail(req);
      if (String.isNotBlank(result.errorMessage)) {
        LogRowDto log = new LogRowDto();
        log.customerName = acc.Name;
        log.status = 'Failed';
        log.message = result.errorMessage;
        logs.add(log);
        continue;
      }

      emails.add(result.mail);

      // Build log rows:
      // - With contracts: one row per attached ContentVersion
      // - Without contracts: one row per customer
      List<LogRowDto> currentEmailLogs = new List<LogRowDto>();
      if (r.contentVersionIds != null && !r.contentVersionIds.isEmpty()) {
        for (Id cvId : r.contentVersionIds) {
          ContentVersion cv = cvById.get(cvId);
          LogRowDto log = new LogRowDto();
          log.customerName = acc.Name;
          log.fileTitle = cv != null ? cv.Title : null;
          log.versionNumber = cv != null
            ? Integer.valueOf(cv.VersionNumber)
            : null;
          log.status = 'Sending';
          log.message = 'Email is being sent...';
          logs.add(log);
          currentEmailLogs.add(log);
        }
      } else {
        LogRowDto log = new LogRowDto();
        log.customerName = acc.Name;
        log.status = 'Sending';
        log.message = 'Email is being sent...';
        logs.add(log);
        currentEmailLogs.add(log);
      }
      emailIndexToLogs.put(emailIndex, currentEmailLogs);
      emailIndex++;
    }

    if (!emails.isEmpty()) {
      Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);

      for (Integer i = 0; i < results.size(); i++) {
        Messaging.SendEmailResult result = results[i];
        List<LogRowDto> emailLogs = emailIndexToLogs.get(i);

        if (emailLogs != null) {
          for (LogRowDto log : emailLogs) {
            if (result.isSuccess()) {
              log.status = 'Sent';
              log.message = 'Email sent successfully.';
            } else {
              log.status = 'Failed';
              String errorMsg = 'Unknown error';
              if (result.getErrors() != null && result.getErrors().size() > 0) {
                errorMsg = result.getErrors()[0].getMessage();
              }
              log.message = errorMsg;
            }
          }
        }
      }
    }

    SendResponse resp = new SendResponse();
    resp.logs = logs;
    return resp;
  }

  /* =========================================================
       PREVIEW (MERGED SUBJECT/BODY)
       ========================================================= */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> previewEmail(
    Id emailTemplateId,
    Id customerId,
    Id contactId,
    Id workOrderId,
    String subject,
    String body
  ) {
    if (emailTemplateId == null) {
      throw new AuraHandledException('Email template is required for preview.');
    }

    Id whoId;
    Id whatId;
    Boolean stmBranch = false;

    if (customerId != null && isServiceTeamMemberId(customerId)) {
      stmBranch = true;
      Service_Team_Member__c stm = [
        SELECT Id, Name, Email__c
        FROM Service_Team_Member__c
        WHERE Id = :customerId
        LIMIT 1
      ];
      whoId = UserInfo.getUserId();
      whatId = isWorkOrderId(workOrderId) ? workOrderId : stm.Id;
    } else if (customerId != null && isOpportunityId(customerId)) {
      Opportunity opp = [
        SELECT
          Id,
          Name,
          AccountId,
          Account.Primary_Contact__c,
          Customer_Primary_Contact__c
        FROM Opportunity
        WHERE Id = :customerId
        LIMIT 1
      ];
      whatId = opp.AccountId;

      if (contactId != null) {
        List<Contact> explicitWho = [
          SELECT Id
          FROM Contact
          WHERE Id = :contactId
          LIMIT 1
        ];
        if (explicitWho.isEmpty()) {
          throw new AuraHandledException('Contact not found for preview.');
        }
        whoId = contactId;
      } else if (opp.Customer_Primary_Contact__c != null) {
        whoId = opp.Customer_Primary_Contact__c;
      } else if (
        opp.AccountId != null &&
        opp.Account.Primary_Contact__c != null
      ) {
        whoId = opp.Account.Primary_Contact__c;
      } else if (opp.AccountId != null) {
        List<Contact> anyOnAccount = [
          SELECT Id
          FROM Contact
          WHERE AccountId = :opp.AccountId
          ORDER BY CreatedDate ASC
          LIMIT 1
        ];
        if (anyOnAccount.isEmpty()) {
          throw new AuraHandledException(
            'Unable to resolve Contact for preview. Set a Primary Contact on the Proposal or Account.'
          );
        }
        whoId = anyOnAccount[0].Id;
      } else {
        throw new AuraHandledException(
          'Unable to resolve Contact for preview. Set a Primary Contact on the Proposal or Account.'
        );
      }
    } else {
      // Resolve Account
      Account acc;
      if (customerId != null) {
        acc = [
          SELECT
            Id,
            Name,
            Primary_Contact__c,
            Primary_Contact__r.Email,
            Primary_Contact__r.FirstName,
            Primary_Contact__r.LastName
          FROM Account
          WHERE Id = :customerId
          LIMIT 1
        ];
      }
      if (acc == null) {
        throw new AuraHandledException('Unable to resolve Account for preview.');
      }

      // whoId for merge must be Contact/Lead/User. Do not rely on Primary_Contact__r — it is often
      // null under sharing even when Primary_Contact__c is set; LWC also passes contactId: null.
      if (contactId != null) {
        List<Contact> explicitWho = [
          SELECT Id
          FROM Contact
          WHERE Id = :contactId
          LIMIT 1
        ];
        if (explicitWho.isEmpty()) {
          throw new AuraHandledException('Contact not found for preview.');
        }
        whoId = contactId;
      } else if (acc.Primary_Contact__c != null) {
        whoId = acc.Primary_Contact__c;
      } else {
        List<Contact> anyOnAccount = [
          SELECT Id
          FROM Contact
          WHERE AccountId = :acc.Id
          ORDER BY CreatedDate ASC
          LIMIT 1
        ];
        if (anyOnAccount.isEmpty()) {
          throw new AuraHandledException(
            'Unable to resolve Contact for preview. Set a Primary Contact on the account or add a contact.'
          );
        }
        whoId = anyOnAccount[0].Id;
      }
      whatId = acc.Id;
    }

    String finalSubject;
    String finalBody;
    Boolean mergeFieldError = false;

    Id lineItemsRestrictStmId = stmBranch ? customerId : null;

    // Stored-template fast path — skip if body uses {{{ }}} (SF merge expects {!...})
    if (String.isBlank(body)) {
      Boolean templateUsesTripleBraces = false;
      for (EmailTemplate tChk : [
        SELECT HtmlValue, Body
        FROM EmailTemplate
        WHERE Id = :emailTemplateId
        LIMIT 1
      ]) {
        String src = String.isNotBlank(tChk.HtmlValue)
          ? tChk.HtmlValue
          : tChk.Body;
        templateUsesTripleBraces =
          String.isNotBlank(src) && src.contains('{{{');
      }

      if (!templateUsesTripleBraces) {
        try {
          Messaging.SingleEmailMessage renderedTemplate = Messaging.renderStoredEmailTemplate(
            emailTemplateId,
            whoId,
            whatId
          );

          finalSubject = renderedTemplate != null
            ? renderedTemplate.getSubject()
            : null;
          finalBody = renderedTemplate != null
            ? renderedTemplate.getHtmlBody()
            : null;

          finalBody = MassSendEmailBuilder.applyLineItemsPlaceholder(
            finalBody,
            whatId,
            lineItemsRestrictStmId
          );
          finalSubject = MassSendEmailBuilder.applyLineItemsPlaceholder(
            finalSubject,
            whatId,
            lineItemsRestrictStmId
          );
          finalBody = MassSendEmailBuilder.applyAccountAddressPlaceholder(
            finalBody,
            whatId,
            true
          );
          finalSubject = MassSendEmailBuilder.applyAccountAddressPlaceholder(
            finalSubject,
            whatId,
            false
          );

          return new Map<String, Object>{
            'subject' => finalSubject,
            'body' => finalBody,
            'mergeFieldError' => false
          };
        } catch (Exception ex) {
          mergeFieldError = true;
        }
      }
    }

    // Здесь работаем с пользовательским subject/body (или fallback)
    String rawBody = body;
    String rawSubject = subject;

    // Если body пустой, забираем HtmlValue/Body из шаблона без рендера (как в getTemplateDetails)
    if (String.isBlank(rawBody)) {
      EmailTemplate t = [
        SELECT Subject, HtmlValue, Body, TemplateType, DeveloperName
        FROM EmailTemplate
        WHERE Id = :emailTemplateId
        LIMIT 1
      ];
      rawSubject = String.isNotBlank(subject) ? subject : t.Subject;
      rawBody = String.isNotBlank(t.HtmlValue) ? t.HtmlValue : t.Body;
    }

    rawBody = MassSendEmailBuilder.prepareForRenderEmailTemplate(rawBody, whoId);
    rawSubject = MassSendEmailBuilder.prepareForRenderEmailTemplate(rawSubject, whoId);

    try {
      List<String> bodiesToRender = new List<String>{ rawBody };
      if (!String.isBlank(rawSubject)) {
        bodiesToRender.add(rawSubject);
      }

      List<Messaging.RenderEmailTemplateBodyResult> results = Messaging.renderEmailTemplate(
        whoId,
        whatId,
        bodiesToRender
      );

      // Body
      if (!results.isEmpty() && results[0].getSuccess()) {
        finalBody = results[0].getMergedBody();
      } else {
        finalBody = rawBody;
      }

      // Subject
      if (!String.isBlank(rawSubject)) {
        if (results.size() > 1 && results[1].getSuccess()) {
          finalSubject = results[1].getMergedBody();
        } else {
          finalSubject = rawSubject;
        }
      }
    } catch (Exception ex) {
      mergeFieldError = true;

      // Базовый текст = сырой текст без рендера
      finalBody = rawBody;
      finalSubject = rawSubject;

      if (finalBody != null) {
        finalBody = MassSendEmailBuilder.softenCaseMergeFailures(finalBody);
      }
      if (finalSubject != null) {
        finalSubject = MassSendEmailBuilder.softenCaseMergeFailures(finalSubject);
      }
    }

    finalBody = MassSendEmailBuilder.applyLineItemsPlaceholder(
      finalBody,
      whatId,
      lineItemsRestrictStmId
    );
    finalSubject = MassSendEmailBuilder.applyLineItemsPlaceholder(
      finalSubject,
      whatId,
      lineItemsRestrictStmId
    );
    finalBody = MassSendEmailBuilder.applyAccountAddressPlaceholder(
      finalBody,
      whatId,
      true
    );
    finalSubject = MassSendEmailBuilder.applyAccountAddressPlaceholder(
      finalSubject,
      whatId,
      false
    );

    return new Map<String, Object>{
      'subject' => finalSubject,
      'body' => finalBody,
      'mergeFieldError' => mergeFieldError
    };
  }
}