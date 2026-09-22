public with sharing class MassSendEmailBuilder {
  private static final List<String> LINE_ITEM_PLACEHOLDERS = new List<String>{
    '[LINE_ITEMS]',
    '[LINE ITEM]'
  };

  private static final String ACCOUNT_ADDRESS_PLACEHOLDER = '[ACCOUNT_ADDRESS]';

  private static final Set<String> CONTRACT_SEND_PDF_TEMPLATE_DEVELOPER_NAMES = new Set<String>{
    'Contract_Send_PDF_Regular_Customer',
    'Contract_Send_PDF_New_Customer'
  };

  private static final List<String> CONTRACT_SEND_PDF_CC_USER_NAMES = new List<String>{
    'Roman Shestakov',
    'Stephanie Pratt',
    'Jessica Floyd'
  };

  private static final String WORK_ORDER_ORG_WIDE_EMAIL_ADDRESS =
    'sf_workorders@premierswim.com';

  public class BuildRequest {
    public Id targetWhoId;
    public List<String> toAddresses;
    public Id mergeWhoId;
    public Id whatId;
    public List<Id> contentVersionIds;
    public Boolean parsedContent;
    public String rowSubject;
    public String rowBody;
    public String defaultSubject;
    public String defaultBody;
    public Id emailTemplateId;
    public String templateDeveloperName;
    public String recipientEmail;
    public User sendingUser;
    public Boolean useWorkOrderMailbox;
    public String regionalManagerEmail;
    public List<String> namedCcEmails;
    public Boolean applyWorkOrderPlaceholders;
    public Id lineItemsRestrictStmId;
  }

  public class EmailBuildResult {
    public Messaging.SingleEmailMessage mail;
    public String errorMessage;
  }

  /**
   * Centralized builder for a single outbound email used by the mass-send controller.
   * Returns an EmailBuildResult; if errorMessage is set, the caller should log the
   * row failure and continue instead of aborting the whole batch.
   */
  public static EmailBuildResult buildEmail(BuildRequest req) {
    EmailBuildResult result = new EmailBuildResult();

    String effectiveSubject = String.isNotBlank(req.rowSubject)
      ? req.rowSubject
      : req.defaultSubject;
    String effectiveBody = String.isNotBlank(req.rowBody)
      ? req.rowBody
      : req.defaultBody;

    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

    if (req.toAddresses != null && !req.toAddresses.isEmpty()) {
      mail.setToAddresses(req.toAddresses);
    } else if (req.targetWhoId != null) {
      mail.setTargetObjectId(req.targetWhoId);
    }

    if (req.whatId != null) {
      mail.setWhatId(req.whatId);
    }

    mail.setSaveAsActivity(true);

    if (req.contentVersionIds != null && !req.contentVersionIds.isEmpty()) {
      mail.setEntityAttachments(req.contentVersionIds);
    }

    applyOutboundSenderIdentity(mail, req.sendingUser, req.useWorkOrderMailbox);

    if (req.parsedContent == true && String.isNotBlank(effectiveBody)) {
      mail.setSubject(String.isNotBlank(effectiveSubject) ? effectiveSubject : '');
      mail.setHtmlBody(effectiveBody);
    } else if (req.emailTemplateId != null) {
      Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
        req.emailTemplateId,
        req.mergeWhoId,
        req.whatId
      );

      if (String.isNotBlank(effectiveBody)) {
        String mergeBody = prepareForRenderEmailTemplate(
          effectiveBody,
          req.mergeWhoId
        );
        String mergeSubject = prepareForRenderEmailTemplate(
          effectiveSubject,
          req.mergeWhoId
        );
        List<String> bodiesToRender = new List<String>{ mergeBody };
        if (String.isNotBlank(mergeSubject)) {
          bodiesToRender.add(mergeSubject);
        }

        List<Messaging.RenderEmailTemplateBodyResult> renderResults = Messaging.renderEmailTemplate(
          req.mergeWhoId,
          req.whatId,
          bodiesToRender
        );

        if (!renderResults.isEmpty() && renderResults[0].getSuccess()) {
          mail.setHtmlBody(renderResults[0].getMergedBody());
        } else {
          mail.setHtmlBody(mergeBody);
        }

        if (
          String.isNotBlank(mergeSubject) &&
          renderResults.size() > 1 &&
          renderResults[1].getSuccess()
        ) {
          mail.setSubject(renderResults[1].getMergedBody());
        } else if (String.isNotBlank(mergeSubject)) {
          mail.setSubject(mergeSubject);
        } else {
          mail.setSubject(rendered.getSubject());
        }
      } else {
        mail.setSubject(rendered.getSubject());
        mail.setHtmlBody(rendered.getHtmlBody());
      }
    } else {
      result.errorMessage = 'Email template is required.';
      return result;
    }

    if (req.applyWorkOrderPlaceholders == true && isWorkOrderId(req.whatId)) {
      mail.setHtmlBody(
        applyAccountAddressPlaceholder(
          applyLineItemsPlaceholder(
            mail.getHtmlBody(),
            req.whatId,
            req.lineItemsRestrictStmId
          ),
          req.whatId,
          true
        )
      );
      mail.setSubject(
        applyAccountAddressPlaceholder(
          applyLineItemsPlaceholder(
            mail.getSubject(),
            req.whatId,
            req.lineItemsRestrictStmId
          ),
          req.whatId,
          false
        )
      );
    }

    applyContractSendPdfCcAddresses(
      mail,
      req.templateDeveloperName,
      req.recipientEmail,
      req.regionalManagerEmail,
      req.namedCcEmails
    );

    result.mail = mail;
    return result;
  }

  /* ---------- Sender identity ---------- */

  private static OrgWideEmailAddress getWorkOrderOrgWideEmailAddress() {
    List<OrgWideEmailAddress> rows = [
      SELECT Id, DisplayName, Address
      FROM OrgWideEmailAddress
      WHERE Address = :WORK_ORDER_ORG_WIDE_EMAIL_ADDRESS AND IsVerified = TRUE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  public static void applyOutboundSenderIdentity(
    Messaging.SingleEmailMessage mail,
    User currentUser,
    Boolean useWorkOrderMailbox
  ) {
    if (useWorkOrderMailbox) {
      OrgWideEmailAddress woOwea = getWorkOrderOrgWideEmailAddress();
      if (woOwea != null) {
        mail.setOrgWideEmailAddressId(woOwea.Id);
        mail.setReplyTo(woOwea.Address);
        return;
      }
    }

    List<OrgWideEmailAddress> oweaList = [
      SELECT Id, Address
      FROM OrgWideEmailAddress
      WHERE Address = :currentUser.Email AND IsVerified = TRUE
      LIMIT 1
    ];
    if (!oweaList.isEmpty()) {
      mail.setOrgWideEmailAddressId(oweaList[0].Id);
      mail.setReplyTo(currentUser.Email);
      return;
    }

    mail.setReplyTo(currentUser.Email);
    mail.setSenderDisplayName(currentUser.Email);
  }

  /* ---------- Template rendering helpers ---------- */

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

  public static String softenCaseMergeFailures(String text) {
    if (String.isBlank(text)) {
      return text;
    }
    Pattern p = Pattern.compile('\\{\\{\\{?Case\\.([^}]+)\\}\\}\\}?');
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

  public static String prepareForRenderEmailTemplate(String text, Id whoId) {
    return expandEmailMergeAliases(normalizeTripleBraceMergeFields(text), whoId);
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

  /* ---------- Work Order placeholders ---------- */

  public static String applyLineItemsPlaceholder(
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
    String tableHtml = buildQuickBookLineItemsHtml(workOrderId, serviceTeamMemberId);
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
        SELECT Name, Description__c, Quantity__c
        FROM Quick_Book_Work_Order_Line_Item__c
        WHERE
          Work_Order__c = :workOrderId
          AND Service_Team_Member__c = :serviceTeamMemberId
        ORDER BY CreatedDate ASC
      ];
    } else {
      lines = [
        SELECT Name, Description__c, Quantity__c
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
          '</tr>'
      );
    }

    rows.add('</tbody></table>');
    return String.join(rows, '');
  }

  public static String applyAccountAddressPlaceholder(
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

  private static Boolean isWorkOrderId(Id recordId) {
    return recordId != null && recordId.getSobjectType() == WorkOrder.SObjectType;
  }

  /* ---------- CC / template helpers ---------- */

  public static String resolveEmailTemplateDeveloperName(Id emailTemplateId) {
    if (emailTemplateId == null) {
      return null;
    }
    List<EmailTemplate> templates = [
      SELECT DeveloperName
      FROM EmailTemplate
      WHERE Id = :emailTemplateId
      LIMIT 1
    ];
    return templates.isEmpty() ? null : templates[0].DeveloperName;
  }

  public static List<String> loadNamedContractSendPdfCcEmails() {
    Map<String, String> emailByName = new Map<String, String>();
    for (User userRecord : [
      SELECT Name, Email
      FROM User
      WHERE Name IN :CONTRACT_SEND_PDF_CC_USER_NAMES
      AND IsActive = true
    ]) {
      if (String.isNotBlank(userRecord.Email)) {
        emailByName.put(userRecord.Name, userRecord.Email);
      }
    }

    List<String> emails = new List<String>();
    for (String userName : CONTRACT_SEND_PDF_CC_USER_NAMES) {
      if (emailByName.containsKey(userName)) {
        emails.add(emailByName.get(userName));
      }
    }
    return emails;
  }

  public static Map<Id, String> resolveRegionalManagerEmailsByAccount(Set<Id> accountIds) {
    Map<Id, String> accountToRmEmail = new Map<Id, String>();
    if (accountIds == null || accountIds.isEmpty()) {
      return accountToRmEmail;
    }

    for (Contract_Bid__c bid : [
      SELECT Customer__c, Lead_Owner__r.Email, CreatedDate
      FROM Contract_Bid__c
      WHERE Customer__c IN :accountIds
      AND Lead_Owner__c != NULL
      AND Lead_Owner__r.IsActive = true
      AND Lead_Owner__r.Email != NULL
      ORDER BY CreatedDate DESC
    ]) {
      if (!accountToRmEmail.containsKey(bid.Customer__c)) {
        accountToRmEmail.put(bid.Customer__c, bid.Lead_Owner__r.Email);
      }
    }
    return accountToRmEmail;
  }

  private static void applyContractSendPdfCcAddresses(
    Messaging.SingleEmailMessage mail,
    String templateDeveloperName,
    String toEmail,
    String regionalManagerEmail,
    List<String> namedCcEmails
  ) {
    if (mail == null || !CONTRACT_SEND_PDF_TEMPLATE_DEVELOPER_NAMES.contains(templateDeveloperName)) {
      return;
    }
    List<String> ccEmails = buildContractSendPdfCcAddresses(
      toEmail,
      regionalManagerEmail,
      namedCcEmails
    );
    if (!ccEmails.isEmpty()) {
      mail.setCcAddresses(ccEmails);
    }
  }

  public static List<String> buildContractSendPdfCcAddresses(
    String toEmail,
    String regionalManagerEmail,
    List<String> namedCcEmails
  ) {
    Set<String> seen = new Set<String>();
    List<String> ccEmails = new List<String>();
    String toEmailKey = String.isBlank(toEmail) ? null : toEmail.trim().toLowerCase();

    addCcEmail(ccEmails, seen, toEmailKey, regionalManagerEmail);
    if (namedCcEmails != null) {
      for (String namedEmail : namedCcEmails) {
        addCcEmail(ccEmails, seen, toEmailKey, namedEmail);
      }
    }
    return ccEmails;
  }

  private static void addCcEmail(
    List<String> ccEmails,
    Set<String> seen,
    String toEmailKey,
    String emailValue
  ) {
    if (String.isBlank(emailValue)) {
      return;
    }
    String trimmed = emailValue.trim();
    String key = trimmed.toLowerCase();
    if (key == toEmailKey || seen.contains(key)) {
      return;
    }
    seen.add(key);
    ccEmails.add(trimmed);
  }
}
