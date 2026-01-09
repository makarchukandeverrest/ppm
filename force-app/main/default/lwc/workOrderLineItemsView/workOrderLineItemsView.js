import { LightningElement, track, wire,api } from 'lwc';
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";

import WORK_ORDER_QB_NO from "@salesforce/schema/WorkOrder.Quick_Books_WO_No__c";
import WORK_ORDER_START_DATE from "@salesforce/schema/WorkOrder.StartDate";
import WORK_ORDER_CUSTOMER_NAME from "@salesforce/schema/WorkOrder.Account.Name";
import BILLING_STREET_FIELD from "@salesforce/schema/WorkOrder.Account.BillingStreet";
import BILLING_CITY_FIELD from "@salesforce/schema/WorkOrder.Account.BillingCity";
import BILLING_STATE_FIELD from "@salesforce/schema/WorkOrder.Account.BillingState";
import BILLING_POSTAL_CODE_FIELD from "@salesforce/schema/WorkOrder.Account.BillingPostalCode";
import BILLING_COUNTRY_FIELD from "@salesforce/schema/WorkOrder.Account.BillingCountry";

import getWorkOrderLineItems from "@salesforce/apex/WorkOrderLineItemsController.getWorkOrderLineItems";


export default class WorkOrderLineItemsView extends LightningElement {
    @api recordId;
    @track workOrderDetails = {};
    @track workOrderLineItems = [];

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
            BILLING_COUNTRY_FIELD
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
                startDate: getFieldValue(data, WORK_ORDER_START_DATE)
            }; 
        }
        
    }

        @wire(getWorkOrderLineItems, { workOrderId: "$recordId" })
        wiredLineItems(result) {
          const { error, data } = result;
          if (data) {
            this.workOrderLineItems = JSON.parse(JSON.stringify(data));
          } else if (error) {
            console.error("Error fetching line items:", error);
          }
        }

    get total() {
        return this.workOrderLineItems.reduce((sum, item) => sum + (item.Amount__c || 0), 0);
    }
}