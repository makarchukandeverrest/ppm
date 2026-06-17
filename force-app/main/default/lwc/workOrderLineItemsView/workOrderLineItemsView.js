import { LightningElement, track, wire, api } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import WORK_ORDER_QB_NO from "@salesforce/schema/WorkOrder.Quick_Books_WO_No__c";
import WORK_ORDER_START_DATE from "@salesforce/schema/WorkOrder.StartDate";
import WORK_ORDER_CUSTOMER_NAME from "@salesforce/schema/WorkOrder.Account.Name";
import BILLING_STREET_FIELD from "@salesforce/schema/WorkOrder.Account.BillingStreet";
import BILLING_CITY_FIELD from "@salesforce/schema/WorkOrder.Account.BillingCity";
import BILLING_STATE_FIELD from "@salesforce/schema/WorkOrder.Account.BillingState";
import BILLING_POSTAL_CODE_FIELD from "@salesforce/schema/WorkOrder.Account.BillingPostalCode";
import BILLING_COUNTRY_FIELD from "@salesforce/schema/WorkOrder.Account.BillingCountry";
import SERVICE_TEAM_MEMBER from "@salesforce/schema/WorkOrder.Service_Team_Member__c";
import SERVICE_TEAM_MEMBER_OBJECT from "@salesforce/schema/Service_Team_Member__c";
import SERVICE_TEAM_MEMBER_NAME from "@salesforce/schema/Service_Team_Member__c.Name";

import getWorkOrderLineItems from "@salesforce/apex/WorkOrderLineItemsController.getWorkOrderLineItems";
import saveServiceTeamMemberAssignments from "@salesforce/apex/WorkOrderLineItemsController.saveServiceTeamMemberAssignments";

function normalizeMemberId(value) {
  return value || null;
}

function mapLineItemRow(row) {
  const savedId = normalizeMemberId(row.Service_Team_Member__c);
  const savedLabel = row.Service_Team_Member__r?.Name ?? "";
  return {
    ...row,
    itemNameDisplay:
      row.Name?.toLowerCase() === row.Id?.slice(0, 15).toLowerCase()
        ? ""
        : row.Name ?? "",
    savedServiceTeamMemberId: savedId,
    draftServiceTeamMemberId: savedId || "",
    draftServiceTeamMemberLabel: savedLabel,
    serviceTeamMemberLabel: savedLabel,
    assignmentDisplayLabel: savedLabel || "—"
  };
}

export default class WorkOrderLineItemsView extends LightningElement {
  @api recordId;
  @track workOrderDetails = {};
  @track workOrderLineItems = [];
  @track editingRowIds = [];

  isSaving = false;
  wiredLineItemsResult;
  labelLookupRecordId;
  labelLookupRowId;
  showCreateMemberModal = false;
  createMemberForRowId;
  canCreateServiceTeamMember = false;

  serviceTeamMemberMatchingInfo = {
    primaryField: { fieldPath: "Name" },
    additionalFields: [{ fieldPath: "Email__c" }]
  };

  serviceTeamMemberDisplayInfo = {
    primaryField: "Name",
    additionalFields: ["Email__c"]
  };

  @wire(getObjectInfo, { objectApiName: SERVICE_TEAM_MEMBER_OBJECT })
  wiredServiceTeamMemberObjectInfo({ data }) {
    this.canCreateServiceTeamMember = data?.createable ?? false;
  }

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [
      WORK_ORDER_QB_NO,
      WORK_ORDER_START_DATE,
      WORK_ORDER_CUSTOMER_NAME,
      BILLING_STREET_FIELD,
      BILLING_CITY_FIELD,
      BILLING_STATE_FIELD,
      BILLING_POSTAL_CODE_FIELD,
      BILLING_COUNTRY_FIELD,
      SERVICE_TEAM_MEMBER
    ]
  })
  wiredProposal({ error, data }) {
    if (data) {
      this.workOrderDetails = {
        accountName: getFieldValue(data, WORK_ORDER_CUSTOMER_NAME),
        billingStreet: getFieldValue(data, BILLING_STREET_FIELD),
        billingCity: getFieldValue(data, BILLING_CITY_FIELD),
        billingState: getFieldValue(data, BILLING_STATE_FIELD),
        billingPostalCode: getFieldValue(data, BILLING_POSTAL_CODE_FIELD),
        billingCountry: getFieldValue(data, BILLING_COUNTRY_FIELD),
        startDate: getFieldValue(data, WORK_ORDER_START_DATE),
        serviceTeamMember: getFieldValue(data, SERVICE_TEAM_MEMBER)
      };
    } else if (error) {
      // optional: log header load error
    }
  }

  @wire(getRecord, {
    recordId: "$labelLookupRecordId",
    fields: [SERVICE_TEAM_MEMBER_NAME]
  })
  wiredServiceTeamMemberLabel({ data }) {
    if (!data || !this.labelLookupRowId) {
      return;
    }

    const rowId = this.labelLookupRowId;
    const name = getFieldValue(data, SERVICE_TEAM_MEMBER_NAME) || "—";
    this.workOrderLineItems = this.workOrderLineItems.map((item) =>
      item.Id === rowId ? { ...item, draftServiceTeamMemberLabel: name } : item
    );
    this.labelLookupRecordId = undefined;
    this.labelLookupRowId = undefined;
  }

  @wire(getWorkOrderLineItems, { workOrderId: "$recordId" })
  wiredLineItems(result) {
    this.wiredLineItemsResult = result;
    const { error, data } = result;
    if (data) {
      this.setLineItemsFromServer(data);
    } else if (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error loading line items",
          message: error?.body?.message || error?.message || "Unknown error",
          variant: "error"
        })
      );
    }
  }

  get lineItemsForDisplay() {
    const editingSet = new Set(this.editingRowIds);
    return this.workOrderLineItems.map((item) => {
      const isDirty =
        normalizeMemberId(item.draftServiceTeamMemberId) !==
        normalizeMemberId(item.savedServiceTeamMemberId);
      return {
        ...item,
        isEditingAssignment: editingSet.has(item.Id),
        draftServiceTeamMemberPickerValue:
          item.draftServiceTeamMemberId || undefined,
        assignmentDisplayLabel: isDirty
          ? item.draftServiceTeamMemberLabel || "—"
          : item.serviceTeamMemberLabel || "—"
      };
    });
  }

  get total() {
    return this.workOrderLineItems.reduce(
      (sum, item) => sum + (item.Amount__c || 0),
      0
    );
  }

  get hasPendingAssignmentChanges() {
    return this.workOrderLineItems.some(
      (item) =>
        normalizeMemberId(item.draftServiceTeamMemberId) !==
        normalizeMemberId(item.savedServiceTeamMemberId)
    );
  }

  get isSaveDisabled() {
    return !this.hasPendingAssignmentChanges || this.isSaving;
  }

  get isCancelDisabled() {
    return !this.hasPendingAssignmentChanges || this.isSaving;
  }

  setLineItemsFromServer(data, preserveEditingRows = false) {
    const raw = JSON.parse(JSON.stringify(data));
    this.workOrderLineItems = raw.map(mapLineItemRow);
    if (!preserveEditingRows) {
      this.editingRowIds = [];
    }
  }

  async reloadLineItemsFromServer() {
    if (this.wiredLineItemsResult) {
      await refreshApex(this.wiredLineItemsResult);
    }
  }

  handleBeginEditAssignment(event) {
    const rowId = event.currentTarget.dataset.id;
    if (!rowId) {
      return;
    }
    if (this.editingRowIds.includes(rowId)) {
      this.editingRowIds = this.editingRowIds.filter((id) => id !== rowId);
    } else {
      this.editingRowIds = [...this.editingRowIds, rowId];
    }
  }

  handleServiceTeamMemberDraftChange(event) {
    const rowId =
      event.currentTarget?.dataset?.id || event.target?.dataset?.id;
    const recordId = event.detail?.recordId || null;

    if (!rowId) {
      return;
    }

    this.applyDraftServiceTeamMember(rowId, recordId);
  }

  handleOpenCreateMemberModal(event) {
    const rowId = event.currentTarget?.dataset?.id;
    if (!rowId) {
      return;
    }
    this.createMemberForRowId = rowId;
    this.showCreateMemberModal = true;
  }

  handleCloseCreateMemberModal() {
    this.showCreateMemberModal = false;
    this.createMemberForRowId = null;
  }

  handleCreateMemberSuccess(event) {
    const newMemberId = event.detail?.id;
    const rowId = this.createMemberForRowId;

    this.handleCloseCreateMemberModal();

    if (newMemberId && rowId) {
      this.applyDraftServiceTeamMember(rowId, newMemberId);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: "Service Team Member created.",
          variant: "success"
        })
      );
    }
  }

  handleCreateMemberError(event) {
    const message =
      event.detail?.message || "Could not create Service Team Member.";
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Create failed",
        message,
        variant: "error"
      })
    );
  }

  applyDraftServiceTeamMember(rowId, recordId) {
    this.workOrderLineItems = this.workOrderLineItems.map((item) =>
      item.Id === rowId
        ? {
            ...item,
            draftServiceTeamMemberId: recordId || "",
            draftServiceTeamMemberLabel: recordId
              ? item.draftServiceTeamMemberLabel
              : "—"
          }
        : item
    );

    if (recordId) {
      this.labelLookupRowId = rowId;
      this.labelLookupRecordId = recordId;
    }
  }

  handleCancelAssignments() {
    this.workOrderLineItems = this.workOrderLineItems.map((item) => ({
      ...item,
      draftServiceTeamMemberId: item.savedServiceTeamMemberId || "",
      draftServiceTeamMemberLabel: item.serviceTeamMemberLabel || "",
      assignmentDisplayLabel: item.serviceTeamMemberLabel || "—"
    }));
    this.editingRowIds = [];
  }

  async handleSaveAssignments() {
    if (!this.hasPendingAssignmentChanges || this.isSaving) {
      return;
    }

    const pendingUpdates = this.workOrderLineItems
      .filter(
        (item) =>
          normalizeMemberId(item.draftServiceTeamMemberId) !==
          normalizeMemberId(item.savedServiceTeamMemberId)
      )
      .map((item) => ({
        lineItemId: item.Id,
        serviceTeamMemberId: normalizeMemberId(item.draftServiceTeamMemberId)
      }));

    if (pendingUpdates.length === 0) {
      return;
    }

    const lineItemIds = [];
    const serviceTeamMemberIds = [];
    pendingUpdates.forEach((item) => {
      lineItemIds.push(item.lineItemId);
      serviceTeamMemberIds.push(item.serviceTeamMemberId);
    });

    // eslint-disable-next-line no-console
    console.log(
      "[WorkOrderLineItemsView] save payload",
      JSON.stringify({ pendingCount: pendingUpdates.length, lineItemIds, serviceTeamMemberIds })
    );

    if (lineItemIds.length === 0 || serviceTeamMemberIds.length === 0) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Nothing to save",
          message:
            "No line item IDs were collected from the UI. Check that Service Team Member draft changes are being applied to rows.",
          variant: "error",
          mode: "sticky"
        })
      );
      return;
    }

    this.isSaving = true;
    try {
      const result = await saveServiceTeamMemberAssignments({
        workOrderId: this.recordId,
        lineItemIds,
        serviceTeamMemberIds
      });

      const savedCount = result?.successCount ?? 0;

      if (savedCount > 0) {
        this.editingRowIds = [];
        await this.reloadLineItemsFromServer();
      }

      if (result?.allSucceeded && savedCount > 0) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Success",
            message: `${savedCount} assignment(s) saved.`,
            variant: "success"
          })
        );
        return;
      }

      const errorDetail = (result?.errors || []).join(" ");

      if (savedCount > 0) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Partially saved",
            message: `${savedCount} saved, ${result.failureCount} failed. ${errorDetail}`,
            variant: "warning",
            mode: "sticky"
          })
        );
        return;
      }

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Save failed",
          message:
            errorDetail || "No assignments were saved.",
          variant: "error",
          mode: "sticky"
        })
      );
    } catch (error) {
      const message =
        error?.body?.message || error?.message || "Could not save assignments.";
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Save failed",
          message,
          variant: "error",
          mode: "sticky"
        })
      );
    } finally {
      this.isSaving = false;
    }
  }
}
