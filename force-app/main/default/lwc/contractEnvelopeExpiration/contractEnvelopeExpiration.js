import { LightningElement, api } from "lwc";
import getSelectionSummary from "@salesforce/apex/DocuSignEnvelopeExpirationService.getSelectionSummary";
import queueUpdate from "@salesforce/apex/DocuSignEnvelopeExpirationService.queueUpdate";
import getUpdateStatus from "@salesforce/apex/DocuSignEnvelopeExpirationService.getUpdateStatus";
import { FlowAttributeChangeEvent } from "lightning/flowSupport";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";

const DAY_MS = 24 * 60 * 60 * 1000;

export default class ContractEnvelopeExpiration extends LightningElement {
  @api recordId;
  @api recordIds = [];
  @api expirationDate;
  @api warningDate;

  bidCount = 0;
  envelopeCount;
  isLoading = false;
  isSubmitting = false;
  statusMessage;
  statusVariant = "info";
  loadError;
  requestId;
  _pollGeneration = 0;
  _loadedFor;

  connectedCallback() {
    if (!this.expirationDate) {
      this.expirationDate = this.addDays(120);
    }
    if (!this.warningDate) {
      this.warningDate = this.addDays(110);
    }
    if (this.hasFlowSelection) {
      this.notifyFlow("expirationDate", this.expirationDate);
      this.notifyFlow("warningDate", this.warningDate);
      this.loadSummary();
    }
  }

  renderedCallback() {
    if (
      this.isRecordAction &&
      this.recordId &&
      this.recordId !== this._loadedFor &&
      !this.isLoading
    ) {
      this.loadSummary();
    }
  }

  disconnectedCallback() {
    this._pollGeneration += 1;
  }

  get hasFlowSelection() {
    return Array.isArray(this.recordIds) && this.recordIds.length > 0;
  }

  get isRecordAction() {
    return !this.hasFlowSelection;
  }

  get selectedIds() {
    return this.hasFlowSelection ? this.recordIds : [this.recordId];
  }

  async loadSummary() {
    const ids = this.selectedIds.filter((id) => id);
    if (ids.length === 0) {
      return;
    }
    const loadKey = ids.join(",");
    if (this._loadedFor === loadKey) {
      return;
    }
    this._loadedFor = loadKey;
    this.isLoading = true;
    this.loadError = undefined;
    try {
      const summary = await getSelectionSummary({ contractBidIds: ids });
      if (this._loadedFor !== loadKey) {
        return;
      }
      this.bidCount = summary?.bidCount || 0;
      this.envelopeCount = summary?.envelopeCount || 0;
    } catch (error) {
      if (this._loadedFor !== loadKey) {
        return;
      }
      this.envelopeCount = undefined;
      this.loadError =
        error?.body?.message ||
        error?.message ||
        "Unable to load open envelopes.";
    } finally {
      if (this._loadedFor === loadKey) {
        this.isLoading = false;
      }
    }
  }

  handleExpirationChange(event) {
    this.expirationDate = event.detail.value;
    this.notifyFlow("expirationDate", this.expirationDate);
  }

  handleWarningChange(event) {
    this.warningDate = event.detail.value;
    this.notifyFlow("warningDate", this.warningDate);
  }

  notifyFlow(name, value) {
    if (!this.hasFlowSelection) {
      return;
    }
    this.dispatchEvent(new FlowAttributeChangeEvent(name, value));
  }

  @api
  validate() {
    const errorMessage = this.validationMessage;
    return {
      isValid: !errorMessage,
      errorMessage
    };
  }

  get validationMessage() {
    if (this.isRecordAction && (!this.recordId || this.envelopeCount === undefined)) {
      return "Wait for the open-envelope check to finish.";
    }
    if (this.isLoading) {
      return "Wait for the open-envelope check to finish.";
    }
    if (this.loadError) {
      return this.loadError;
    }
    if (!this.hasFlowSelection && !this.recordId) {
      return "Select at least one Contract Bid.";
    }
    if (this.hasFlowSelection && this.recordIds.length === 0) {
      return "Select at least one Contract Bid.";
    }
    if (this.envelopeCount === 0) {
      return "No Sent or Delivered DocuSign envelopes were found.";
    }
    if (!this.expirationDate || !this.warningDate) {
      return "Expiration date and expiration warning date are required.";
    }

    const today = this.toUtcDate(this.today);
    const expiration = this.toUtcDate(this.expirationDate);
    const warning = this.toUtcDate(this.warningDate);
    if (expiration <= today) {
      return "Expiration date must be in the future.";
    }
    if (warning < today) {
      return "Expiration warning date cannot be in the past.";
    }
    if (warning >= expiration) {
      return "Expiration warning date must be before the expiration date.";
    }
    if (Math.round((expiration - today) / DAY_MS) > 999) {
      return "Expiration date must be within 999 days.";
    }
    return null;
  }

  get today() {
    return new Date().toISOString().slice(0, 10);
  }

  get minimumExpirationDate() {
    return this.addDays(1);
  }

  get statusClass() {
    const tone =
      this.statusVariant === "error"
        ? "slds-alert_error"
        : this.statusVariant === "success"
          ? "slds-theme_success"
          : "slds-alert_info";
    return `slds-notify slds-notify_alert ${tone} slds-m-bottom_medium`;
  }

  get summaryText() {
    if (this.isRecordAction) {
      if (this.isLoading || this.envelopeCount === undefined) {
        return "Checking open DocuSign envelopes...";
      }
      return `This Contract Bid has ${this.envelopeCount} open envelope(s).`;
    }
    return `${this.bidCount} selected Contract Bid(s), ${this.envelopeCount || 0} open envelope(s)`;
  }

  get submitDisabled() {
    return this.isSubmitting || Boolean(this.validationMessage);
  }

  async handleSubmit() {
    const validation = this.validate();
    if (!validation.isValid) {
      if (this.isRecordAction) {
        this.toast("Cannot update envelopes", validation.errorMessage, "error");
      }
      return;
    }

    this.isSubmitting = true;
    if (this.hasFlowSelection) {
      this.statusMessage = "Queueing DocuSign envelope updates...";
    }
    try {
      const result = await queueUpdate({
        contractBidIds: this.selectedIds,
        expirationDate: this.expirationDate,
        warningDate: this.warningDate
      });
      if (this.isRecordAction) {
        this.toast(
          "Update queued",
          result?.message || "DocuSign envelope update queued.",
          "success"
        );
        this.dispatchEvent(new CloseActionScreenEvent());
        return;
      }
      this.requestId = result?.requestId;
      this.statusMessage = "Updating DocuSign envelopes...";
      this.statusVariant = "info";
      await this.pollStatus();
    } catch (error) {
      const message =
        error?.body?.message || error?.message || "Unable to queue updates.";
      if (this.isRecordAction) {
        this.toast("Update failed", message, "error");
      } else {
        this.statusMessage = message;
        this.statusVariant = "error";
      }
    } finally {
      this.isSubmitting = false;
    }
  }

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  toast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({ title, message, variant, mode: "sticky" })
    );
  }

  async pollStatus() {
    const generation = ++this._pollGeneration;
    const deadline = Date.now() + 90000;
    while (generation === this._pollGeneration && Date.now() < deadline) {
      const status = await getUpdateStatus({ requestId: this.requestId });
      if (generation !== this._pollGeneration) {
        return;
      }
      this.applyStatus(status);
      if (status?.finished) {
        return;
      }
      await this.delay(2000);
    }
    if (generation === this._pollGeneration) {
      this.statusVariant = "error";
      this.statusMessage =
        "The update is still running and has not reported a final result. Request " +
        (this.requestId || "");
    }
  }

  applyStatus(status) {
    const summary = `${status?.status || "Unknown"}: ${status?.succeeded || 0} succeeded, ${status?.failed || 0} failed of ${status?.total || 0}.`;
    this.statusMessage = status?.errorSummary
      ? `${summary} ${status.errorSummary}`
      : summary;
    if (!status?.finished) {
      this.statusVariant = "info";
    } else if ((status.failed || 0) > 0) {
      this.statusVariant = "error";
    } else {
      this.statusVariant = "success";
    }
  }

  delay(milliseconds) {
    return new Promise((resolve) => {
      setTimeout(resolve, milliseconds);
    });
  }

  addDays(days) {
    const date = new Date();
    date.setUTCHours(12, 0, 0, 0);
    date.setUTCDate(date.getUTCDate() + days);
    return date.toISOString().slice(0, 10);
  }

  toUtcDate(value) {
    return new Date(`${value}T00:00:00.000Z`);
  }
}
