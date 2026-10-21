import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { encodeDefaultFieldValues } from "lightning/pageReferenceUtils";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import {
  registerRefreshHandler,
  unregisterRefreshHandler
} from "lightning/refresh";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import TASK_OBJECT from "@salesforce/schema/Task";
import getUnifiedActivities from "@salesforce/apex/UnifiedActivityController.getUnifiedActivities";

const WHO_ID_OBJECTS = new Set(["Contact", "Lead"]);
const BID_STAGE_BID_QUALIFIED = "Contact Made";
// Negotiation Started = current API; Proposal/Review = label "Negotiation" on stage-update branch
const BID_STAGES_NEGOTIATION = new Set([
  "Negotiation Started",
  "Proposal/Review"
]);
const RM_REQUEST_RECORD_TYPE_LABEL = "Regional Manager Request";
const REQUEST_CONTRACT_SUBJECT = "Request a Contract Bid";
const REQUEST_NEW_VERSION_SUBJECT = "Request New Version";

const FILE_ICONS = {
  pdf: "doctype:pdf",
  doc: "doctype:word",
  docx: "doctype:word",
  xls: "doctype:excel",
  xlsx: "doctype:excel",
  ppt: "doctype:ppt",
  pptx: "doctype:ppt",
  txt: "doctype:txt",
  csv: "doctype:csv",
  zip: "doctype:zip"
};

function fileIconName(fileName) {
  const extension = String(fileName || "")
    .split(".")
    .pop()
    .toLowerCase();
  return FILE_ICONS[extension] || "doctype:attachment";
}

const DEFAULT_CONFIG = {
  Account: {
    primaryContactField: "Primary_Contact__c",
    emailField: "Email__c",
    locationFields:
      "BillingStreet,BillingCity,BillingState,BillingPostalCode,BillingCountry"
  },
  Contract_Bid__c: {
    primaryContactField: "Customer__r.Primary_Contact__c",
    emailField: "Customer__r.Email__c",
    locationFields:
      "Customer__r.BillingStreet,Customer__r.BillingCity,Customer__r.BillingState,Customer__r.BillingPostalCode,Customer__r.BillingCountry"
  }
};

export default class UnifiedActivityFeed extends NavigationMixin(
  LightningElement
) {
  @api maxItems = 20;
  @api relatedRecordConfig = "";
  @api currentRecordLabel = "";
  @api primaryContactField = "";
  @api emailField = "";
  @api locationFields = "";
  @api relatedRecordLocationFields = "";
  @api newEventLabel = "";
  @api newEventIcon = "";

  _recordId;
  _sortDirection = "DESC";
  objectApiName;
  activityDefaultFields;
  relatedRecordId;
  primaryContactId;
  primaryContactEmail = "";
  accountAddress = "";
  currentStage;
  contractCreatorId;
  rmRequestRecordTypeId;
  refreshHandlerId;
  activities = [];
  totalCount = 0;
  nextOffset = 0;
  hasMore = false;
  isLoading = false;
  isLoadingMore = false;
  selectedType = "All";
  searchTerm = "";
  showComposer = false;

  @wire(getRecord, { recordId: "$recordId", layoutTypes: ["Compact"] })
  wiredRecord({ data }) {
    if (data) {
      this.objectApiName = data.apiName;
      this.activityDefaultFields = this.resolveActivityDefaultFields(data);
    }
  }

  @wire(getObjectInfo, { objectApiName: TASK_OBJECT })
  wiredTaskObjectInfo({ data }) {
    if (!data?.recordTypeInfos) {
      return;
    }
    const match = Object.values(data.recordTypeInfos).find(
      (rt) => rt.name === RM_REQUEST_RECORD_TYPE_LABEL && rt.available
    );
    this.rmRequestRecordTypeId = match?.recordTypeId;
  }

  @wire(getRecord, {
    recordId: "$recordId",
    fields: "$activityDefaultFields"
  })
  wiredActivityDefaults({ data, error }) {
    if (error) {
      this.showError(error);
      return;
    }
    if (!data) {
      return;
    }
    this.relatedRecordId = this.resolveRelatedRecordId(data);
    this.primaryContactId = this.resolvePrimaryContactId(data);
    this.primaryContactEmail = this.resolvePrimaryContactEmail(data);
    this.accountAddress = this.resolveAccountAddress(data);
    this.currentStage = this.resolveCurrentStage(data);
    this.contractCreatorId = this.resolveContractCreatorId(data);
  }

  get isNegotiationStage() {
    return BID_STAGES_NEGOTIATION.has(this.currentStage);
  }

  get showRequestContract() {
    return (
      this.objectApiName === "Contract_Bid__c" &&
      (this.currentStage === BID_STAGE_BID_QUALIFIED || this.isNegotiationStage)
    );
  }

  get requestContractSubject() {
    return this.isNegotiationStage
      ? REQUEST_NEW_VERSION_SUBJECT
      : REQUEST_CONTRACT_SUBJECT;
  }

  get effectiveConfig() {
    const defaults = DEFAULT_CONFIG[this.objectApiName] || {};
    return {
      primaryContactField:
        this.primaryContactField || defaults.primaryContactField || "",
      emailField: this.emailField || defaults.emailField || "",
      locationFields: this.locationFields || defaults.locationFields || ""
    };
  }

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    if (this._recordId !== value) {
      this._recordId = value;
      this.objectApiName = undefined;
      this.activityDefaultFields = undefined;
      this.primaryContactId = undefined;
      this.primaryContactEmail = "";
      this.accountAddress = "";
      this.relatedRecordId = undefined;
      this.currentStage = undefined;
      this.contractCreatorId = undefined;
      if (value) {
        this.loadActivities(true);
      } else {
        this.resetState();
      }
    }
  }

  @api
  get sortDirection() {
    return this._sortDirection;
  }

  set sortDirection(value) {
    this._sortDirection = value || "DESC";
  }

  get hasRecordId() {
    return !!this.recordId;
  }

  get isAscending() {
    return this._sortDirection.toUpperCase() === "ASC";
  }

  get sortIcon() {
    return this.isAscending ? "utility:arrowup" : "utility:arrowdown";
  }

  get sortLabel() {
    return this.isAscending ? "Oldest first" : "Newest first";
  }

  get typeOptions() {
    return [
      { label: "All", value: "All" },
      { label: "Tasks", value: "Task" },
      { label: "Calls", value: "Call" },
      { label: "Events", value: "Event" },
      { label: "Emails", value: "EmailMessage" },
      { label: "Notes", value: "ContentNote" },
      { label: "Chatter", value: "FeedItem" }
    ];
  }

  get countLabel() {
    if (this.totalCount === 0) {
      return "0";
    }
    if (this.activities.length >= this.totalCount) {
      return String(this.totalCount);
    }
    return `${this.activities.length} of ${this.totalCount}`;
  }

  get showLoadMore() {
    return this.hasMore && this.activities.length > 0 && !this.isLoading;
  }

  get emptyMessage() {
    if (this.selectedType === "All" && !this.searchTerm) {
      return "No activities or chatter to show.";
    }
    if (this.searchTerm) {
      return "No matches found. Try a different search term.";
    }
    return `No ${this.selectedType.toLowerCase()} records found.`;
  }

  connectedCallback() {
    this.refreshHandlerId = registerRefreshHandler(
      this,
      this.handleRefreshView.bind(this)
    );
    if (this.recordId) {
      this.loadActivities(true);
    }
  }

  disconnectedCallback() {
    if (this.refreshHandlerId) {
      unregisterRefreshHandler(this.refreshHandlerId);
    }
  }

  handleRefreshView() {
    return this.loadActivities(true)
      .then(() => true)
      .catch(() => false);
  }

  resetState() {
    this.activities = [];
    this.totalCount = 0;
    this.nextOffset = 0;
    this.hasMore = false;
    this.isLoading = false;
    this.isLoadingMore = false;
  }

  async loadActivities(reset) {
    if (!this.recordId) {
      return;
    }

    if (reset) {
      this.nextOffset = 0;
      this.isLoading = true;
    } else {
      this.isLoadingMore = true;
    }

    try {
      const result = await getUnifiedActivities({
        recordId: this.recordId,
        sortDirection: this.sortDirection,
        pageSize: this.maxItems,
        offset: reset ? 0 : this.nextOffset,
        activityType: this.selectedType,
        searchTerm: this.searchTerm,
        relatedRecordConfig: this.relatedRecordConfig,
        currentRecordLabel: this.currentRecordLabel
      });

      const enriched = this.enrichActivities(result.items || []);
      this.activities = reset ? enriched : [...this.activities, ...enriched];
      this.totalCount = result.totalCount || 0;
      this.hasMore = result.hasMore || false;
      this.nextOffset = result.nextOffset || this.activities.length;
    } catch (error) {
      this.showError(error);
    } finally {
      this.isLoading = false;
      this.isLoadingMore = false;
    }
  }

  enrichActivities(data) {
    return data.map((item) => {
      const contentParts = (item.contentParts || []).map((part, index) => ({
        ...part,
        key: `${item.id}-${index}`,
        isText: part.partType === "text",
        isImage: part.partType === "image",
        isFile: part.partType === "file",
        fileIcon: fileIconName(part.fileName),
        isClickable:
          (part.partType === "image" || part.partType === "file") &&
          !!part.contentDocumentId
      }));
      const hasDescription = !!(
        item.description && String(item.description).trim()
      );
      const hasDisplayBody = contentParts.length > 0 || hasDescription;
      const isEmail = item.type === "EmailMessage";
      const isNote = item.type === "ContentNote";

      return {
        ...item,
        contentParts,
        hasContentParts: contentParts.length > 0,
        hasDescription,
        hasDisplayBody,
        showSourceLabel: this.showSourceLabels && !!item.sourceLabel,
        displayDate: this.formatDate(item.createdDate),
        timelineClass: `slds-timeline__item_expandable ${this.timelineItemClass(item.type)}`,
        isTask: item.type === "Task",
        isCall: item.type === "Call",
        isEvent: item.type === "Event",
        isEmail,
        isNote,
        isFeed: item.type === "FeedItem",
        isCollapsibleBody: isEmail && hasDisplayBody,
        bodyPreview: isEmail
          ? this.buildPlainTextPreview(item.description)
          : "",
        attachmentCount: item.attachmentCount || 0,
        hasAttachments: isEmail && (item.attachmentCount || 0) > 0,
        attachmentLabel:
          isEmail && (item.attachmentCount || 0) > 0
            ? item.attachmentCount === 1
              ? "1 attachment"
              : `${item.attachmentCount} attachments`
            : ""
      };
    });
  }

  buildPlainTextPreview(value) {
    if (!value) {
      return "";
    }
    const text = String(value)
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<br\s*\/?>/gi, " ")
      .replace(/<\/p>/gi, " ")
      .replace(/<[^>]+>/g, " ")
      .replace(/&nbsp;/gi, " ")
      .replace(/&amp;/gi, "&")
      .replace(/&lt;/gi, "<")
      .replace(/&gt;/gi, ">")
      .replace(/&quot;/gi, '"')
      .replace(/&#39;/gi, "'")
      .replace(/\s+/g, " ")
      .trim();
    const maxLength = 160;
    if (text.length <= maxLength) {
      return text;
    }
    return `${text.slice(0, maxLength).trim()}…`;
  }

  timelineItemClass(type) {
    switch (type) {
      case "Call":
        return "slds-timeline__item_call";
      case "Event":
        return "slds-timeline__item_event";
      case "EmailMessage":
        return "slds-timeline__item_email";
      default:
        return "slds-timeline__item_task";
    }
  }

  get showSourceLabels() {
    return (
      !!this.relatedRecordConfig && this.relatedRecordConfig.trim().length > 0
    );
  }

  formatDate(value) {
    if (!value) return "";
    const date = new Date(value);
    return date.toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit"
    });
  }

  handleSortToggle() {
    this._sortDirection = this.isAscending ? "DESC" : "ASC";
    this.loadActivities(true);
  }

  handleTypeChange(event) {
    this.selectedType = event.detail.value;
    this.loadActivities(true);
  }

  handleSearchChange(event) {
    this.searchTerm = event.detail.value;
    this.loadActivities(true);
  }

  handleRefresh() {
    this.loadActivities(true);
  }

  handleLoadMore() {
    if (!this.hasMore || this.isLoadingMore) {
      return;
    }
    this.loadActivities(false);
  }

  handleRequestContract() {
    if (!this.recordId) {
      return;
    }

    const defaults = {
      ...this.getActivityDefaults(),
      Subject: this.requestContractSubject
    };
    if (this.rmRequestRecordTypeId) {
      defaults.RecordTypeId = this.rmRequestRecordTypeId;
    }
    if (this.contractCreatorId) {
      defaults.OwnerId = this.contractCreatorId;
    }
    this.openNewActivityRecord("Task", defaults, this.rmRequestRecordTypeId);
  }

  handleNewTask() {
    this.openNewActivityRecord("Task", this.getActivityDefaults());
  }

  handleNewEvent() {
    this.openNewActivityRecord("Event", this.getActivityDefaults());
  }

  handleLogACall() {
    this.openGlobalQuickAction("Global.LogACall");
  }

  handleLogAVisit() {
    const accountId =
      this.objectApiName === "Account" ? this.recordId : this.relatedRecordId;
    if (!accountId) {
      return;
    }
    this.openGlobalQuickAction(
      "Account.New_Visit",
      this.getVisitDefaults(accountId),
      accountId
    );
  }

  handleNewPost() {
    this.showComposer = true;
  }

  handleNewEmail() {
    const defaults = {};
    if (this.primaryContactEmail) {
      defaults.ToAddress = this.primaryContactEmail;
    }
    this.openGlobalQuickAction(
      "Global.SendEmail",
      Object.keys(defaults).length ? defaults : undefined
    );
  }

  resolveActivityDefaultFields(record) {
    const config = this.effectiveConfig;
    const fields = new Set();

    this.parseRelatedRecordConfig().forEach((field) =>
      fields.add(`${record.apiName}.${field}`)
    );

    if (config.primaryContactField) {
      fields.add(`${record.apiName}.${config.primaryContactField}`);
      fields.add(
        `${record.apiName}.${this.resolveContactEmailField(config.primaryContactField)}`
      );
    }
    if (config.emailField) {
      fields.add(`${record.apiName}.${config.emailField}`);
    }
    if (config.locationFields) {
      config.locationFields
        .split(",")
        .map((field) => field.trim())
        .filter((field) => field.length > 0)
        .forEach((field) => fields.add(`${record.apiName}.${field}`));
    }

    if (record.apiName === "Contract_Bid__c") {
      fields.add(`${record.apiName}.Stage__c`);
      fields.add(`${record.apiName}.Record_Manager__c`);
    }

    if (fields.size === 0) {
      return undefined;
    }
    return Array.from(fields);
  }

  resolveCurrentStage(record) {
    if (record.apiName !== "Contract_Bid__c") {
      return undefined;
    }
    return getFieldValue(record, `${record.apiName}.Stage__c`);
  }

  resolveContractCreatorId(record) {
    if (record.apiName !== "Contract_Bid__c") {
      return undefined;
    }
    return getFieldValue(record, `${record.apiName}.Record_Manager__c`);
  }

  parseRelatedRecordConfig() {
    if (!this.relatedRecordConfig) {
      return [];
    }
    return this.relatedRecordConfig
      .split(",")
      .map((entry) => entry.split(":")[0].trim())
      .filter((field) => field.length > 0);
  }

  resolveContactEmailField(contactLookupField) {
    return contactLookupField.replace(/__c$/, "__r") + ".Email";
  }

  resolvePrimaryContactId(record) {
    const field = this.effectiveConfig.primaryContactField;
    if (!field) {
      return undefined;
    }
    return getFieldValue(record, `${record.apiName}.${field}`);
  }

  resolvePrimaryContactEmail(record) {
    const config = this.effectiveConfig;
    const primaryField = config.primaryContactField;
    const emailField = config.emailField;

    if (primaryField) {
      const primaryContactEmail = getFieldValue(
        record,
        `${record.apiName}.${this.resolveContactEmailField(primaryField)}`
      );
      if (primaryContactEmail) {
        return primaryContactEmail;
      }
    }
    if (emailField) {
      return getFieldValue(record, `${record.apiName}.${emailField}`) || "";
    }
    return "";
  }

  resolveRelatedRecordId(record) {
    const fields = this.parseRelatedRecordConfig();
    for (const field of fields) {
      const value = getFieldValue(record, `${record.apiName}.${field}`);
      if (value) {
        return value;
      }
    }
    return undefined;
  }

  resolveAccountAddress(record) {
    const locationFields = this.effectiveConfig.locationFields;
    if (!locationFields) {
      return "";
    }
    const parts = locationFields
      .split(",")
      .map((field) => field.trim())
      .filter((field) => field.length > 0)
      .map((field) => getFieldValue(record, `${record.apiName}.${field}`));
    return this.formatAddress(parts);
  }

  formatAddress(parts) {
    return parts
      .map((part) => (part == null ? "" : String(part).trim()))
      .filter((part) => part.length > 0)
      .join(", ");
  }

  getActivityDefaults(whatId = this.recordId) {
    if (WHO_ID_OBJECTS.has(this.objectApiName)) {
      return { WhoId: this.recordId };
    }

    const defaults = { WhatId: whatId };
    if (this.primaryContactId) {
      defaults.WhoId = this.primaryContactId;
    }
    return defaults;
  }

  getVisitDefaults(accountId) {
    const start = new Date();
    const end = new Date(start.getTime() + 60 * 60 * 1000);
    const defaults = {
      WhatId: accountId,
      Subject: "Site Visit",
      StartDateTime: start.toISOString().slice(0, 19) + "Z",
      EndDateTime: end.toISOString().slice(0, 19) + "Z"
    };
    if (this.primaryContactId) {
      defaults.WhoId = this.primaryContactId;
    }
    if (this.accountAddress) {
      defaults.Location = this.accountAddress;
    }
    return defaults;
  }

  openGlobalQuickAction(apiName, defaults, contextRecordId) {
    const recordId = contextRecordId || this.recordId;
    if (!recordId) {
      return;
    }

    const state = { recordId };
    if (defaults) {
      state.defaultFieldValues = encodeDefaultFieldValues(defaults);
    }

    this[NavigationMixin.Navigate]({
      type: "standard__quickAction",
      attributes: { apiName },
      state
    });
  }

  openNewActivityRecord(objectApiName, defaults, recordTypeId) {
    if (!this.recordId) {
      return;
    }

    const fieldDefaults = defaults || this.getActivityDefaults();
    const state = {
      defaultFieldValues: encodeDefaultFieldValues(fieldDefaults),
      navigationLocation: "RELATED_LIST"
    };
    if (recordTypeId) {
      state.recordTypeId = recordTypeId;
    }

    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName,
        actionName: "new"
      },
      state
    });
  }

  handleItemClick(event) {
    const recordId = event.detail.recordId;
    this.openRecordPage(recordId);
  }

  handleImageClick(event) {
    const contentDocumentId = event.detail.contentDocumentId;
    if (!contentDocumentId) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__namedPage",
      attributes: {
        pageName: "filePreview"
      },
      state: {
        selectedRecordId: contentDocumentId
      }
    });
  }

  openRecordPage(recordId) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: recordId,
        actionName: "view"
      }
    });
  }

  handleComposerCancel() {
    this.showComposer = false;
  }

  handleComposerSuccess() {
    this.showComposer = false;
    this.loadActivities(true);
  }

  showError(error) {
    const message = this.extractErrorMessage(error);
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Error loading activities",
        message: message,
        variant: "error"
      })
    );
  }

  extractErrorMessage(error) {
    const outputErrors = error.body?.output?.errors;
    if (Array.isArray(outputErrors) && outputErrors.length > 0) {
      return outputErrors
        .map((item) => item.message)
        .filter((message) => !!message)
        .join(" ");
    }

    const fieldErrors = error.body?.output?.fieldErrors;
    if (fieldErrors) {
      const messages = [];
      Object.keys(fieldErrors).forEach((field) => {
        (fieldErrors[field] || []).forEach((item) => {
          if (item.message) {
            messages.push(item.message);
          }
        });
      });
      if (messages.length > 0) {
        return messages.join(" ");
      }
    }

    if (error.body?.message) return error.body.message;
    if (typeof error.body === "string") return error.body;
    if (error.message) return error.message;
    return "An unknown error occurred";
  }
}
