import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// import getMergeGroups from '@salesforce/apex/DuplicateFinder.getMergeGroups';

export default class MassObjectMerger extends LightningElement {
    // objectTypes = [
    //     { label: 'Account', value: 'Account' },
    //     { label: 'Contact', value: 'Contact' },
    //     { label: 'Opportunity', value: 'Opportunity' },
    //     { label: 'Lead', value: 'Lead' }
    // ];

    // @track selectedObjectType = '';
    // @track mergeGroups = [];
    // @track isLoading = false;
    // @track isMerging = false;

    // selectedValues = {};

    // handleObjectTypeChange(event) {
    //     this.selectedObjectType = event.detail.value || '';
    //     this.mergeGroups = [];
    //     this.selectedValues = {};
    // }

    // async loadDuplicateGroups() {
    //     if (!this.selectedObjectType) {
    //         this.showToast('Error', 'Please select an object type first.', 'error');
    //         return;
    //     }

    //     this.isLoading = true;
    //     this.mergeGroups = [];
    //     this.selectedValues = {};

    //     try {
    //         const raw = await getMergeGroups({
    //             sObjectApiName: this.selectedObjectType,
    //             limitSize: 100
    //         });
    //         console.log('getMergeGroups RAW:', JSON.stringify(raw));

    //         this.mergeGroups = (raw || []).map((group) => {
    //             const defaultSelection = {};
    //             (group.fieldRows || []).forEach((row) => {
    //                 const firstVal = row.recordValues && row.recordValues[0];
    //                 if (firstVal) {
    //                     defaultSelection[row.fieldApiName] = firstVal.recordId;
    //                 }
    //             });

    //             this.selectedValues[group.groupKey] = defaultSelection;

    //             return group;
    //         });

    //         console.log('mergeGroups (mapped):', JSON.stringify(this.mergeGroups));
    //         console.log('selectedValues:', JSON.stringify(this.selectedValues));

    //         if (this.mergeGroups.length === 0) {
    //             this.showToast(
    //                 'Info',
    //                 'No duplicate groups found for this object type.',
    //                 'info'
    //             );
    //         }
    //     } catch (e) {
    //         const message =
    //             e && e.body && e.body.message
    //                 ? e.body.message
    //                 : (e && e.message) || 'Unknown error';
    //         this.showToast('Error', message, 'error');
    //         console.error('getMergeGroups error:', e);
    //     } finally {
    //         this.isLoading = false;
    //     }
    // }

    // get hasGroups() {
    //     return this.mergeGroups && this.mergeGroups.length > 0;
    // }

    // get isLoadButtonDisabled() {
    //     return !this.selectedObjectType || this.isLoading;
    // }

    // get displayGroups() {
    //     return (this.mergeGroups || []).map((group, index) => {
    //         const sel = this.selectedValues[group.groupKey] || {};
    //         return {
    //             ...group,
    //             isFirst: index === 0,
    //             headerRecords: (group.recordIds || []).map((id, idx) => ({
    //                 id,
    //                 name:
    //                     group.recordNames && group.recordNames[idx]
    //                         ? group.recordNames[idx]
    //                         : id
    //             })),
    //             fieldRows: (group.fieldRows || []).map((row) => ({
    //                 ...row,
    //                 radioName: `mergefield-${group.groupKey}-${row.fieldApiName}`,
    //                 recordValues: (row.recordValues || []).map((val) => ({
    //                     ...val,
    //                     isSelected: sel[row.fieldApiName] === val.recordId
    //                 }))
    //             }))
    //         };
    //     });
    // }

    // handleFieldChoiceChange(event) {
    //     const groupKey = event.target.dataset.groupkey;
    //     const fieldApi = event.target.dataset.fieldapiname;
    //     const recordId = event.target.dataset.recordid;
    //     const checked = event.target.checked;

    //     if (!groupKey || !fieldApi || !recordId) {
    //         return;
    //     }

    //     if (!this.selectedValues[groupKey]) {
    //         this.selectedValues[groupKey] = {};
    //     }

    //     if (checked) {
    //         this.selectedValues[groupKey][fieldApi] = recordId;
    //     } else {
    //         if (this.selectedValues[groupKey][fieldApi] === recordId) {
    //             delete this.selectedValues[groupKey][fieldApi];
    //         }
    //     }

    //     this.selectedValues = { ...this.selectedValues };
    // }

    // get allGroupsValidForMerge() {
    //     return (this.mergeGroups || []).every((group) => {
    //         const sel = this.selectedValues[group.groupKey] || {};
    //         const requestedFields = (group.fieldRows || []).map(
    //             (r) => r.fieldApiName
    //         );
    //         return requestedFields.every((f) => !!sel[f]);
    //     });
    // }

    // get invalidGroupsMessage() {
    //     const bad = (this.mergeGroups || []).filter((group) => {
    //         const sel = this.selectedValues[group.groupKey] || {};
    //         const requestedFields = (group.fieldRows || []).map(
    //             (r) => r.fieldApiName
    //         );
    //         return !requestedFields.every((f) => !!sel[f]);
    //     });
    //     if (bad.length === 0) return '';
    //     return `Each group must have a selected value for every field. ${bad.length} group(s) are incomplete.`;
    // }

    // get isMergeButtonDisabled() {
    //     return this.isMerging || !this.hasGroups || !this.allGroupsValidForMerge;
    // }

    // handleMerge() {
    //     if (!this.allGroupsValidForMerge) {
    //         this.showToast(
    //             'Error',
    //             this.invalidGroupsMessage ||
    //                 'Each group must select a value for every field.',
    //             'error'
    //         );
    //         return;
    //     }

    //     const payload = (this.mergeGroups || []).map((group) => {
    //         const sel = this.selectedValues[group.groupKey] || {};
    //         const fieldSelections = (group.fieldRows || []).map((row) => ({
    //             fieldApiName: row.fieldApiName,
    //             recordId: sel[row.fieldApiName]
    //         }));
    //         return {
    //             groupKey: group.groupKey,
    //             fieldSelections
    //         };
    //     });

    //     this.isMerging = true;

    //     setTimeout(() => {
    //         this.isMerging = false;
    //         const totalGroups = payload.length;
    //         this.showToast(
    //             'Success',
    //             `Prepared merge for ${totalGroups} group(s).`,
    //             'success'
    //         );
    //         this.resetComponent();
    //     }, 1500);
    // }

    // resetComponent() {
    //     this.mergeGroups = [];
    //     this.selectedObjectType = '';
    //     this.selectedValues = {};
    // }

    // showToast(title, message, variant) {
    //     this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    // }
}