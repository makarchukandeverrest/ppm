import { LightningElement, api } from 'lwc';
import { FlowNavigationNextEvent } from 'lightning/flowSupport';

const PREVIEW_FIELDS = ['Name', 'Customer__c', 'Contract_Year__c', 'Stage__c', 'Due_Date__c'];

export default class MassCloneReview extends LightningElement {
    _clonePayloadJson;
    @api objectApiName;
    @api cardTitle = 'Review Records to Create';

    parseError;
    rows = [];

    @api
    get clonePayloadJson() {
        return this._clonePayloadJson;
    }

    set clonePayloadJson(value) {
        this._clonePayloadJson = value;
        this.parsePayload();
    }

    parsePayload() {
        if (!this._clonePayloadJson) {
            this.rows = [];
            this.parseError = undefined;
            return;
        }

        try {
            const payloads = JSON.parse(this._clonePayloadJson);
            if (!Array.isArray(payloads)) {
                throw new Error('Payload must be a JSON array.');
            }

            this.rows = payloads.map((payload, index) => {
                const fields = payload.fields || {};
                const previewValues = PREVIEW_FIELDS.filter((fieldName) =>
                    Object.prototype.hasOwnProperty.call(fields, fieldName)
                ).map((fieldName) => ({
                    key: `${index}-${fieldName}`,
                    label: fieldName,
                    value: this.formatValue(fields[fieldName])
                }));

                return {
                    id: payload.sourceId || `row-${index}`,
                    rowNumber: index + 1,
                    sourceName: payload.sourceName || payload.sourceId || `Record ${index + 1}`,
                    newName: fields.Name || '—',
                    fieldCount: Object.keys(fields).length,
                    previewValues,
                    hasPreviewValues: previewValues.length > 0
                };
            });
            this.parseError = undefined;
        } catch (error) {
            this.rows = [];
            this.parseError = error.message || 'Unable to parse clone payload.';
        }
    }

    formatValue(value) {
        if (value === null || value === undefined || value === '') {
            return '—';
        }

        if (typeof value === 'object') {
            return JSON.stringify(value);
        }

        return String(value);
    }

    get count() {
        return this.rows.length;
    }

    get hasRows() {
        return this.count > 0;
    }

    get summaryText() {
        return `${this.count} record(s) ready to create.`;
    }

    handleCreateRecords() {
        this.dispatchEvent(new FlowNavigationNextEvent());
    }
}
