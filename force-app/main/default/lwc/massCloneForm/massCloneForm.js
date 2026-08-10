import { LightningElement, api } from 'lwc';
import { TEMPLATE_RECORD_ID, reduceErrors } from 'c/massCloneUtils';

export default class MassCloneForm extends LightningElement {
    @api objectApiName;
    @api recordTypeId;
    @api selectedRecordId;
    @api selectedRecordLabel;
    @api cloneNamePreview;
    @api formSections = [];
    @api fieldValues = [];
    @api isReady = false;
    @api isLoading = false;
    @api layoutError;
    @api recordLoadError;
    @api isReviewing = false;

    get isTemplateSelected() {
        return this.selectedRecordId === TEMPLATE_RECORD_ID;
    }

    get showCloneNamePreview() {
        return Boolean(this.cloneNamePreview);
    }

    get layoutErrorMessage() {
        return this.extractMessage(this.layoutError);
    }

    get recordLoadErrorMessage() {
        return this.extractMessage(this.recordLoadError);
    }

    get isCompleteButNotReady() {
        return !this.isLoading && !this.isReady;
    }

    get formSectionsWithValues() {
        return this.formSections.map((section) => ({
            ...section,
            fields: section.fields.map((fieldName) => ({
                key: `${this.selectedRecordId}-${fieldName}`,
                name: fieldName,
                value: this.fieldValues[fieldName]
            }))
        }));
    }

    extractMessage(error) {
        return error?.body?.message || error?.message || null;
    }

    handleFieldChange(event) {
        const field = event.currentTarget;
        if (!field?.fieldName) {
            return;
        }

        this.dispatchEvent(
            new CustomEvent('fieldchange', {
                detail: {
                    fieldName: field.fieldName,
                    value: event.detail?.value ?? field.value
                }
            })
        );
    }

    handleApplyToAll() {
        this.dispatchEvent(new CustomEvent('applytoall'));
    }

    handleReview() {
        this.dispatchEvent(new CustomEvent('review'));
    }

    @api
    readFieldValues() {
        const fields = this.template.querySelectorAll('lightning-input-field');
        const values = {};

        fields.forEach((field) => {
            if (!field.fieldName) {
                return;
            }
            const normalizedValue = this.normalizeValue(field.value);
            if (normalizedValue !== undefined) {
                values[field.fieldName] = normalizedValue;
            }
        });

        return values;
    }

    normalizeValue(value) {
        if (value === undefined || value === null || value === '') {
            return undefined;
        }
        if (typeof value === 'object') {
            return value.id || value.value || undefined;
        }
        return value;
    }
}
