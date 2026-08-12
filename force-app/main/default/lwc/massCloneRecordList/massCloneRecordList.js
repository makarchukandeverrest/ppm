import { LightningElement, api } from 'lwc';
import { TEMPLATE_RECORD_ID } from 'c/massCloneUtils';

const TEMPLATE_ROW = {
    id: TEMPLATE_RECORD_ID,
    rowNumber: '★',
    name: 'Common values',
    title: 'Shared template for all records',
    originalName: null,
    showOriginalName: false,
    isTemplate: true
};

export default class MassCloneRecordList extends LightningElement {
    _recordIds = [];
    _recordNames = [];
    _selectedRecordId;
    @api
    get recordIds() {
        return this._recordIds;
    }
    set recordIds(value) {
        this._recordIds = Array.isArray(value) ? [...value] : [];
    }

    @api
    get recordNames() {
        return this._recordNames;
    }
    set recordNames(value) {
        this._recordNames = Array.isArray(value) ? [...value] : [];
    }

    @api
    get selectedRecordId() {
        return this._selectedRecordId;
    }
    set selectedRecordId(value) {
        this._selectedRecordId = value;
    }

    @api
    get draftNames() {
        return this._draftNames;
    }
    set draftNames(value) {
        this._draftNames = value || {};
    }

    get count() {
        return this._recordIds.length;
    }

    get hasRecords() {
        return this.count > 0;
    }

    get rows() {
        if (!this._recordIds.length) {
            return [];
        }

        const templateRow = this.buildTemplateRow();
        const recordRows = this._recordIds.map((id, index) => this.buildRecordRow(id, index));
        return [templateRow, ...recordRows];
    }

    buildTemplateRow() {
        const isSelected = this._selectedRecordId === TEMPLATE_RECORD_ID;
        return {
            ...TEMPLATE_ROW,
            isSelected,
            itemClass: isSelected
                ? 'id-item id-item_template id-item_selected'
                : 'id-item id-item_template'
        };
    }

    buildRecordRow(id, index) {
        const originalName = this._recordNames[index] || id;
        const draftName = this._draftNames?.[id];
        const displayName = draftName || originalName;
        const isSelected = id === this._selectedRecordId;

        return {
            id,
            rowNumber: index + 1,
            name: displayName,
            title: 'Use this record as clone source',
            originalName,
            showOriginalName: Boolean(draftName && draftName !== originalName),
            isTemplate: false,
            isSelected: String(isSelected),
            itemClass: isSelected ? 'id-item id-item_selected' : 'id-item'
        };
    }

    handleSelect(event) {
        const recordId = event.currentTarget.dataset.id;
        if (recordId && recordId !== this._selectedRecordId) {
            this.dispatchEvent(new CustomEvent('select', { detail: { recordId } }));
        }
    }
}
