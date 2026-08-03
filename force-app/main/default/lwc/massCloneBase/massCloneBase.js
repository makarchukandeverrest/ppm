import { LightningElement, api, wire } from 'lwc';
import { getLayout } from 'lightning/uiLayoutApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getRecordFieldValuesJson from '@salesforce/apex/MassCloneController.getRecordFieldValuesJson';
import createCloneRecords from '@salesforce/apex/MassCloneController.createCloneRecords';
import {
    CONTRACT_BID_OBJECT,
    buildContractBidCloneName
} from './contractBidCloneUtils';

const SYSTEM_FIELDS = new Set([
    'CreatedById',
    'CreatedDate',
    'LastModifiedById',
    'LastModifiedDate',
    'SystemModstamp',
    'IsDeleted'
]);

const TEMPLATE_RECORD_ID = '__bulk_template__';
const BULK_APPLY_EXCLUDED_FIELDS = new Set(['Name']);
const PREVIEW_FIELDS = ['Name', 'Customer__c', 'Contract_Year__c', 'Stage__c', 'Due_Date__c'];
const STEP_EDIT = 'edit';
const STEP_REVIEW = 'review';

export default class MassCloneBase extends LightningElement {
    _recordIds = [];
    @api recordNames = [];
    @api objectApiName;
    _fieldNames = [];
    @api layoutType = 'Full';
    @api layoutMode = 'Edit';
    @api recordTypeId;
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
    selectedRecordId;
    sourceRecord;
    recordLoadError;
    isRecordLoading = false;
    formContractYear;
    _fieldsAppliedKey;
    recordDrafts = {};
    sourceSnapshots = {};
    pendingBulkValues;
    currentStep = STEP_EDIT;
    isPreparingReview = false;
    isCreatingRecords = false;
    createCompleted = false;
    panelStatusMessage = '';
    panelStatusVariant = '';

    @api
    get recordIds() {
        return this._recordIds;
    }

    set recordIds(value) {
        this._recordIds = Array.isArray(value) ? [...value] : [];
        this.ensureSelectedRecord();
    }

    @api
    get fieldNames() {
        return this._fieldNames;
    }

    set fieldNames(value) {
        this._fieldNames = Array.isArray(value) ? [...value] : [];
        this.applyExplicitFieldNames();
    }

    connectedCallback() {
        this.ensureSelectedRecord();
    }

    ensureSelectedRecord() {
        if (!this._recordIds.length) {
            this.selectedRecordId = undefined;
            this.sourceRecord = undefined;
            return;
        }

        const isValidSelection =
            this.selectedRecordId === TEMPLATE_RECORD_ID ||
            this._recordIds.includes(this.selectedRecordId);

        if (!this.selectedRecordId || !isValidSelection) {
            this.selectedRecordId = TEMPLATE_RECORD_ID;
            this.sourceRecord = undefined;
            this.isRecordLoading = false;
            this._fieldsAppliedKey = undefined;
        }
    }

    get isTemplateSelected() {
        return this.selectedRecordId === TEMPLATE_RECORD_ID;
    }

    get isRealRecordSelected() {
        return Boolean(this.selectedRecordId) && !this.isTemplateSelected;
    }

    get recordFields() {
        if (
            this.isTemplateSelected ||
            !this.selectedRecordId ||
            !this.objectApiName ||
            !this.resolvedFieldNames.length
        ) {
            return undefined;
        }

        return this.buildRecordFieldPaths(this.selectedRecordId);
    }

    buildRecordFieldPaths(recordId) {
        if (!recordId || !this.objectApiName || !this.resolvedFieldNames.length) {
            return undefined;
        }

        const fields = [...this.resolvedFieldNames];

        if (this.isContractBid && !fields.includes('Contract_Year__c')) {
            fields.push('Contract_Year__c');
        }

        return fields.map((fieldName) => `${this.objectApiName}.${fieldName}`);
    }

    get isContractBid() {
        return this.objectApiName === CONTRACT_BID_OBJECT;
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

            const existingDraft = this.recordDrafts[this.selectedRecordId];
            if (existingDraft?.Contract_Year__c !== undefined) {
                this.formContractYear = existingDraft.Contract_Year__c;
            } else {
                this.formContractYear = getFieldValue(
                    data,
                    `${this.objectApiName}.Contract_Year__c`
                );
            }

            this._fieldsAppliedKey = undefined;
        } else if (error) {
            this.sourceRecord = undefined;
            this.formContractYear = undefined;
            this.recordLoadError = error;
            this._fieldsAppliedKey = undefined;
        }
    }

    @wire(getObjectInfo, { objectApiName: '$objectApiName' })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.objectInfo = data;
            this.defaultRecordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            this.objectInfo = undefined;
            this.defaultRecordTypeId = undefined;
        }
    }

    @wire(getLayout, {
        objectApiName: '$objectApiName',
        layoutType: '$layoutType',
        mode: '$layoutMode',
        recordTypeId: '$effectiveRecordTypeId'
    })
    wiredLayout({ data, error }) {
        if (this.hasExplicitFieldNames) {
            return;
        }

        this.layoutFetchComplete = true;

        if (data) {
            this.formSections = this.extractSectionsFromLayout(data);
            this.resolvedFieldNames = this.flattenSectionFields(this.formSections);
            this.layoutError = undefined;
            this.publishFormFieldNames();
        } else if (error) {
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

    get isEditStep() {
        return this.currentStep === STEP_EDIT;
    }

    get isReviewStep() {
        return this.currentStep === STEP_REVIEW;
    }

    get reviewCardTitle() {
        return 'Ready to Create';
    }

    get reviewRows() {
        if (!this.clonePayloadJson) {
            return [];
        }

        try {
            const payloads = JSON.parse(this.clonePayloadJson);
            if (!Array.isArray(payloads)) {
                return [];
            }

            return payloads.map((payload, index) => {
                const fields = payload.fields || {};
                const previewValues = PREVIEW_FIELDS.filter((fieldName) =>
                    Object.prototype.hasOwnProperty.call(fields, fieldName)
                ).map((fieldName) => ({
                    key: `${index}-${fieldName}`,
                    label: fieldName,
                    value: this.formatReviewValue(fields[fieldName])
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
        } catch (error) {
            return [];
        }
    }

    get hasReviewRows() {
        return this.reviewRows.length > 0;
    }

    get reviewSummaryText() {
        return `${this.reviewRows.length} record(s) ready to create.`;
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

    get isCreateDisabled() {
        return this.isCreatingRecords || this.createCompleted;
    }

    formatReviewValue(value) {
        if (value === null || value === undefined || value === '') {
            return '—';
        }

        if (typeof value === 'object') {
            return JSON.stringify(value);
        }

        return String(value);
    }

    get rows() {
        if (!this._recordIds.length) {
            return [];
        }

        const templateRow = {
            id: TEMPLATE_RECORD_ID,
            rowNumber: '★',
            name: 'Common values',
            title: 'Shared template for all records',
            originalName: null,
            showOriginalName: false,
            isTemplate: true,
            isSelected: this.isTemplateSelected,
            itemClass: this.isTemplateSelected
                ? 'id-item id-item_template id-item_selected'
                : 'id-item id-item_template'
        };

        const recordRows = this._recordIds.map((id, index) => {
            const originalName = this.getRecordLabel(index, id);
            const isSelected = id === this.selectedRecordId;
            const draftName = this.getDraftFieldValue(id, 'Name');
            const displayName =
                this.isContractBid && draftName ? draftName : originalName;

            return {
                id,
                rowNumber: index + 1,
                name: displayName,
                title: 'Use this record as clone source',
                originalName,
                showOriginalName: Boolean(
                    this.isContractBid && draftName && draftName !== originalName
                ),
                isTemplate: false,
                isSelected,
                itemClass: isSelected ? 'id-item id-item_selected' : 'id-item'
            };
        });

        return [templateRow, ...recordRows];
    }

    buildSourceSnapshot(sourceRecord) {
        if (!sourceRecord || !this.objectApiName) {
            return {};
        }

        return {
            Name: getFieldValue(sourceRecord, `${this.objectApiName}.Name`),
            Contract_Year__c: getFieldValue(
                sourceRecord,
                `${this.objectApiName}.Contract_Year__c`
            )
        };
    }

    ensureTemplateDraft() {
        if (!this.recordDrafts[TEMPLATE_RECORD_ID]) {
            this.recordDrafts = {
                ...this.recordDrafts,
                [TEMPLATE_RECORD_ID]: {}
            };
        }
    }

    extractNonEmptyDraftValues(draft) {
        if (!draft) {
            return {};
        }

        const values = {};
        Object.entries(draft).forEach(([fieldName, value]) => {
            if (
                !BULK_APPLY_EXCLUDED_FIELDS.has(fieldName) &&
                value !== undefined &&
                value !== null &&
                value !== ''
            ) {
                values[fieldName] = value;
            }
        });

        return values;
    }

    applyBulkValuesToDraft(recordId, draft, sharedValues) {
        Object.assign(draft, sharedValues);

        if (sharedValues.Contract_Year__c !== undefined) {
            this.syncCloneNameInDraft(recordId, draft, sharedValues.Contract_Year__c);
        }
    }

    getRawSourceName(recordId) {
        if (this.sourceSnapshots[recordId]?.Name) {
            return this.sourceSnapshots[recordId].Name;
        }

        const index = this._recordIds.indexOf(recordId);
        if (index !== -1 && Array.isArray(this.recordNames) && this.recordNames[index]) {
            return this.recordNames[index];
        }

        if (recordId === this.selectedRecordId && this.sourceRecord) {
            return getFieldValue(this.sourceRecord, `${this.objectApiName}.Name`);
        }

        return undefined;
    }

    syncCloneNameInDraft(recordId, draft, contractYear) {
        if (!this.isContractBid) {
            return;
        }

        const rawName = this.getRawSourceName(recordId);
        if (!rawName) {
            return;
        }

        draft.Name = buildContractBidCloneName(rawName, contractYear);
    }

    getDraftForRecord(recordId) {
        return this.recordDrafts[recordId] || null;
    }

    getDraftFieldValue(recordId, fieldName) {
        const draft = this.getDraftForRecord(recordId);
        if (!draft || !Object.prototype.hasOwnProperty.call(draft, fieldName)) {
            return undefined;
        }

        return draft[fieldName];
    }

    getSourceFieldValue(fieldName, sourceRecord = this.sourceRecord) {
        if (!sourceRecord || !this.objectApiName) {
            return undefined;
        }

        const rawValue = getFieldValue(
            sourceRecord,
            `${this.objectApiName}.${fieldName}`
        );

        return this.transformSourceFieldValue(fieldName, rawValue, sourceRecord);
    }

    getSourceFieldValueFromMap(fieldName, fieldMap) {
        if (!fieldMap) {
            return undefined;
        }

        const rawValue = fieldMap[fieldName];
        return this.transformSourceFieldValue(fieldName, rawValue, fieldMap);
    }

    transformSourceFieldValue(fieldName, rawValue, source) {
        if (this.isContractBid && fieldName === 'Name') {
            let contractYear;
            if (
                source &&
                typeof source === 'object' &&
                Object.prototype.hasOwnProperty.call(source, 'Contract_Year__c')
            ) {
                contractYear = source.Contract_Year__c;
            } else if (source && this.objectApiName) {
                contractYear = getFieldValue(
                    source,
                    `${this.objectApiName}.Contract_Year__c`
                );
            }
            return buildContractBidCloneName(rawValue, contractYear);
        }

        return rawValue;
    }

    ensureDraftInitialized(recordId) {
        if (recordId === TEMPLATE_RECORD_ID) {
            this.ensureTemplateDraft();
            return;
        }

        if (this.recordDrafts[recordId] || !this.sourceRecord || recordId !== this.selectedRecordId) {
            return;
        }

        const draft = {};
        this.resolvedFieldNames.forEach((fieldName) => {
            draft[fieldName] = this.getSourceFieldValue(fieldName);
        });

        if (this.pendingBulkValues) {
            this.applyBulkValuesToDraft(recordId, draft, this.pendingBulkValues);
        }

        this.recordDrafts = {
            ...this.recordDrafts,
            [recordId]: draft
        };

        if (this.isContractBid && draft.Contract_Year__c !== undefined) {
            this.formContractYear = draft.Contract_Year__c;
        }
    }

    updateDraftField(fieldName, value) {
        if (!this.selectedRecordId) {
            return;
        }

        const existing = this.recordDrafts[this.selectedRecordId] || {};
        this.recordDrafts = {
            ...this.recordDrafts,
            [this.selectedRecordId]: {
                ...existing,
                [fieldName]: value
            }
        };
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

    isEmptyFieldValue(value) {
        return this.normalizeFieldValue(value) === undefined;
    }

    saveCurrentDraftFromForm() {
        if (!this.selectedRecordId) {
            return;
        }

        const fields = this.template.querySelectorAll('lightning-input-field');
        if (!fields.length) {
            return;
        }

        const existing = { ...(this.recordDrafts[this.selectedRecordId] || {}) };
        fields.forEach((field) => {
            if (!field.fieldName) {
                return;
            }

            const normalizedValue = this.normalizeFieldValue(field.value);
            if (normalizedValue !== undefined) {
                existing[field.fieldName] = normalizedValue;
            }
        });

        this.recordDrafts = {
            ...this.recordDrafts,
            [this.selectedRecordId]: existing
        };
    }

    get cloneNamePreview() {
        if (!this.isContractBid || !this.isRealRecordSelected) {
            return '';
        }

        const draftName = this.getDraftFieldValue(this.selectedRecordId, 'Name');
        if (draftName) {
            return draftName;
        }

        if (!this.sourceRecord) {
            return '';
        }

        return this.getSourceFieldValue('Name');
    }

    get showCloneNamePreview() {
        return this.isContractBid && Boolean(this.cloneNamePreview);
    }

    get formSectionsWithValues() {
        return this.formSections.map((section) => ({
            ...section,
            fields: section.fields.map((fieldName) => ({
                key:
                    fieldName === 'Name'
                        ? `${this.selectedRecordId}-Name-${this.formContractYear ?? ''}`
                        : `${this.selectedRecordId}-${fieldName}`,
                name: fieldName,
                value: this.getFieldValueForForm(fieldName)
            }))
        }));
    }

    getFieldValueForForm(fieldName) {
        const draftValue = this.getDraftFieldValue(this.selectedRecordId, fieldName);
        if (draftValue !== undefined) {
            return draftValue;
        }

        if (this.isTemplateSelected) {
            return undefined;
        }

        return this.getSourceFieldValue(fieldName);
    }

    handleRecordSelect(event) {
        const recordId = event.currentTarget.dataset.id;

        if (!recordId || recordId === this.selectedRecordId) {
            return;
        }

        this.saveCurrentDraftFromForm();

        if (recordId === TEMPLATE_RECORD_ID) {
            this.selectedRecordId = TEMPLATE_RECORD_ID;
            this.sourceRecord = undefined;
            this.formContractYear = this.getDraftFieldValue(
                TEMPLATE_RECORD_ID,
                'Contract_Year__c'
            );
            this.isRecordLoading = false;
            this._fieldsAppliedKey = undefined;
            return;
        }

        this.isRecordLoading = true;
        this.selectedRecordId = recordId;

        const draft = this.getDraftForRecord(recordId);
        this.formContractYear =
            draft?.Contract_Year__c !== undefined ? draft.Contract_Year__c : undefined;
        this._fieldsAppliedKey = undefined;
    }

    handleApplyToAll() {
        this.saveCurrentDraftFromForm();

        const sharedValues = this.extractNonEmptyDraftValues(
            this.recordDrafts[TEMPLATE_RECORD_ID]
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

        this.pendingBulkValues = { ...sharedValues };
        const updatedDrafts = { ...this.recordDrafts };

        this._recordIds.forEach((recordId) => {
            const existingDraft = { ...(updatedDrafts[recordId] || {}) };
            this.applyBulkValuesToDraft(recordId, existingDraft, sharedValues);
            updatedDrafts[recordId] = existingDraft;
        });

        this.recordDrafts = updatedDrafts;

        if (this.isRealRecordSelected) {
            const activeDraft = updatedDrafts[this.selectedRecordId];
            if (activeDraft?.Contract_Year__c !== undefined) {
                this.formContractYear = activeDraft.Contract_Year__c;
            }
            this._fieldsAppliedKey = undefined;
            Promise.resolve().then(() => this.applyFormFieldValues());
        }

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Applied to all',
                message: `Shared values applied to ${this._recordIds.length} record(s).`,
                variant: 'success'
            })
        );
    }

    handleFieldChange(event) {
        const field = event.currentTarget;
        const fieldName = field?.fieldName;
        const value = event.detail?.value ?? field.value;

        if (!fieldName || !this.selectedRecordId) {
            return;
        }

        this.ensureDraftInitialized(this.selectedRecordId);
        this.updateDraftField(fieldName, value);

        if (this.isContractBid && fieldName === 'Contract_Year__c') {
            this.formContractYear = value;

            if (this.isRealRecordSelected) {
                const draft = {
                    ...(this.recordDrafts[this.selectedRecordId] || {}),
                    Contract_Year__c: value
                };
                this.syncCloneNameInDraft(this.selectedRecordId, draft, value);
                this.recordDrafts = {
                    ...this.recordDrafts,
                    [this.selectedRecordId]: draft
                };
                this.applyCloneNameField();
            }
        }
    }

    renderedCallback() {
        this.applyFormFieldValues();
    }

    applyCloneNameField() {
        const nameValue = this.getFieldValueForForm('Name');
        if (nameValue === undefined) {
            return;
        }

        this.template.querySelectorAll('lightning-input-field').forEach((field) => {
            if (field.fieldName === 'Name') {
                field.value = nameValue;
            }
        });
    }

    applyFormFieldValues() {
        if (!this.isLayoutReady) {
            return;
        }

        if (this.isTemplateSelected) {
            this.ensureTemplateDraft();
        } else if (!this.sourceRecord) {
            return;
        } else {
            this.ensureDraftInitialized(this.selectedRecordId);
        }

        if (this._fieldsAppliedKey === this.selectedRecordId) {
            return;
        }

        this.template.querySelectorAll('lightning-input-field').forEach((field) => {
            const value = this.getFieldValueForForm(field.fieldName);
            if (value !== undefined && value !== null) {
                field.value = value;
            } else if (this.isTemplateSelected) {
                field.value = null;
            }
        });

        this._fieldsAppliedKey = this.selectedRecordId;
    }

    handleRecordKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleRecordSelect(event);
        }
    }

    getRecordLabel(index, id) {
        if (Array.isArray(this.recordNames) && this.recordNames[index]) {
            return this.recordNames[index];
        }

        return id;
    }

    get selectedRecordLabel() {
        if (this.isTemplateSelected) {
            return '';
        }

        const index = this._recordIds.indexOf(this.selectedRecordId);

        if (index === -1) {
            return '';
        }

        return this.getRecordLabel(index, this.selectedRecordId);
    }

    get selectedRecordCloneLabel() {
        if (!this.isContractBid) {
            return this.selectedRecordLabel;
        }

        return this.cloneNamePreview || this.selectedRecordLabel;
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

    get recordLoadErrorMessage() {
        if (!this.recordLoadError) {
            return null;
        }

        return (
            this.recordLoadError.body?.message ||
            this.recordLoadError.message ||
            'Unable to load selected record values.'
        );
    }

    get layoutErrorMessage() {
        if (!this.layoutError) {
            return null;
        }

        return (
            this.layoutError.body?.message ||
            this.layoutError.message ||
            'Unable to load page layout fields for this object.'
        );
    }

    buildDraftFromFieldMap(recordId, fieldMap) {
        const draft = {};

        this.resolvedFieldNames.forEach((fieldName) => {
            draft[fieldName] = this.getSourceFieldValueFromMap(fieldName, fieldMap);
        });

        if (this.pendingBulkValues) {
            this.applyBulkValuesToDraft(recordId, draft, this.pendingBulkValues);
        }

        return draft;
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

        PREVIEW_FIELDS.forEach(addField);
        this.resolvedFieldNames.forEach(addField);

        if (this.isContractBid) {
            addField('Contract_Year__c');
        }

        return fieldNames.slice(0, 60);
    }

    getRequiredFieldNamesForCreate() {
        const required = ['Name', 'Customer__c'];

        if (this.isContractBid) {
            required.push('Contract_Year__c', 'Stage__c');
        }

        if (this.objectInfo) {
            this.resolvedFieldNames.forEach((fieldName) => {
                const fieldDef = this.objectInfo.fields[fieldName];
                if (fieldDef?.required && fieldDef?.createable && !required.includes(fieldName)) {
                    required.push(fieldName);
                }
            });
        }

        return [...new Set(required)];
    }

    async ensureRequiredSourceFields() {
        const requiredFields = this.getRequiredFieldNamesForCreate();
        const recordIdsNeedingLoad = this._recordIds.filter((recordId) => {
            const draft = this.recordDrafts[recordId] || {};
            return requiredFields.some((fieldName) =>
                this.isEmptyFieldValue(draft[fieldName])
            );
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
        const updatedDrafts = { ...this.recordDrafts };

        recordIdsNeedingLoad.forEach((recordId) => {
            updatedDrafts[recordId] = this.mergeDraftWithSourceValues(
                recordId,
                updatedDrafts[recordId],
                valuesByRecordId[recordId] || {}
            );
        });

        this.recordDrafts = updatedDrafts;
    }

    mergeDraftWithSourceValues(recordId, draft, sourceValues) {
        const merged = { ...(draft || {}) };

        this.resolvedFieldNames.forEach((fieldName) => {
            if (!this.isEmptyFieldValue(merged[fieldName])) {
                return;
            }

            merged[fieldName] = this.getSourceFieldValueFromMap(fieldName, sourceValues);
        });

        if (this.pendingBulkValues) {
            this.applyBulkValuesToDraft(recordId, merged, this.pendingBulkValues);
        }

        return merged;
    }

    async ensureAllDraftsReady() {
        this.saveCurrentDraftFromForm();

        const valuesJson = await getRecordFieldValuesJson({
            objectApiName: this.objectApiName,
            recordIds: [...this._recordIds],
            fieldNames: this.getDraftFieldNamesForLoad()
        });
        const valuesByRecordId = JSON.parse(valuesJson || '{}');
        const updatedDrafts = { ...this.recordDrafts };

        this._recordIds.forEach((recordId) => {
            updatedDrafts[recordId] = this.mergeDraftWithSourceValues(
                recordId,
                updatedDrafts[recordId],
                valuesByRecordId[recordId] || {}
            );
        });

        this.recordDrafts = updatedDrafts;
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
            sourceName: this.getRecordLabel(index, sourceId),
            fields: this.buildPayloadFields(this.recordDrafts[sourceId])
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

    extractErrorMessage(error) {
        if (!error) {
            return 'Unknown error';
        }

        if (Array.isArray(error.body)) {
            return error.body.map((entry) => entry.message).join(' ');
        }

        return error.body?.message || error.message || 'Unexpected error.';
    }

    async handleReview() {
        this.isPreparingReview = true;
        this.panelStatusMessage = '';
        this.panelStatusVariant = '';

        try {
            await this.ensureAllDraftsReady();
            this.publishClonePayload();

            if (!this.reviewRows.length) {
                this.panelStatusMessage =
                    'No clone field values were found for the selected records.';
                this.panelStatusVariant = 'warning';
                return;
            }

            this.currentStep = STEP_REVIEW;
        } catch (error) {
            this.panelStatusMessage = this.extractErrorMessage(error);
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

            if (!this.reviewRows.length) {
                this.panelStatusMessage =
                    'No clone field values were found for the selected records.';
                this.panelStatusVariant = 'warning';
                return;
            }

            const result = await createCloneRecords({
                objectApiName: this.objectApiName,
                clonePayloadJson: this.clonePayloadJson
            });

            this.publishCreateResult(result);

            const successCount = result?.successCount ?? 0;
            const failureCount = result?.failureCount ?? 0;
            const errorMessage = result?.errorMessage || '';

            if (successCount > 0 && !failureCount) {
                this.createCompleted = true;
                this.panelStatusMessage = `Successfully created ${successCount} record(s). Click Close to exit.`;
                this.panelStatusVariant = 'success';
            } else if (successCount > 0) {
                this.createCompleted = true;
                this.panelStatusMessage =
                    errorMessage ||
                    `Created ${successCount} record(s), ${failureCount} failed. Click Close to exit.`;
                this.panelStatusVariant = 'warning';
            } else {
                this.panelStatusMessage =
                    errorMessage ||
                    'Unable to create records. No response details were returned from the server.';
                this.panelStatusVariant = 'error';
            }
        } catch (error) {
            this.panelStatusMessage = this.extractErrorMessage(error);
            this.panelStatusVariant = 'error';
        } finally {
            this.isCreatingRecords = false;
        }
    }
}
