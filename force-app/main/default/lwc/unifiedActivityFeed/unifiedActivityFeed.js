import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { encodeDefaultFieldValues } from "lightning/pageReferenceUtils";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import {
  registerRefreshHandler,
  unregisterRefreshHandler
} from "lightning/refresh";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import getUnifiedActivities from "@salesforce/apex/UnifiedActivityController.getUnifiedActivities";

const WHO_ID_OBJECTS = new Set(["Contact", "Lead"]);

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

  _recordId;
  _sortDirection = "DESC";
  objectApiName;
  activityDefaultFields = [];
  primaryContactId;
  primaryContactEmail = "";
  accountAddress = "";
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

  @wire(getRecord, {
    recordId: "$recordId",
    fields: "$activityDefaultFields"
  })
  wiredActivityDefaults({ data }) {
    if (!data) {
      return;
    }
    this.primaryContactId = this.resolvePrimaryContactId(data);
    this.primaryContactEmail = this.resolvePrimaryContactEmail(data);
    this.accountAddress = this.resolveAccountAddress(data);
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
      this.primaryContactId = undefined;
      this.primaryContactEmail = "";
      this.accountAddress = "";
      this.activityDefaultFields = [];
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
        isClickable: part.partType === "image" && !!part.contentDocumentId
      }));
      const hasDescription = !!(
        item.description && String(item.description).trim()
      );
      const hasDisplayBody = contentParts.length > 0 || hasDescription;
      const isEmail = item.type === "EmailMessage";

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

  handleNewTask() {
    this.openNewActivityRecord("Task");
  }

  handleNewEvent() {
    this.openNewActivityRecord("Event");
  }

  handleLogACall() {
    this.openGlobalQuickAction("Global.LogACall");
  }

  handleLogAVisit() {
    this.openNewActivityRecord("Event", this.getVisitDefaults());
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
    if (
      !config.primaryContactField &&
      !config.emailField &&
      !config.locationFields
    ) {
      return [];
    }

    const fields = new Set();
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
    return Array.from(fields);
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

  getActivityDefaults() {
    if (WHO_ID_OBJECTS.has(this.objectApiName)) {
      return { WhoId: this.recordId };
    }

    const defaults = { WhatId: this.recordId };
    if (this.primaryContactId) {
      defaults.WhoId = this.primaryContactId;
    }
    return defaults;
  }

  getVisitDefaults() {
    const start = new Date();
    const end = new Date(start.getTime() + 60 * 60 * 1000);
    return {
      ...this.getActivityDefaults(),
      Subject: "Site Visit",
      StartDateTime: start.toISOString().slice(0, 19) + "Z",
      EndDateTime: end.toISOString().slice(0, 19) + "Z",
      ...(this.accountAddress ? { Location: this.accountAddress } : {})
    };
  }

  openGlobalQuickAction(apiName, defaults) {
    if (!this.recordId) {
      return;
    }

    const state = { recordId: this.recordId };
    if (defaults) {
      state.defaultFieldValues = encodeDefaultFieldValues(defaults);
    }

    this[NavigationMixin.Navigate]({
      type: "standard__quickAction",
      attributes: { apiName },
      state
    });
  }

  openNewActivityRecord(objectApiName, defaults) {
    if (!this.recordId) {
      return;
    }

    const fieldDefaults = defaults || this.getActivityDefaults();

    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName,
        actionName: "new"
      },
      state: {
        defaultFieldValues: encodeDefaultFieldValues(fieldDefaults),
        navigationLocation: "RELATED_LIST"
      }
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
    if (error.body?.message) return error.body.message;
    if (typeof error.body === "string") return error.body;
    if (error.message) return error.message;
    return "An unknown error occurred";
  }
}
