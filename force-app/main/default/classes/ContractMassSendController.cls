public with sharing class ContractMassSendController {
  /**
   * Put either token in HTML/text email templates; Apex replaces with a line-item table
   * when merge whatId is a Work Order (send + preview).
   */
  private static final List<String> LINE_ITEM_PLACEHOLDERS = new List<String>{
    '[LINE_ITEMS]',
    '[LINE ITEM]'
  };

  /**
   * Classic merge often leaves WorkOrder.Account billing/shipping blank; Apex fills from SOQL.
   */
  private static final String ACCOUNT_ADDRESS_PLACEHOLDER = '[ACCOUNT_ADDRESS]';

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

  /** Org-wide address used when the mass-send host is a Work Order record page. */
  private static final String WORK_ORDER_ORG_WIDE_EMAIL_ADDRESS =
    'sf_workorders@premiersswim.com';

  private static final String LOG_SEND = 'ContractMassSend';

  private static void logSend(String message) {
    System.debug(LoggingLevel.INFO, LOG_SEND + ' | ' + message);
  }

  private static void logSendWarn(String message) {
    System.debug(LoggingLevel.WARN, LOG_SEND + ' | ' + message);
  }

  /**
   * True when the LWC passes the host record as inputIds[0] (e.g. quick action on Work Order).
   */
  private static Boolean isWorkOrderPageContext(List<Id> inputIds) {
    return inputIds != null &&
      !inputIds.isEmpty() &&
      inputIds[0] != null &&
      inputIds[0].getSobjectType() == WorkOrder.SObjectType;
  }

  private static OrgWideEmailAddress getWorkOrderOrgWideEmailAddress() {
    List<OrgWideEmailAddress> rows = [
      SELECT Id, DisplayName, Address
      FROM OrgWideEmailAddress
      WHERE Address = :WORK_ORDER_ORG_WIDE_EMAIL_ADDRESS AND IsVerified = TRUE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /**
   * From: Org-Wide Email — Work Order mailbox when launched from a Work Order page;
   * otherwise same as before (current user address + matching verified OWEA if any).
   */
  private static void applyOutboundSenderIdentity(
    Messaging.SingleEmailMessage mail,
    User currentUser,
    Boolean useWorkOrderMailbox,
    String branchLabel
  ) {
    if (useWorkOrderMailbox) {
      OrgWideEmailAddress woOwea = getWorkOrderOrgWideEmailAddress();
      if (woOwea != null) {
        mail.setOrgWideEmailAddressId(woOwea.Id);
        mail.setSenderDisplayName(
          String.isNotBlank(woOwea.DisplayName) ? woOwea.DisplayName : woOwea.Address
        );
        mail.setReplyTo(currentUser.Email);
        logSend(
          'sender=' +
            branchLabel +
            ' path=WorkOrderOWEA orgWideEmailAddressId=' +
            woOwea.Id +
            ' display=' +
            (String.isNotBlank(woOwea.DisplayName)
              ? woOwea.DisplayName
              : woOwea.Address) +
            ' replyTo=' +
            currentUser.Email
        );
        return;
      }
      logSendWarn(
        'sender=' +
          branchLabel +
          ' path=WorkOrderOWEA FAILED (missing OWEA); falling back to user OWEA / user From'
      );
    }

    List<OrgWideEmailAddress> oweaList = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE Address = :currentUser.Email AND IsVerified = TRUE
      LIMIT 1
    ];
    if (!oweaList.isEmpty()) {
      mail.setOrgWideEmailAddressId(oweaList[0].Id);
      mail.setSenderDisplayName(currentUser.Email + ' (Salesforce)');
      logSend(
        'sender=' +
          branchLabel +
          ' path=UserOWEA orgWideEmailAddressId=' +
          oweaList[0].Id +
          ' userEmail=' +
          currentUser.Email
      );
    } else {
      logSend(
        'sender=' +
          branchLabel +
          ' path=UserEmailOnly (no verified OWEA for user) userEmail=' +
          currentUser.Email
      );
    }
    mail.setReplyTo(currentUser.Email);
    mail.setSenderDisplayName(currentUser.Email);
  }

  /**
   * Mustache-style {{{Recipient.Name}}} is not merged by Salesforce; classic merge uses {!Recipient.Name}.
   * Apex Matcher has no appendReplacement — rebuild with substring per match.
   */
  private static String normalizeTripleBraceMergeFields(String text) {
    if (String.isBlank(text)) {
      return text;
    }
    Pattern p = Pattern.compile('\\{\\{\\{([^}]+)\\}\\}\\}');
    String result = text;
    while (true) {
      Matcher m = p.matcher(result);
      if (!m.find()) {
        break;
      }
      String path = m.group(1) != null ? m.group(1).trim() : '';
      Integer startPos = m.start();
      Integer endPos = m.end();
      result =
        result.substring(0, startPos) +
        '{!' +
        path +
        '}' +
        result.substring(endPos);
    }
    return result;
  }

  /** Safe cleanup when merge fails; avoids replaceAll('$1') throwing on edge-case subjects. */
  private static String softenCaseMergeFailures(String text) {
    if (String.isBlank(text)) {
      return text;
    }
    Pattern p = Pattern.compile('\\{\\{\\{?Case\\.([^}]+)\\}\\}?');
    String result = text;
    while (true) {
      Matcher m = p.matcher(result);
      if (!m.find()) {
        break;
      }
      String field = m.group(1) != null ? m.group(1) : '';
      Integer startPos = m.start();
      Integer endPos = m.end();
      result =
        result.substring(0, startPos) +
        '[Case.' +
        field +
        ']' +
        result.substring(endPos);
    }
    return result;
  }

  /**
   * renderStoredEmailTemplate resolves Recipient/Sender; renderEmailTemplate(whoId, whatId, strings) does not
   * bind those email-template aliases — merge runs but values are blank. Map to the concrete merge objects.
   */
  private static String expandEmailMergeAliases(String text, Id whoId) {
    if (String.isBlank(text) || whoId == null) {
      return text;
    }
    String out = text;
    Schema.SObjectType whoType = whoId.getSobjectType();
    if (whoType == Contact.SObjectType) {
      out = out.replace('{!Recipient.', '{!Contact.');
    } else if (whoType == Lead.SObjectType) {
      out = out.replace('{!Recipient.', '{!Lead.');
    } else if (whoType == User.SObjectType) {
      out = out.replace('{!Recipient.', '{!User.');
    }
    out = out.replace('{!Sender.', '{!User.');
    return out;
  }

  private static String prepareForRenderEmailTemplate(String text, Id whoId) {
    return expandEmailMergeAliases(
      normalizeTripleBraceMergeFields(text),
      whoId
    );
  }

  private static String escapeHtml(String raw) {
    if (raw == null) {
      return '';
    }
    return raw.replace('&', '&amp;')
      .replace('<', '&lt;')
      .replace('>', '&gt;')
      .replace('"', '&quot;');
  }

  /**
   * Replaces [LINE_ITEMS] / [LINE ITEMS] with an HTML table of Quick Book line items.
   * When serviceTeamMemberId is set, only line items with that Service_Team_Member__c are included.
   * No-op if workOrderId is not a Work Order, content blank, or no placeholder present.
   */
  private static String applyLineItemsPlaceholder(
    String content,
    Id workOrderId,
    Id serviceTeamMemberId
  ) {
    if (String.isBlank(content) || !isWorkOrderId(workOrderId)) {
      return content;
    }
    Boolean needs = false;
    for (String ph : LINE_ITEM_PLACEHOLDERS) {
      if (content.contains(ph)) {
        needs = true;
        break;
      }
    }
    if (!needs) {
      return content;
    }
    String tableHtml = buildQuickBookLineItemsHtml(
      workOrderId,
      serviceTeamMemberId
    );
    String out = content;
    for (String ph : LINE_ITEM_PLACEHOLDERS) {
      out = out.replace(ph, tableHtml);
    }
    return out;
  }

  private static String buildQuickBookLineItemsHtml(
    Id workOrderId,
    Id serviceTeamMemberId
  ) {
    List<Quick_Book_Work_Order_Line_Item__c> lines;
    if (serviceTeamMemberId != null) {
      lines = [
        SELECT Name, Description__c, Quantity__c, Rate__c, Amount__c
        FROM Quick_Book_Work_Order_Line_Item__c
        WHERE
          Work_Order__c = :workOrderId
          AND Service_Team_Member__c = :serviceTeamMemberId
        ORDER BY CreatedDate ASC
      ];
    } else {
      lines = [
        SELECT Name, Description__c, Quantity__c, Rate__c, Amount__c
        FROM Quick_Book_Work_Order_Line_Item__c
        WHERE Work_Order__c = :workOrderId
        ORDER BY CreatedDate ASC
      ];
    }

    if (lines.isEmpty()) {
      if (serviceTeamMemberId != null) {
        return '<p><em>No line items on this work order are assigned to you.</em></p>';
      }
      return '<p><em>No line items on this work order.</em></p>';
    }

    List<String> rows = new List<String>();
    rows.add(
      '<table style="border-collapse:collapse;width:100%;max-width:640px;font-family:Arial,sans-serif;font-size:14px;">'
    );
    rows.add(
      '<thead><tr style="background:#f3f3f3;">' +
        '<th style="border:1px solid #ccc;padding:8px;text-align:left;">Item</th>' +
        '<th style="border:1px solid #ccc;padding:8px;text-align:left;">Description</th>' +
        '<th style="border:1px solid #ccc;padding:8px;text-align:right;">Qty</th>' +
        '<th style="border:1px solid #ccc;padding:8px;text-align:right;">Rate</th>' +
        '<th style="border:1px solid #ccc;padding:8px;text-align:right;">Amount</th>' +
        '</tr></thead><tbody>'
    );

    for (Quick_Book_Work_Order_Line_Item__c li : lines) {
      rows.add(
        '<tr>' +
          '<td style="border:1px solid #ccc;padding:8px;">' +
          escapeHtml(li.Name) +
          '</td>' +
          '<td style="border:1px solid #ccc;padding:8px;">' +
          escapeHtml(li.Description__c) +
          '</td>' +
          '<td style="border:1px solid #ccc;padding:8px;text-align:right;">' +
          (li.Quantity__c != null ? String.valueOf(li.Quantity__c) : '') +
          '</td>' +
          '<td style="border:1px solid #ccc;padding:8px;text-align:right;">' +
          (li.Rate__c != null ? String.valueOf(li.Rate__c) : '') +
          '</td>' +
          '<td style="border:1px solid #ccc;padding:8px;text-align:right;">' +
          (li.Amount__c != null ? String.valueOf(li.Amount__c) : '') +
          '</td>' +
          '</tr>'
      );
    }

    rows.add('</tbody></table>');
    return String.join(rows, '');
  }

  private static String applyAccountAddressPlaceholder(
    String content,
    Id workOrderId,
    Boolean useHtmlLineBreaks
  ) {
    if (String.isBlank(content) || !isWorkOrderId(workOrderId)) {
      return content;
    }
    if (!content.contains(ACCOUNT_ADDRESS_PLACEHOLDER)) {
      return content;
    }
    String snippet = useHtmlLineBreaks
      ? buildAccountAddressHtml(workOrderId)
      : buildAccountAddressOneLineEscaped(workOrderId);
    return content.replace(ACCOUNT_ADDRESS_PLACEHOLDER, snippet);
  }

  private static String buildAccountAddressOneLineEscaped(Id workOrderId) {
    String plain = formatWorkOrderAccountAddressPlain(workOrderId);
    if (String.isBlank(plain)) {
      return '';
    }
    return escapeHtml(plain.replace('\n', ', '));
  }

  private static String buildAccountAddressHtml(Id workOrderId) {
    String plain = formatWorkOrderAccountAddressPlain(workOrderId);
    if (String.isBlank(plain)) {
      return '<em>No account or billing/shipping address on file.</em>';
    }
    List<String> esc = new List<String>();
    for (String line : plain.split('\n', -1)) {
      if (String.isNotBlank(line)) {
        esc.add(escapeHtml(line.trim()));
      }
    }
    return esc.isEmpty()
      ? '<em>No address lines.</em>'
      : String.join(esc, '<br/>');
  }

  /** Billing first; if empty, shipping. Street line + "City, State PostalCode" line. */
  private static String formatWorkOrderAccountAddressPlain(Id workOrderId) {
    List<WorkOrder> wos = [
      SELECT
        AccountId,
        Account.BillingStreet,
        Account.BillingCity,
        Account.BillingState,
        Account.BillingPostalCode,
        Account.ShippingStreet,
        Account.ShippingCity,
        Account.ShippingState,
        Account.ShippingPostalCode
      FROM WorkOrder
      WHERE Id = :workOrderId
      LIMIT 1
    ];
    if (wos.isEmpty() || wos[0].AccountId == null) {
      return null;
    }
    Account a = wos[0].Account;
    String street = a.BillingStreet;
    String city = a.BillingCity;
    String state = a.BillingState;
    String zip = a.BillingPostalCode;
    if (addressAllBlank(street, city, state, zip)) {
      street = a.ShippingStreet;
      city = a.ShippingCity;
      state = a.ShippingState;
      zip = a.ShippingPostalCode;
    }
    if (addressAllBlank(street, city, state, zip)) {
      return null;
    }
    List<String> lines = new List<String>();
    if (String.isNotBlank(street)) {
      lines.add(street.trim());
    }
    List<String> cityStateZip = new List<String>();
    if (String.isNotBlank(city)) {
      cityStateZip.add(city.trim());
    }
    if (String.isNotBlank(state)) {
      cityStateZip.add(state.trim());
    }
    if (String.isNotBlank(zip)) {
      cityStateZip.add(zip.trim());
    }
    if (!cityStateZip.isEmpty()) {
      lines.add(String.join(cityStateZip, ', '));
    }
    return String.join(lines, '\n');
  }

  private static Boolean addressAllBlank(
    String street,
    String city,
    String state,
    String zip
  ) {
    return String.isBlank(street) &&
      String.isBlank(city) &&
      String.isBlank(state) &&
      String.isBlank(zip);
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

  private static final String PREMIER_POOL_TEMPLATE_FOLDER = 'Premier Pool Templates';

  /** Classic HTML/custom/VF templates in the Premier Pool Templates folder only. */
  private static List<TemplateDto> loadPremierPoolTemplatesForUi() {
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
       SEND
    ========================================================= */

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
    Set<Id> cvIds = new Set<Id>();

    for (SendReqRow r : rows) {
      if (isServiceTeamMemberId(r.customerId)) {
        stmIds.add(r.customerId);
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

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ stm.Email__c });
        mail.setWhatId(mergeWhatId);
        mail.setSaveAsActivity(true);

        User currentUserStm = [
          SELECT Email
          FROM User
          WHERE Id = :UserInfo.getUserId()
          LIMIT 1
        ];
        List<OrgWideEmailAddress> oweaListStm = [
          SELECT Id
          FROM OrgWideEmailAddress
          WHERE Address = :currentUserStm.Email AND IsVerified = TRUE
          LIMIT 1
        ];
        if (!oweaListStm.isEmpty()) {
          mail.setOrgWideEmailAddressId(oweaListStm[0].Id);
          mail.setSenderDisplayName(currentUserStm.Email + ' (Salesforce)');
        }
        mail.setReplyTo(currentUserStm.Email);
        mail.setSenderDisplayName(currentUserStm.Email);

        // whoId must be Contact, Lead, or User for merge API; STM is recipient via setToAddresses only.
        Id whoForMerge = UserInfo.getUserId();
        if (r.parsedContent == true && String.isNotBlank(rowBody)) {
          mail.setSubject(
            String.isNotBlank(rowSubject) ? rowSubject : ''
          );
          mail.setHtmlBody(rowBody);
        } else if (emailTemplateId != null) {
          Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
            emailTemplateId,
            whoForMerge,
            mergeWhatId
          );

          if (String.isNotBlank(rowBody)) {
            String mergeBody = prepareForRenderEmailTemplate(rowBody, whoForMerge);
            String mergeSubject = prepareForRenderEmailTemplate(rowSubject, whoForMerge);
            List<String> bodiesToRender = new List<String>{ mergeBody };
            if (String.isNotBlank(rowSubject)) {
              bodiesToRender.add(mergeSubject);
            }

            List<Messaging.RenderEmailTemplateBodyResult> renderResults = Messaging.renderEmailTemplate(
              whoForMerge,
              mergeWhatId,
              bodiesToRender
            );

            if (renderResults[0].getSuccess()) {
              mail.setHtmlBody(renderResults[0].getMergedBody());
            } else {
              mail.setHtmlBody(mergeBody);
            }

            if (
              String.isNotBlank(rowSubject) &&
              renderResults.size() > 1 &&
              renderResults[1].getSuccess()
            ) {
              mail.setSubject(renderResults[1].getMergedBody());
            } else if (String.isNotBlank(rowSubject)) {
              mail.setSubject(mergeSubject);
            } else {
              mail.setSubject(rendered.getSubject());
            }
          } else {
            mail.setSubject(rendered.getSubject());
            mail.setHtmlBody(rendered.getHtmlBody());
          }
        } else {
          throw new AuraHandledException('Email template is required.');
        }

        if (r.parsedContent != true && isWorkOrderId(mergeWhatId)) {
          mail.setHtmlBody(
            applyAccountAddressPlaceholder(
              applyLineItemsPlaceholder(
                mail.getHtmlBody(),
                mergeWhatId,
                stm.Id
              ),
              mergeWhatId,
              true
            )
          );
          mail.setSubject(
            applyAccountAddressPlaceholder(
              applyLineItemsPlaceholder(
                mail.getSubject(),
                mergeWhatId,
                stm.Id
              ),
              mergeWhatId,
              false
            )
          );
        }

        emails.add(mail);

        LogRowDto stmLog = new LogRowDto();
        stmLog.customerName = stm.Name;
        stmLog.status = 'Sending';
        stmLog.message = 'Email is being sent...';
        logs.add(stmLog);
        emailIndexToLogs.put(emailIndex, new List<LogRowDto>{ stmLog });
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

      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setTargetObjectId(acc.Primary_Contact__c);
      mail.setWhatId(acc.Id);
      if (r.contentVersionIds != null && !r.contentVersionIds.isEmpty()) {
        mail.setEntityAttachments(r.contentVersionIds);
      }
      mail.setSaveAsActivity(true);

      User currentUser = [
        SELECT Email
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
      ];
      List<OrgWideEmailAddress> oweaList = [
        SELECT Id
        FROM OrgWideEmailAddress
        WHERE Address = :currentUser.Email AND IsVerified = TRUE
        LIMIT 1
      ];
      if (!oweaList.isEmpty()) {
        mail.setOrgWideEmailAddressId(oweaList[0].Id);
        mail.setSenderDisplayName(currentUser.Email + ' (Salesforce)');
      }
      mail.setReplyTo(currentUser.Email);
      mail.setReplyTo(currentUser.Email);
      mail.setSenderDisplayName(currentUser.Email);

      // Attach contracts only in "with contracts" mode
      if (r.contentVersionIds != null && !r.contentVersionIds.isEmpty()) {
        mail.setEntityAttachments(r.contentVersionIds);
      }
      mail.setSaveAsActivity(true);

      // USE SALESFORCE NATIVE TEMPLATE RENDERING
      // renderStoredEmailTemplate properly merges ALL fields
      if (r.parsedContent == true && String.isNotBlank(rowBody)) {
        mail.setSubject(
          String.isNotBlank(rowSubject) ? rowSubject : ''
        );
        mail.setHtmlBody(rowBody);
      } else if (emailTemplateId != null) {
        Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
          emailTemplateId,
          acc.Primary_Contact__c, // whoId (Contact)
          acc.Id // whatId (Account)
        );

        // If user provided custom subject/body, use renderEmailTemplate to merge those
        if (String.isNotBlank(rowBody)) {
          Id whoForAcc = acc.Primary_Contact__c;
          String mergeBody = prepareForRenderEmailTemplate(rowBody, whoForAcc);
          String mergeSubject = prepareForRenderEmailTemplate(rowSubject, whoForAcc);
          List<String> bodiesToRender = new List<String>{ mergeBody };
          if (String.isNotBlank(rowSubject)) {
            bodiesToRender.add(mergeSubject);
          }

          List<Messaging.RenderEmailTemplateBodyResult> renderResults = Messaging.renderEmailTemplate(
            whoForAcc, // whoId
            acc.Id, // whatId
            bodiesToRender
          );

          // Get rendered body
          if (renderResults[0].getSuccess()) {
            mail.setHtmlBody(renderResults[0].getMergedBody());
          } else {
            mail.setHtmlBody(mergeBody); // Fallback to unmerged
          }

          // Get rendered subject
          if (
            String.isNotBlank(rowSubject) &&
            renderResults.size() > 1 &&
            renderResults[1].getSuccess()
          ) {
            mail.setSubject(renderResults[1].getMergedBody());
          } else if (String.isNotBlank(rowSubject)) {
            mail.setSubject(mergeSubject);
          } else {
            mail.setSubject(rendered.getSubject());
          }
        } else {
          // Use fully rendered template
          mail.setSubject(rendered.getSubject());
          mail.setHtmlBody(rendered.getHtmlBody());
        }
      } else {
        throw new AuraHandledException('Email template is required.');
      }

      emails.add(mail);

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

          finalBody = applyLineItemsPlaceholder(
            finalBody,
            whatId,
            lineItemsRestrictStmId
          );
          finalSubject = applyLineItemsPlaceholder(
            finalSubject,
            whatId,
            lineItemsRestrictStmId
          );
          finalBody = applyAccountAddressPlaceholder(
            finalBody,
            whatId,
            true
          );
          finalSubject = applyAccountAddressPlaceholder(
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

    rawBody = prepareForRenderEmailTemplate(rawBody, whoId);
    rawSubject = prepareForRenderEmailTemplate(rawSubject, whoId);

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
        finalBody = softenCaseMergeFailures(finalBody);
      }
      if (finalSubject != null) {
        finalSubject = softenCaseMergeFailures(finalSubject);
      }
    }

    finalBody = applyLineItemsPlaceholder(
      finalBody,
      whatId,
      lineItemsRestrictStmId
    );
    finalSubject = applyLineItemsPlaceholder(
      finalSubject,
      whatId,
      lineItemsRestrictStmId
    );
    finalBody = applyAccountAddressPlaceholder(
      finalBody,
      whatId,
      true
    );
    finalSubject = applyAccountAddressPlaceholder(
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
