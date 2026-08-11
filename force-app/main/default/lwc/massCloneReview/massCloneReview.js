import { LightningElement, api } from 'lwc';
import { FlowNavigationNextEvent } from 'lightning/flowSupport';
import {
    buildReviewRows,
    buildReviewSummary
} from 'c/massCloneUtils';

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
            this.rows = buildReviewRows(this._clonePayloadJson, this.objectApiName);
            this.parseError = undefined;
        } catch (error) {
            this.rows = [];
            this.parseError = error.message || 'Unable to parse clone payload.';
        }
    }

    get count() {
        return this.rows.length;
    }

    get hasRows() {
        return this.count > 0;
    }

    get summaryText() {
        return buildReviewSummary(this.count);
    }

    handleCreateRecords() {
        this.dispatchEvent(new CustomEvent('create'));
    }
}
