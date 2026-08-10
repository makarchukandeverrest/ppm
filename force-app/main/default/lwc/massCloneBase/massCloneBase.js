import { LightningElement, api, wire, track } from 'lwc';
import { getRecordCreateDefaults } from 'lightning/uiRecordApi';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getRecordFieldValuesJson from '@salesforce/apex/MassCloneController.getRecordFieldValuesJson';
import createCloneRecords from '@salesforce/apex/MassCloneController.createCloneRecords';
import {
    SYSTEM_FIELDS,
    TEMPLATE_RECORD_ID,
    BULK_APPLY_EXCLUDED_FIELDS,
    MAX_FIELDS_PER_LOAD,
    STEP_EDIT,
    STEP_REVIEW,
    buildReviewRows,
    buildReviewSummary,
    reduceErrors,
    getCloneRule
} from 'c/massCloneUtils';

export default class MassCloneBase extends LightningElement {
    _recordIds = [];
    @api recordNames = [];
    @api objectApiName;
    _fieldNames = [];
    @api recordTypeId;
    // Deprecated: kept only for backward compatibility with existing Flow versions.
    @api layoutType = 'Full';
    @api layoutMode = 'Edit';
    @api cardTitle = 'Selected Records';
    @api iconName = 'standard:record';
    @api formFieldNames = [];
    @api clonePayloadJson = '';
    @api createSuccessCount = 0;
    @api createFailureCount = 0;
    @api createErrorMessage = '';
    @api createdRecordIds = [];

    formSections = [];
    objectInfo;
    resolvedFieldNames = [];
    layoutError;
    layoutFetchComplete = false;
    defaultRecordTypeId;
    selectedRecordId = TEMPLATE_RECORD_ID;
    sourceRecord;
    recordLoadError;
    isRecordLoading = false;
    currentStep = STEP_EDIT;
    isPreparingReview = false;
    isCreatingRecords = false;
    createCompleted = false;
    panelStatusMessage = '';
    panelStatusVariant = '';

    @track drafts = {};
    @track lastBulkValues = null;
    @track sourceSnapshots = {};
    @track draftNames = {};
    _reviewRows = [];

    @api
    get recordIds() {
        return this._recordIds;
    }

    set recordIds(value) {
        this._recordIds = Array.isArray(value) ? [...value] : [];
        this.selectedRecordId = TEMPLATE_RECORD_ID;
        this.sourceRecord = undefined;
        this.recordLoadError = undefined;
        this.loadAllSourceSnapshots();
    }

    connectedCallback() {
        this.loadAllSourceSnapshots();
    }

    @api
    get fieldNames() {
        return this._fieldNames;
    }

    set fieldNames(value) {
        this._fieldNames = Array.isArray(value) ? [...value] : [];
        this.applyExplicitFieldNames();
    }

    get cloneRule() {
        return getCloneRule(this.objectApiName);
    }

    @wire(getRecordCreateDefaults, {
        objectApiName: '$objectApiName',
        recordTypeId: '$recordTypeId'
    })
    wiredCreateDefaults({ data, error }) {
        if (this.hasExplicitFieldNames) {
            return;
        }

        this.layoutFetchComplete = true;

        if (data) {
            this.objectInfo = data.objectInfos?.[this.objectApiName];
            this.defaultRecordTypeId = data.recordTypeId;
            this.formSections = this.extractSectionsFromLayout(data.layout);
            this.resolvedFieldNames = this.flattenSectionFields(this.formSections);
            this.layoutError = undefined;
            this.publishFormFieldNames();
        } else if (error) {
            this.objectInfo = undefined;
            this.defaultRecordTypeId = undefined;
            this.formSections = [];
            this.resolvedFieldNames = [];
            this.layoutError = error;
            this.publishFormFieldNames();
        } else {
            this.formSections = [];
            this.resolvedFieldNames = [];
        }
    }

    get effectiveRecordTypeId() {
        return this.recordTypeId || this.defaultRecordTypeId;
    }

    get hasExplicitFieldNames() {
        return this._fieldNames.length > 0;
    }

    applyExplicitFieldNames() {
        if (!this.hasExplicitFieldNames) {
            return;
        }

        this.layoutFetchComplete = true;
        this.layoutError = undefined;
        this.resolvedFieldNames = [...new Set(this._fieldNames)];
        this.formSections = [
            {
                id: 'explicit-fields',
                heading: null,
                fields: this.resolvedFieldNames
            }
        ];
        this.publishFormFieldNames();
    }

    extractSectionsFromLayout(layout) {
        if (!layout?.sections?.length) {
            return [];
        }

        const seenFields = new Set();

        return layout.sections
            .map((section, index) => ({
                id: section.heading || `section-${index}`,
                heading: section.heading,
                fields: this.extractFieldsFromSection(section).filter((fieldName) => {
                    if (seenFields.has(fieldName)) {
                        return false;
                    }
                    seenFields.add(fieldName);
                    return true;
                })
            }))
            .filter((section) => section.fields.length > 0);
    }

    extractFieldsFromSection(section) {
        const fields = [];

        section.layoutRows?.forEach((row) => {
            row.layoutItems?.forEach((item) => {
                item.layoutComponents?.forEach((component) => {
                    if (
                        component.componentType === 'Field' &&
                        component.apiName &&
                        !SYSTEM_FIELDS.has(component.apiName)
                    ) {
                        fields.push(component.apiName);
                    }
                });
            });
        });

        return [...new Set(fields)];
    }

    flattenSectionFields(sections) {
        const fields = [];
        sections.forEach((section) => {
            section.fields.forEach((fieldName) => {
                if (!fields.includes(fieldName)) {
                    fields.push(fieldName);
                }
            });
        });
        return fields;
    }

    publishFormFieldNames() {
        this.formFieldNames = [...this.resolvedFieldNames];
        this.dispatchEvent(
            new FlowAttributeChangeEvent('formFieldNames', this.formFieldNames)
        );
    }

    get recordFields() {
        if (this.isTemplateSelected || !this.selectedRecordId || !this.objectApiName || !this.resolvedFieldNames.length) {
            return undefined;
        }

        const fields = [...this.resolvedFieldNames];
        this.cloneRule.fieldsToLoad.forEach((fieldName) => {
            if (!fields.includes(fieldName)) {
                fields.push(fieldName);
            }
        });

        return fields.map((fieldName) => `${this.objectApiName}.${fieldName}`);
    }

    @wire(getRecord, { recordId: '$selectedRecordId', fields: '$recordFields' })
    wiredSourceRecord({ data, error }) {
        if (this.isTemplateSelected || !this.selectedRecordId || !this.recordFields) {
            return;
        }

        this.isRecordLoading = false;

        if (data) {
            this.sourceRecord = data;
            this.recordLoadError = undefined;
            this.sourceSnapshots = {
                ...this.sourceSnapshots,
                [this.selectedRecordId]: this.buildSourceSnapshot(data)
            };
            this.ensureDraftFromSource(this.selectedRecordId, data);
        } else if (error) {
            this.sourceRecord = undefined;
            this.recordLoadError = error;
        }
    }

    buildSourceSnapshot(sourceRecord) {
        if (!sourceRecord || !this.objectApiName) {
            return {};
        }

        return {
            Name: getFieldValue(sourceRecord, `${this.objectApiName}.Name`)
        };
    }

    ensureDraftFromSource(recordId, sourceRecord) {
        if (this.drafts[recordId]) {
            return;
        }

        const sourceValues = {};
        this.resolvedFieldNames.forEach((fieldName) => {
            sourceValues[fieldName] = getFieldValue(sourceRecord, `${this.objectApiName}.${fieldName}`);
        });
        this.cloneRule.fieldsToLoad.forEach((fieldName) => {
            sourceValues[fieldName] = getFieldValue(sourceRecord, `${this.objectApiName}.${fieldName}`);
        });

        const draft = { ...sourceValues, __sourceName: sourceValues.Name };
        const merged = this.applyBulkValuesToDraft(draft);
        this.setDraft(recordId, merged);
        this.refreshDraftNames();
    }

    get isTemplateSelected() {
        return this.selectedRecordId === TEMPLATE_RECORD_ID;
    }

    get isRealRecordSelected() {
        return Boolean(this.selectedRecordId) && !this.isTemplateSelected;
    }

    get count() {
        return this._recordIds.length;
    }

    get hasRecords() {
        return this.count > 0;
    }

    get showForm() {
        return Boolean(this.objectApiName);
    }

    get isLayoutReady() {
        return (
            this.showForm &&
            this.layoutFetchComplete &&
            this.resolvedFieldNames.length > 0 &&
            Boolean(this.selectedRecordId) &&
            (this.isTemplateSelected || Boolean(this.sourceRecord))
        );
    }

    get isLayoutLoading() {
        return (
            this.showForm &&
            (!this.layoutFetchComplete || (this.isRealRecordSelected && this.isRecordLoading))
        );
    }

    get isEditStep() {
        return this.currentStep === STEP_EDIT;
    }

    get isReviewStep() {
        return this.currentStep === STEP_REVIEW;
    }

    get selectedRecordLabel() {
        if (this.isTemplateSelected) {
            return '';
        }
        const index = this._recordIds.indexOf(this.selectedRecordId);
        if (index === -1) {
            return '';
        }
        return this.recordNames[index] || this.selectedRecordId;
    }

    get cloneNamePreview() {
        if (!this.isRealRecordSelected) {
            return '';
        }

        const draft = this.drafts[this.selectedRecordId];
        const sourceValues = this.sourceRecord
            ? this.buildSourceValuesFromRecord(this.sourceRecord)
            : {};

        return this.cloneRule.deriveName(draft, sourceValues);
    }

    buildSourceValuesFromRecord(sourceRecord) {
        if (!sourceRecord || !this.objectApiName) {
            return {};
        }

        const values = { Name: getFieldValue(sourceRecord, `${this.objectApiName}.Name`) };
        this.cloneRule.fieldsToLoad.forEach((fieldName) => {
            values[fieldName] = getFieldValue(sourceRecord, `${this.objectApiName}.${fieldName}`);
        });
        return values;
    }

    get formFieldValues() {
        const values = {};
        this.resolvedFieldNames.forEach((fieldName) => {
            values[fieldName] = this.getFieldValueForForm(fieldName);
        });
        return values;
    }

    getFieldValueForForm(fieldName) {
        const draftValue = this.drafts[this.selectedRecordId]?.[fieldName];
        if (draftValue !== undefined) {
            return draftValue;
        }

        if (this.isTemplateSelected) {
            return undefined;
        }

        return this.sourceRecord
            ? getFieldValue(this.sourceRecord, `${this.objectApiName}.${fieldName}`)
            : undefined;
    }

    async loadAllSourceSnapshots() {
        if (!this.objectApiName || !this._recordIds.length) {
            return;
        }

        const fieldNames = this.getSourceSnapshotFieldNames();
        if (!fieldNames.length) {
            return;
        }

        try {
            const valuesJson = await getRecordFieldValuesJson({
                objectApiName: this.objectApiName,
                recordIds: [...this._recordIds],
                fieldNames
            });
            const valuesByRecordId = JSON.parse(valuesJson || '{}');

            const newSnapshots = { ...this.sourceSnapshots };
            this._recordIds.forEach((recordId) => {
                const sourceValues = valuesByRecordId[recordId] || {};
                newSnapshots[recordId] = sourceValues;
            });
            this.sourceSnapshots = newSnapshots;
            this.refreshDraftNames();
        } catch (error) {
            // Source snapshots are a best-effort optimization for name previews.
            // Failure here should not block the user from continuing.
        }
    }

    getSourceSnapshotFieldNames() {
        return [...new Set(['Name', ...this.cloneRule.fieldsToLoad])];
    }

    refreshDraftNames() {
        const names = {};
        this._recordIds.forEach((recordId) => {
            const draft = this.drafts[recordId];
            const sourceValues = this.sourceSnapshots[recordId] || {};
            const derivedName = this.cloneRule.deriveName(draft, sourceValues);
            if (derivedName) {
                names[recordId] = derivedName;
            }
        });
        this.draftNames = names;
    }

    get recordLoadErrorMessage() {
        return this.recordLoadError?.body?.message || this.recordLoadError?.message || null;
    }

    get layoutErrorMessage() {
        return this.layoutError?.body?.message || this.layoutError?.message || null;
    }

    get reviewRows() {
        return this._reviewRows;
    }

    get hasReviewRows() {
        return this._reviewRows.length > 0;
    }

    get reviewSummaryText() {
        return buildReviewSummary(this._reviewRows.length);
    }

    refreshReviewRows() {
        this._reviewRows = buildReviewRows(this.clonePayloadJson, this.objectApiName);
    }

    get isCreateDisabled() {
        return this.isCreatingRecords || this.createCompleted;
    }

    get showPanelStatus() {
        return Boolean(this.panelStatusMessage);
    }

    get panelStatusClass() {
        const base = 'panel-status';
        if (this.panelStatusVariant === 'success') {
            return `${base} panel-status_success`;
        }
        if (this.panelStatusVariant === 'warning') {
            return `${base} panel-status_warning`;
        }
        if (this.panelStatusVariant === 'error') {
            return `${base} panel-status_error`;
        }
        return base;
    }

    getDraftFieldNamesForLoad() {
        const seen = new Set();
        const fieldNames = [];

        const addField = (fieldName) => {
            if (!fieldName || seen.has(fieldName) || SYSTEM_FIELDS.has(fieldName)) {
                return;
            }
            if (this.objectInfo) {
                const fieldDef = this.objectInfo.fields[fieldName];
                if (fieldDef && !fieldDef.createable && fieldName !== 'Name') {
                    return;
                }
            }
            seen.add(fieldName);
            fieldNames.push(fieldName);
        };

        this.cloneRule.previewFields.forEach(addField);
        this.cloneRule.fieldsToLoad.forEach(addField);
        this.resolvedFieldNames.forEach(addField);

        return fieldNames.slice(0, MAX_FIELDS_PER_LOAD);
    }

    getRequiredFieldNamesForCreate() {
        return [...new Set([...this.cloneRule.requiredFields])];
    }

    normalizeFieldValue(value) {
        if (value === undefined || value === null || value === '') {
            return undefined;
        }
        if (typeof value === 'object') {
            return value.id || value.value || undefined;
        }
        return value;
    }

    buildPayloadFields(draft) {
        const fields = {};
        if (!draft) {
            return fields;
        }

        this.resolvedFieldNames.forEach((fieldName) => {
            if (SYSTEM_FIELDS.has(fieldName)) {
                return;
            }
            const fieldDef = this.objectInfo?.fields?.[fieldName];
            if (fieldDef && !fieldDef.createable) {
                return;
            }
            const value = this.normalizeFieldValue(draft[fieldName]);
            if (value !== undefined) {
                fields[fieldName] = value;
            }
        });

        if (!fields.Name && draft.Name !== undefined) {
            const nameValue = this.normalizeFieldValue(draft.Name);
            if (nameValue !== undefined) {
                fields.Name = nameValue;
            }
        }

        if (this.effectiveRecordTypeId) {
            fields.RecordTypeId = this.effectiveRecordTypeId;
        }

        this.getRequiredFieldNamesForCreate().forEach((fieldName) => {
            if (Object.prototype.hasOwnProperty.call(fields, fieldName)) {
                return;
            }
            const value = this.normalizeFieldValue(draft[fieldName]);
            if (value !== undefined) {
                fields[fieldName] = value;
            }
        });

        return fields;
    }

    publishClonePayload() {
        const payloads = this._recordIds.map((sourceId, index) => ({
            sourceId,
            sourceName: this.recordNames[index] || sourceId,
            fields: this.buildPayloadFields(this.drafts[sourceId])
        }));

        this.clonePayloadJson = JSON.stringify(payloads);
        this.dispatchEvent(
            new FlowAttributeChangeEvent('clonePayloadJson', this.clonePayloadJson)
        );
    }

    publishCreateResult(result) {
        this.createSuccessCount = result?.successCount ?? 0;
        this.createFailureCount = result?.failureCount ?? 0;
        this.createErrorMessage = result?.errorMessage || '';
        this.createdRecordIds = result?.createdRecordIds || [];

        this.dispatchEvent(
            new FlowAttributeChangeEvent('createSuccessCount', this.createSuccessCount)
        );
        this.dispatchEvent(
            new FlowAttributeChangeEvent('createFailureCount', this.createFailureCount)
        );
        this.dispatchEvent(
            new FlowAttributeChangeEvent('createErrorMessage', this.createErrorMessage)
        );
        this.dispatchEvent(
            new FlowAttributeChangeEvent('createdRecordIds', this.createdRecordIds)
        );
    }

    handleRecordSelect(event) {
        const recordId = event.detail.recordId;
        if (!recordId || recordId === this.selectedRecordId) {
            return;
        }

        this.saveCurrentDraftFromForm();
        this.selectedRecordId = recordId;
        this.sourceRecord = undefined;
        this.recordLoadError = undefined;
        this.isRecordLoading = !this.isTemplateSelected;
    }

    handleFieldChange(event) {
        const { fieldName, value } = event.detail;
        if (!fieldName || !this.selectedRecordId) {
            return;
        }

        this.setDraftValue(this.selectedRecordId, fieldName, value);

        if (this.cloneRule.specialFields.includes(fieldName)) {
            this.deriveNameForRecord(this.selectedRecordId);
        }

        this.refreshDraftNames();
    }

    deriveNameForRecord(recordId) {
        const draft = this.drafts[recordId];
        const sourceValues = this.sourceSnapshots[recordId] || {};
        const derivedName = this.cloneRule.deriveName(draft, sourceValues);

        if (derivedName) {
            this.setDraftValue(recordId, 'Name', derivedName);
        }
    }

    handleApplyToAll() {
        this.saveCurrentDraftFromForm();
        this.ensureTemplate();
        const sharedValues = this.extractNonEmptyTemplateValues(
            this.drafts[TEMPLATE_RECORD_ID]
        );

        if (!Object.keys(sharedValues).length) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Nothing to apply',
                    message: 'Fill in at least one common field on the template first.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.applyBulkValues(this._recordIds, sharedValues);

        this._recordIds.forEach((recordId) => {
            this.deriveNameForRecord(recordId);
        });

        this.refreshDraftNames();

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Applied to all',
                message: `Shared values applied to ${this._recordIds.length} record(s).`,
                variant: 'success'
            })
        );
    }

    saveCurrentDraftFromForm() {
        const form = this.template.querySelector('c-mass-clone-form');
        if (!form) {
            return;
        }
        const values = form.readFieldValues();
        Object.entries(values).forEach(([fieldName, value]) => {
            this.setDraftValue(this.selectedRecordId, fieldName, value);
        });
        this.refreshDraftNames();
    }

    setDraftValue(recordId, fieldName, value) {
        this.drafts = {
            ...this.drafts,
            [recordId]: { ...(this.drafts[recordId] || {}), [fieldName]: value }
        };
    }

    setDraft(recordId, draft) {
        this.drafts = {
            ...this.drafts,
            [recordId]: { ...draft }
        };
    }

    ensureTemplate() {
        if (!this.drafts[TEMPLATE_RECORD_ID]) {
            this.drafts = {
                ...this.drafts,
                [TEMPLATE_RECORD_ID]: {}
            };
        }
    }

    applyBulkValues(recordIds, sharedValues) {
        this.lastBulkValues = { ...sharedValues };
        const newDrafts = { ...this.drafts };
        recordIds.forEach((recordId) => {
            newDrafts[recordId] = { ...(newDrafts[recordId] || {}), ...sharedValues };
        });
        this.drafts = newDrafts;
    }

    applyBulkValuesToDraft(draft) {
        if (!this.lastBulkValues) {
            return draft;
        }

        const merged = { ...draft };
        Object.entries(this.lastBulkValues).forEach(([fieldName, value]) => {
            const currentValue = merged[fieldName];
            if (currentValue === undefined || currentValue === null || currentValue === '') {
                merged[fieldName] = value;
            }
        });

        return merged;
    }

    extractNonEmptyTemplateValues(templateDraft) {
        if (!templateDraft) {
            return {};
        }

        const values = {};
        Object.entries(templateDraft).forEach(([fieldName, value]) => {
            if (!BULK_APPLY_EXCLUDED_FIELDS.has(fieldName) && value !== undefined && value !== null && value !== '') {
                values[fieldName] = value;
            }
        });

        return values;
    }

    async handleReview() {
        this.isPreparingReview = true;
        this.panelStatusMessage = '';
        this.panelStatusVariant = '';

        try {
            await this.ensureAllDraftsReady();
            this.publishClonePayload();
            this.refreshReviewRows();

            if (!this.hasReviewRows) {
                this.panelStatusMessage = 'No clone field values were found for the selected records.';
                this.panelStatusVariant = 'warning';
                return;
            }

            this.currentStep = STEP_REVIEW;
        } catch (error) {
            this.panelStatusMessage = reduceErrors(error);
            this.panelStatusVariant = 'error';
        } finally {
            this.isPreparingReview = false;
        }
    }

    handleBackToEdit() {
        this.currentStep = STEP_EDIT;
        this.panelStatusMessage = '';
        this.panelStatusVariant = '';
    }

    async handleCreateRecords() {
        if (this.isCreatingRecords) {
            return;
        }

        this.isCreatingRecords = true;
        this.panelStatusMessage = '';
        this.panelStatusVariant = '';

        try {
            if (!this.objectInfo) {
                throw new Error('Object metadata is still loading. Please try again.');
            }

            this.saveCurrentDraftFromForm();
            await this.ensureRequiredSourceFields();
            this.publishClonePayload();
            this.refreshReviewRows();

            if (!this.hasReviewRows) {
                this.panelStatusMessage = 'No clone field values were found for the selected records.';
                this.panelStatusVariant = 'warning';
                return;
            }

            const result = await createCloneRecords({
                objectApiName: this.objectApiName,
                clonePayloadJson: this.clonePayloadJson
            });

            this.publishCreateResult(result);
            this.setPanelStatusFromResult(result);
        } catch (error) {
            this.panelStatusMessage = reduceErrors(error);
            this.panelStatusVariant = 'error';
        } finally {
            this.isCreatingRecords = false;
        }
    }

    setPanelStatusFromResult(result) {
        const successCount = result?.successCount ?? 0;
        const failureCount = result?.failureCount ?? 0;
        const errorMessage = result?.errorMessage || '';

        if (successCount > 0 && !failureCount) {
            this.createCompleted = true;
            this.panelStatusMessage = `Successfully created ${successCount} record(s). Click Close to exit.`;
            this.panelStatusVariant = 'success';
        } else if (successCount > 0) {
            this.createCompleted = true;
            this.panelStatusMessage = errorMessage || `Created ${successCount} record(s), ${failureCount} failed. Click Close to exit.`;
            this.panelStatusVariant = 'warning';
        } else {
            this.panelStatusMessage = errorMessage || 'Unable to create records. No response details were returned from the server.';
            this.panelStatusVariant = 'error';
        }
    }

    async ensureRequiredSourceFields() {
        const requiredFields = this.getRequiredFieldNamesForCreate();
        const recordIdsNeedingLoad = this._recordIds.filter((recordId) => {
            const draft = this.drafts[recordId] || {};
            return requiredFields.some((fieldName) => {
                const value = draft[fieldName];
                return value === undefined || value === null || value === '';
            });
        });

        if (!recordIdsNeedingLoad.length) {
            return;
        }

        const valuesJson = await getRecordFieldValuesJson({
            objectApiName: this.objectApiName,
            recordIds: recordIdsNeedingLoad,
            fieldNames: requiredFields
        });
        const valuesByRecordId = JSON.parse(valuesJson || '{}');

            recordIdsNeedingLoad.forEach((recordId) => {
            const sourceValues = valuesByRecordId[recordId] || {};
            let draft = this.drafts[recordId];
            if (!draft) {
                draft = this.applyBulkValuesToDraft({ __sourceName: sourceValues.Name });
            }
            const merged = this.mergeDraftWithSourceValues(recordId, draft, sourceValues);
            this.setDraft(recordId, merged);
        });
        this.refreshDraftNames();
    }

    async ensureAllDraftsReady() {
        this.saveCurrentDraftFromForm();

        const valuesJson = await getRecordFieldValuesJson({
            objectApiName: this.objectApiName,
            recordIds: [...this._recordIds],
            fieldNames: this.getDraftFieldNamesForLoad()
        });
        const valuesByRecordId = JSON.parse(valuesJson || '{}');

        this._recordIds.forEach((recordId) => {
            const sourceValues = valuesByRecordId[recordId] || {};
            let draft = this.drafts[recordId];
            if (!draft) {
                draft = this.applyBulkValuesToDraft({ __sourceName: sourceValues.Name });
            }
            const merged = this.mergeDraftWithSourceValues(recordId, draft, sourceValues);
            this.setDraft(recordId, merged);
        });
        this.refreshDraftNames();
    }

    mergeDraftWithSourceValues(recordId, draft, sourceValues) {
        const merged = { ...(draft || {}), __sourceName: sourceValues?.Name };

        [...this.resolvedFieldNames, ...this.cloneRule.fieldsToLoad].forEach((fieldName) => {
            const value = merged[fieldName];
            if (value !== undefined && value !== null && value !== '') {
                return;
            }
            merged[fieldName] = sourceValues?.[fieldName];
        });

        const finalName = this.cloneRule.deriveName(merged, sourceValues);
        if (finalName) {
            merged.Name = finalName;
        }

        return merged;
    }

    @api
    validate() {
        if (!this.hasRecords) {
            return {
                isValid: false,
                errorMessage: 'Select at least one record to clone.'
            };
        }

        if (this.currentStep === STEP_EDIT) {
            return {
                isValid: false,
                errorMessage: 'Click Review to preview all records before creating them.'
            };
        }

        if (this.createCompleted) {
            return { isValid: true };
        }

        return {
            isValid: false,
            errorMessage: 'Click Create Records in the panel header to create the records.'
        };
    }
}
