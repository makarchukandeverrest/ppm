import { LightningElement, api, wire, track } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import OPPORTUNITY_OBJECT from "@salesforce/schema/Opportunity";
import TAX_FIELD from "@salesforce/schema/Opportunity.Sales_Tax__c";
import ACCOUNT_NAME_FIELD from "@salesforce/schema/Opportunity.Account.Name";
import BILLING_STREET_FIELD from "@salesforce/schema/Opportunity.Account.BillingStreet";
import BILLING_CITY_FIELD from "@salesforce/schema/Opportunity.Account.BillingCity";
import BILLING_STATE_FIELD from "@salesforce/schema/Opportunity.Account.BillingState";
import BILLING_POSTAL_CODE_FIELD from "@salesforce/schema/Opportunity.Account.BillingPostalCode";
import BILLING_COUNTRY_FIELD from "@salesforce/schema/Opportunity.Account.BillingCountry";
import START_DATE_FIELD from "@salesforce/schema/Opportunity.Start_Date__c";
import ORDER_TAKEN_BY_FIELD from "@salesforce/schema/Opportunity.Order_Taken_By__c";
import DATE_ORDERED_FIELD from "@salesforce/schema/Opportunity.Date_Ordered__c";
import COMMENTS_FIELD from "@salesforce/schema/Opportunity.Comments__c";
import REFERENCE_NUMBER_FIELD from "@salesforce/schema/Opportunity.Reference_Number__c";
import WARRANTY_FIELD from "@salesforce/schema/Opportunity.Warranty__c";
import getProposalLineItems from "@salesforce/apex/ProposalLineItemController.getProposalLineItems";
import updateProposalLineItems from "@salesforce/apex/ProposalLineItemController.updateProposalLineItems";
import createProposalLineItems from "@salesforce/apex/ProposalLineItemController.createProposalLineItems";
import deleteProposalLineItems from "@salesforce/apex/ProposalLineItemController.deleteProposalLineItems";

export default class ProposalLineItems extends LightningElement {
  @api recordId;
  @track proposalLineItems = [];
  @track proposalDetails = {};
  @track originalLineItems = [];
  @track subtotal = 0;
  @track markup = 0;
  @track tax = 0;
  @track total = 0;
  @track hasEditingItem = false;
  @track selectedItems = [];
  @track isDeleteDisabled = true;
  @track warranty = "";
  wiredLineItemsResult;

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [
      ACCOUNT_NAME_FIELD,
      BILLING_STREET_FIELD,
      BILLING_CITY_FIELD,
      BILLING_STATE_FIELD,
      BILLING_POSTAL_CODE_FIELD,
      BILLING_COUNTRY_FIELD,
      START_DATE_FIELD,
      ORDER_TAKEN_BY_FIELD,
      DATE_ORDERED_FIELD,
      COMMENTS_FIELD,
      REFERENCE_NUMBER_FIELD,
      TAX_FIELD,
      WARRANTY_FIELD
    ]
  })
  wiredProposal({ error, data }) {
    if (data) {
      const salesTaxValue = getFieldValue(data, TAX_FIELD);
      const warrantyValue = getFieldValue(data, WARRANTY_FIELD);
      console.log("Raw Sales Tax value from Opportunity:", salesTaxValue);
      console.log("Raw Warranty value from Opportunity:", warrantyValue);
      console.log("Billing Street:", getFieldValue(data, BILLING_STREET_FIELD));
      console.log("Billing City:", getFieldValue(data, BILLING_CITY_FIELD));
      console.log("Billing State:", getFieldValue(data, BILLING_STATE_FIELD));
      console.log(
        "Billing Postal Code:",
        getFieldValue(data, BILLING_POSTAL_CODE_FIELD)
      );
      console.log(
        "Billing Country:",
        getFieldValue(data, BILLING_COUNTRY_FIELD)
      );

      this.proposalDetails = {
        accountName: getFieldValue(data, ACCOUNT_NAME_FIELD),
        billingStreet: getFieldValue(data, BILLING_STREET_FIELD),
        billingCity: getFieldValue(data, BILLING_CITY_FIELD),
        billingState: getFieldValue(data, BILLING_STATE_FIELD),
        billingPostalCode: getFieldValue(data, BILLING_POSTAL_CODE_FIELD),
        billingCountry: getFieldValue(data, BILLING_COUNTRY_FIELD),
        startDate: getFieldValue(data, START_DATE_FIELD),
        orderTakenBy: getFieldValue(data, ORDER_TAKEN_BY_FIELD),
        dateOrdered: getFieldValue(data, DATE_ORDERED_FIELD),
        comments: getFieldValue(data, COMMENTS_FIELD),
        referenceNumber: getFieldValue(data, REFERENCE_NUMBER_FIELD),
        salesTax:
          salesTaxValue !== undefined && salesTaxValue !== null
            ? salesTaxValue
            : this.tax || 0,
        warranty:
          warrantyValue !== undefined && warrantyValue !== null
            ? warrantyValue
            : this.warranty || ""
      };
      this.tax = this.proposalDetails.salesTax;
      this.warranty = this.proposalDetails.warranty;
      console.log("Final Tax set to:", this.tax);
      console.log("Final Warranty set to:", this.warranty);
      this.calculateSummary();
    } else if (error) {
      console.error("Error in wiredProposal:", error);
    }
  }

  @wire(getProposalLineItems, { proposalId: "$recordId" })
  wiredLineItems(result) {
    this.wiredLineItemsResult = result;
    const { error, data } = result;
    if (data) {
      this.originalLineItems = JSON.parse(JSON.stringify(data));
      this.proposalLineItems = data.map((item) => ({
        ...item,
        Total__c: item.Quantity__c * item.Unit_Cost__c,
        isEditing: false
      }));
      this.updateEditingStatus();
      this.calculateSummary();
      this.updateDeleteButtonState();
    } else if (error) {
      console.error("Error fetching line items:", error);
    }
  }

  handleCellClick(event) {
    const { id, field } = event.currentTarget.dataset;
    if (field !== "Total__c") {
      const item = this.proposalLineItems.find((i) => i.Id === id);
      if (item) {
        item.isEditing = true;
        this.proposalLineItems = [...this.proposalLineItems];
        this.updateEditingStatus();
      }
    }
  }

  handleDescriptionChange(event) {
    const { id, field } = event.target.dataset;
    const value = event.target.value;
    this.updateLineItem(id, field, value);
    this.calculateSummary();
  }

  handleQuantityChange(event) {
    const { id, field } = event.target.dataset;
    const value = parseInt(event.target.value, 10) || 0;
    this.updateLineItem(id, field, value);
    this.updateTotal(id);
    this.calculateSummary();
  }

  handleUnitCostChange(event) {
    const { id, field } = event.target.dataset;
    const value = parseFloat(event.target.value) || 0.0;
    this.updateLineItem(id, field, value);
    this.updateTotal(id);
    this.calculateSummary();
  }

  handleTaxChange(event) {
    const { id, field } = event.target.dataset;
    const value = event.target.value;
    this.updateLineItem(id, field, value);
    this.calculateSummary();
  }

  updateLineItem(id, field, value) {
    const item = this.proposalLineItems.find((i) => i.Id === id);
    if (item) {
      item[field] = value;
      this.proposalLineItems = [...this.proposalLineItems];
    }
  }

  updateTotal(id) {
    const item = this.proposalLineItems.find((i) => i.Id === id);
    if (item) {
      item.Total__c = item.Quantity__c * item.Unit_Cost__c;
      this.proposalLineItems = [...this.proposalLineItems];
    }
  }

  calculateSummary() {
    this.subtotal = this.proposalLineItems.reduce(
      (sum, item) => sum + (item.Total__c || 0),
      0
    );
    this.markup = 0;
    this.total = this.subtotal + this.tax;
  }

  updateEditingStatus() {
    this.hasEditingItem = this.proposalLineItems.some((item) => item.isEditing);
  }

  handleAddNew() {
    const newItem = {
      Description__c: "",
      Quantity__c: 0,
      Unit_Cost__c: 0.0,
      Total__c: 0,
      Tax__c: "",
      isEditing: true,
      isNew: true
    };
    this.proposalLineItems = [...this.proposalLineItems, newItem];
    this.updateEditingStatus();
    this.calculateSummary();
    this.updateDeleteButtonState();
  }

  handleCancel() {
    if (this.originalLineItems.length > 0) {
      this.proposalLineItems = this.originalLineItems
        .map((item) => ({
          ...item,
          Total__c: item.Quantity__c * item.Unit_Cost__c,
          isEditing: false
        }))
        .filter((item) => !item.isNew);
      this.calculateSummary();
      this.updateEditingStatus();
      this.selectedItems = [];
      this.updateDeleteButtonState();
      console.log(
        "Cancel triggered, reverted to original values and removed new items"
      );
    } else {
      console.log("No original data to revert to");
    }
  }

  handleSave() {
    const recordsToUpdate = this.proposalLineItems
      .filter((item) => !item.isNew)
      .map((item) => ({
        Id: item.Id,
        Description__c: item.Description__c,
        Quantity__c: item.Quantity__c,
        Unit_Cost__c: item.Unit_Cost__c,
        Total__c: item.Total__c,
        Tax__c: item.Tax__c
      }));

    const newItems = this.proposalLineItems
      .filter((item) => item.isNew)
      .map((item) => ({
        Description__c: item.Description__c,
        Quantity__c: item.Quantity__c,
        Unit_Cost__c: item.Unit_Cost__c,
        Tax__c: item.Tax__c,
        Deal__c: this.recordId
      }));

    Promise.all([
      updateProposalLineItems({ items: recordsToUpdate }),
      newItems.length > 0
        ? createProposalLineItems({ items: newItems })
        : Promise.resolve()
    ])
      .then(() => {
        return refreshApex(this.wiredLineItemsResult);
      })
      .then(() => {
        this.calculateSummary();
        this.updateEditingStatus();
        this.selectedItems = [];
        this.updateDeleteButtonState();
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Success",
            message: "Proposal Line Items updated/created",
            variant: "success"
          })
        );
      })
      .catch((error) => {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Error",
            message:
              "Error updating/creating records: " +
              (error.body ? error.body.message : error.message),
            variant: "error"
          })
        );
        console.error(error);
      });
  }

  handleSelectAll(event) {
    const isChecked = event.target.checked;
    this.selectedItems = isChecked
      ? this.proposalLineItems.map((item) => item.Id)
      : [];
    this.proposalLineItems = this.proposalLineItems.map((item) => ({
      ...item,
      isSelected: isChecked
    }));
    this.updateDeleteButtonState();
  }

  handleCheckboxChange(event) {
    const itemId = event.target.dataset.id;
    const isChecked = event.target.checked;
    if (isChecked) {
      this.selectedItems = [...this.selectedItems, itemId];
    } else {
      this.selectedItems = this.selectedItems.filter((id) => id !== itemId);
    }
    const item = this.proposalLineItems.find((i) => i.Id === itemId);
    if (item) {
      item.isSelected = isChecked;
      this.proposalLineItems = [...this.proposalLineItems];
    }
    this.updateDeleteButtonState();
  }

  handleDelete() {
    if (this.selectedItems.length === 0) return;

    const itemsToDelete = this.proposalLineItems.filter(
      (item) => this.selectedItems.includes(item.Id) && !item.isNew
    );
    const deleteIds = itemsToDelete.map((item) => item.Id);

    if (deleteIds.length > 0) {
      deleteProposalLineItems({ ids: deleteIds })
        .then(() => {
          return refreshApex(this.wiredLineItemsResult);
        })
        .then(() => {
          this.calculateSummary();
          this.updateEditingStatus();
          this.selectedItems = [];
          this.updateDeleteButtonState();
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Success",
              message: "Selected items deleted",
              variant: "success"
            })
          );
        })
        .catch((error) => {
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Error",
              message:
                "Error deleting records: " +
                (error.body ? error.body.message : error.message),
              variant: "error"
            })
          );
          console.error(error);
        });
    } else {
      this.proposalLineItems = this.proposalLineItems.filter(
        (item) => !this.selectedItems.includes(item.Id)
      );
      this.calculateSummary();
      this.updateEditingStatus();
      this.selectedItems = [];
      this.updateDeleteButtonState();
    }
  }

  updateDeleteButtonState() {
    this.isDeleteDisabled = this.selectedItems.length === 0;
  }
}