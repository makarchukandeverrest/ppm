import { LightningElement, api, wire } from "lwc";
import { getRecord, getRecordNotifyChange } from "lightning/uiRecordApi";
import STAGE_FIELD from "@salesforce/schema/Contract_Bid__c.Stage__c";
import LOST_REASON_FIELD from "@salesforce/schema/Contract_Bid__c.Lost_Reason__c";

const CLOSED_LOST = "Closed - LOST";

export default class LostDealReasonPrompt extends LightningElement {
  @api recordId;

  showModal = false;
  flowKey = 0;

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [STAGE_FIELD, LOST_REASON_FIELD]
  })
  wiredBid({ data }) {
    if (!data || !data.fields) {
      return;
    }

    const stage =
      data.fields.Stage__c != null ? data.fields.Stage__c.value : null;
    const lostReason =
      data.fields.Lost_Reason__c != null
        ? data.fields.Lost_Reason__c.value
        : null;
    const needsReason = stage === CLOSED_LOST && !lostReason;

    if (needsReason && !this.showModal) {
      this.flowKey += 1;
      this.showModal = true;
    } else if (!needsReason && this.showModal) {
      this.showModal = false;
    }
  }

  get flowRuns() {
    return this.showModal ? [{ id: "flow-" + this.flowKey }] : [];
  }

  get inputVariables() {
    return [
      {
        name: "contractBidId",
        type: "String",
        value: this.recordId
      }
    ];
  }

  handleStatusChange(event) {
    const status = event.detail && event.detail.status;
    if (status === "FINISHED" || status === "FINISHED_SCREEN") {
      this.showModal = false;
      if (this.recordId) {
        getRecordNotifyChange([{ recordId: this.recordId }]);
      }
    }
  }
}
