import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Id from '@salesforce/schema/Account.Id';

import NORMAL_SEASON_FRIDAY_CLOSE_TIME from '@salesforce/schema/Account.Normal_Season_Friday_Close_Time__c';
import NORMAL_SEASON_FRIDAY_OPEN_TIME from '@salesforce/schema/Account.Normal_Season_Friday_Open_Time__c';
import NORMAL_SEASON_HOLIDAY_CLOSE_TIME from '@salesforce/schema/Account.NormalSeason_Holiday_Close_Time__c';
import NORMAL_SEASON_HOLIDAY_OPEN_TIME from '@salesforce/schema/Account.NormalSeason_Holiday_Open_Time__c';
import TOTAL_WEEKLY_PEAK_HOURS from '@salesforce/schema/Account.Total_Weekly_Peak_Hours__c';
import NORMAL_SEASON_MONDAY_CLOSE_TIME from '@salesforce/schema/Account.Normal_Season_Monday_Close_Time__c';
import NORMAL_SEASON_MONDAY_OPEN_TIME from '@salesforce/schema/Account.Normal_Season_Monday_Open_Time__c';
import NORMAL_SEASON_NUMBER_OF_LIFEGUARDS from '@salesforce/schema/Account.NormalSeason_Number_of_Lifeguards__c';
import NORMAL_SEASON_SATURDAY_CLOSE_TIME from '@salesforce/schema/Account.NormalSeason_Saturday_Close_Time__c';
import NORMAL_SEASON_SATURDAY_OPEN_TIME from '@salesforce/schema/Account.NormalSeason_Saturday_Open_Time__c';
import NORMAL_SEASON_SUNDAY_CLOSE_TIME from '@salesforce/schema/Account.NormalSeason_Sunday_Close_Time__c';
import NORMAL_SEASON_SUNDAY_OPEN_TIME from '@salesforce/schema/Account.NormalSeason_Sunday_Open_Time__c';
import NORMAL_SEASON_THURSDAY_CLOSE_TIME from '@salesforce/schema/Account.Normal_Season_Thursday_Close_Time__c';
import NORMAL_SEASON_THURSDAY_OPEN_TIME from '@salesforce/schema/Account.Normal_Season_Thursday_Open_Time__c';
import NORMAL_SEASON_TOTAL_STAFF_HOURS from '@salesforce/schema/Account.Normal_Season_Total_Staff_Hours__c';
import NORMAL_SEASON_TUESDAY_CLOSE_TIME from '@salesforce/schema/Account.Normal_Season_Tuesday_Close_Time__c';
import NORMAL_SEASON_TUESDAY_OPEN_TIME from '@salesforce/schema/Account.Normal_Season_Tuesday_Open_Time__c';
import NORMAL_SEASON_WEDNESDAY_CLOSE_TIME from '@salesforce/schema/Account.Normal_Season_Wednesday_Close_Time__c';
import NORMAL_SEASON_WEDNESDAY_OPEN_TIME from '@salesforce/schema/Account.Normal_Season_Wednesday_Open_Time__c';

import SCHOOL_OFF_SEASON_FRIDAY_CLOSE_TIME from '@salesforce/schema/Account.SchoolOff_Season_Friday_Close_Time__c';
import SCHOOL_OFF_SEASON_FRIDAY_OPEN_TIME from '@salesforce/schema/Account.SchoolOff_Season_Friday_Open_Time__c';
import SCHOOL_OFF_SEASON_HOLIDAY_CLOSE_TIME from '@salesforce/schema/Account.SchoolOff_Season_Holiday_Close_Time__c';
import SCHOOL_OFF_SEASON_HOLIDAY_OPEN_TIME from '@salesforce/schema/Account.SchoolOff_Season_Holiday_Open_Time__c';
import TOTAL_SCHOOL_OFF_SEASON_WEEKLY_HOURS from '@salesforce/schema/Account.Total_School_Off_Season_Weekly_Hours__c';
import SCHOOL_OFF_SEASON_MONDAY_CLOSE_TIME from '@salesforce/schema/Account.SchoolOff_Season_Monday_Close_Time__c';
import SCHOOL_OFF_SEASON_MONDAY_OPEN_TIME from '@salesforce/schema/Account.SchoolOff_Season_Monday_Open_Time__c';
import SCHOOL_OFF_SEASON_NUMBER_OF_LIFEGUARDS from '@salesforce/schema/Account.SchoolOff_Season_Number_of_Lifeguards__c';
import SCHOOL_OFF_SEASON_SATURDAY_CLOSE_TIME from '@salesforce/schema/Account.SchoolOff_Season_Saturday_Close_Time__c';
import SCHOOL_OFF_SEASON_SATURDAY_OPEN_TIME from '@salesforce/schema/Account.SchoolOff_Season_Saturday_Open_Time__c';
import SCHOOL_OFF_SEASON_SUNDAY_CLOSE_TIME from '@salesforce/schema/Account.SchoolOff_Season_Sunday_Close_Time__c';
import SCHOOL_OFF_SEASON_SUNDAY_OPEN_TIME from '@salesforce/schema/Account.SchoolOff_Season_Sunday_Open_Time__c';
import SCHOOL_OFF_SEASON_THURSDAY_CLOSE_TIME from '@salesforce/schema/Account.SchoolOff_Season_Thursday_Close_Time__c';
import SCHOOL_OFF_SEASON_THURSDAY_OPEN_TIME from '@salesforce/schema/Account.SchoolOff_Season_Thursday_Open_Time__c';
import SCHOOL_OFF_SEASON_TOTAL_STAFF_HOURS from '@salesforce/schema/Account.School_Off_Season_Total_Staff_Hours__c';
import SCHOOL_OFF_SEASON_TUESDAY_CLOSE_TIME from '@salesforce/schema/Account.SchoolOff_Season_Tuesday_Close_Time__c';
import SCHOOL_OFF_SEASON_TUESDAY_OPEN_TIME from '@salesforce/schema/Account.SchoolOff_Season_Tuesday_Open_Time__c';
import SCHOOL_OFF_SEASON_WEDNESDAY_CLOSE_TIME from '@salesforce/schema/Account.SchoolOff_Season_Wednesday_Close_Time__c';
import SCHOOL_OFF_SEASON_WEDNESDAY_OPEN_TIME from '@salesforce/schema/Account.SchoolOff_Season_Wednesday_Open_Time__c';

const NORMAL_SEASON_FIELDS = [
    NORMAL_SEASON_FRIDAY_CLOSE_TIME,
    NORMAL_SEASON_FRIDAY_OPEN_TIME,
    NORMAL_SEASON_HOLIDAY_CLOSE_TIME,
    NORMAL_SEASON_HOLIDAY_OPEN_TIME,
    TOTAL_WEEKLY_PEAK_HOURS,
    NORMAL_SEASON_MONDAY_CLOSE_TIME,
    NORMAL_SEASON_MONDAY_OPEN_TIME,
    NORMAL_SEASON_NUMBER_OF_LIFEGUARDS,
    NORMAL_SEASON_SATURDAY_CLOSE_TIME,
    NORMAL_SEASON_SATURDAY_OPEN_TIME,
    NORMAL_SEASON_SUNDAY_CLOSE_TIME,
    NORMAL_SEASON_SUNDAY_OPEN_TIME,
    NORMAL_SEASON_THURSDAY_CLOSE_TIME,
    NORMAL_SEASON_THURSDAY_OPEN_TIME,
    NORMAL_SEASON_TOTAL_STAFF_HOURS,
    NORMAL_SEASON_TUESDAY_CLOSE_TIME,
    NORMAL_SEASON_TUESDAY_OPEN_TIME,
    NORMAL_SEASON_WEDNESDAY_CLOSE_TIME,
    NORMAL_SEASON_WEDNESDAY_OPEN_TIME
];

const SCHOOL_OFF_SEASON_FIELDS = [
    SCHOOL_OFF_SEASON_FRIDAY_CLOSE_TIME,
    SCHOOL_OFF_SEASON_FRIDAY_OPEN_TIME,
    SCHOOL_OFF_SEASON_HOLIDAY_CLOSE_TIME,
    SCHOOL_OFF_SEASON_HOLIDAY_OPEN_TIME,
    TOTAL_SCHOOL_OFF_SEASON_WEEKLY_HOURS,
    SCHOOL_OFF_SEASON_MONDAY_CLOSE_TIME,
    SCHOOL_OFF_SEASON_MONDAY_OPEN_TIME,
    SCHOOL_OFF_SEASON_NUMBER_OF_LIFEGUARDS,
    SCHOOL_OFF_SEASON_SATURDAY_CLOSE_TIME,
    SCHOOL_OFF_SEASON_SATURDAY_OPEN_TIME,
    SCHOOL_OFF_SEASON_SUNDAY_CLOSE_TIME,
    SCHOOL_OFF_SEASON_SUNDAY_OPEN_TIME,
    SCHOOL_OFF_SEASON_THURSDAY_CLOSE_TIME,
    SCHOOL_OFF_SEASON_THURSDAY_OPEN_TIME,
    SCHOOL_OFF_SEASON_TOTAL_STAFF_HOURS,
    SCHOOL_OFF_SEASON_TUESDAY_CLOSE_TIME,
    SCHOOL_OFF_SEASON_TUESDAY_OPEN_TIME,
    SCHOOL_OFF_SEASON_WEDNESDAY_CLOSE_TIME,
    SCHOOL_OFF_SEASON_WEDNESDAY_OPEN_TIME
];

const NORMAL_SEASON_FIELD_CONFIG = [
    { apiName: 'Normal_Season_Monday_Open_Time__c', label: 'Monday Open', type: 'time', fieldRef: NORMAL_SEASON_MONDAY_OPEN_TIME },
    { apiName: 'Normal_Season_Monday_Close_Time__c', label: 'Monday Close', type: 'time', fieldRef: NORMAL_SEASON_MONDAY_CLOSE_TIME },
    { apiName: 'Normal_Season_Tuesday_Open_Time__c', label: 'Tuesday Open', type: 'time', fieldRef: NORMAL_SEASON_TUESDAY_OPEN_TIME },
    { apiName: 'Normal_Season_Tuesday_Close_Time__c', label: 'Tuesday Close', type: 'time', fieldRef: NORMAL_SEASON_TUESDAY_CLOSE_TIME },
    { apiName: 'Normal_Season_Wednesday_Open_Time__c', label: 'Wednesday Open', type: 'time', fieldRef: NORMAL_SEASON_WEDNESDAY_OPEN_TIME },
    { apiName: 'Normal_Season_Wednesday_Close_Time__c', label: 'Wednesday Close', type: 'time', fieldRef: NORMAL_SEASON_WEDNESDAY_CLOSE_TIME },
    { apiName: 'Normal_Season_Thursday_Open_Time__c', label: 'Thursday Open', type: 'time', fieldRef: NORMAL_SEASON_THURSDAY_OPEN_TIME },
    { apiName: 'Normal_Season_Thursday_Close_Time__c', label: 'Thursday Close', type: 'time', fieldRef: NORMAL_SEASON_THURSDAY_CLOSE_TIME },
    { apiName: 'Normal_Season_Friday_Open_Time__c', label: 'Friday Open', type: 'time', fieldRef: NORMAL_SEASON_FRIDAY_OPEN_TIME },
    { apiName: 'Normal_Season_Friday_Close_Time__c', label: 'Friday Close', type: 'time', fieldRef: NORMAL_SEASON_FRIDAY_CLOSE_TIME },
    { apiName: 'NormalSeason_Saturday_Open_Time__c', label: 'Saturday Open', type: 'time', fieldRef: NORMAL_SEASON_SATURDAY_OPEN_TIME },
    { apiName: 'NormalSeason_Saturday_Close_Time__c', label: 'Saturday Close', type: 'time', fieldRef: NORMAL_SEASON_SATURDAY_CLOSE_TIME },
    { apiName: 'NormalSeason_Sunday_Open_Time__c', label: 'Sunday Open', type: 'time', fieldRef: NORMAL_SEASON_SUNDAY_OPEN_TIME },
    { apiName: 'NormalSeason_Sunday_Close_Time__c', label: 'Sunday Close', type: 'time', fieldRef: NORMAL_SEASON_SUNDAY_CLOSE_TIME },
    { apiName: 'NormalSeason_Holiday_Open_Time__c', label: 'Holiday Open', type: 'time', fieldRef: NORMAL_SEASON_HOLIDAY_OPEN_TIME },
    { apiName: 'NormalSeason_Holiday_Close_Time__c', label: 'Holiday Close', type: 'time', fieldRef: NORMAL_SEASON_HOLIDAY_CLOSE_TIME },
    { apiName: 'Total_Weekly_Peak_Hours__c', label: 'Total Weekly Peak Hours', type: 'readonly', fieldRef: TOTAL_WEEKLY_PEAK_HOURS },
    { apiName: 'NormalSeason_Number_of_Lifeguards__c', label: 'Number of Lifeguards', type: 'number', fieldRef: NORMAL_SEASON_NUMBER_OF_LIFEGUARDS },
    { apiName: 'Normal_Season_Total_Staff_Hours__c', label: 'Total Staff Hours', type: 'readonly', fieldRef: NORMAL_SEASON_TOTAL_STAFF_HOURS }
];

const SCHOOL_OFF_SEASON_FIELD_CONFIG = [
    { apiName: 'SchoolOff_Season_Monday_Open_Time__c', label: 'Monday Open', type: 'time', fieldRef: SCHOOL_OFF_SEASON_MONDAY_OPEN_TIME },
    { apiName: 'SchoolOff_Season_Monday_Close_Time__c', label: 'Monday Close', type: 'time', fieldRef: SCHOOL_OFF_SEASON_MONDAY_CLOSE_TIME },
    { apiName: 'SchoolOff_Season_Tuesday_Open_Time__c', label: 'Tuesday Open', type: 'time', fieldRef: SCHOOL_OFF_SEASON_TUESDAY_OPEN_TIME },
    { apiName: 'SchoolOff_Season_Tuesday_Close_Time__c', label: 'Tuesday Close', type: 'time', fieldRef: SCHOOL_OFF_SEASON_TUESDAY_CLOSE_TIME },
    { apiName: 'SchoolOff_Season_Wednesday_Open_Time__c', label: 'Wednesday Open', type: 'time', fieldRef: SCHOOL_OFF_SEASON_WEDNESDAY_OPEN_TIME },
    { apiName: 'SchoolOff_Season_Wednesday_Close_Time__c', label: 'Wednesday Close', type: 'time', fieldRef: SCHOOL_OFF_SEASON_WEDNESDAY_CLOSE_TIME },
    { apiName: 'SchoolOff_Season_Thursday_Open_Time__c', label: 'Thursday Open', type: 'time', fieldRef: SCHOOL_OFF_SEASON_THURSDAY_OPEN_TIME },
    { apiName: 'SchoolOff_Season_Thursday_Close_Time__c', label: 'Thursday Close', type: 'time', fieldRef: SCHOOL_OFF_SEASON_THURSDAY_CLOSE_TIME },
    { apiName: 'SchoolOff_Season_Friday_Open_Time__c', label: 'Friday Open', type: 'time', fieldRef: SCHOOL_OFF_SEASON_FRIDAY_OPEN_TIME },
    { apiName: 'SchoolOff_Season_Friday_Close_Time__c', label: 'Friday Close', type: 'time', fieldRef: SCHOOL_OFF_SEASON_FRIDAY_CLOSE_TIME },
    { apiName: 'SchoolOff_Season_Saturday_Open_Time__c', label: 'Saturday Open', type: 'time', fieldRef: SCHOOL_OFF_SEASON_SATURDAY_OPEN_TIME },
    { apiName: 'SchoolOff_Season_Saturday_Close_Time__c', label: 'Saturday Close', type: 'time', fieldRef: SCHOOL_OFF_SEASON_SATURDAY_CLOSE_TIME },
    { apiName: 'SchoolOff_Season_Sunday_Open_Time__c', label: 'Sunday Open', type: 'time', fieldRef: SCHOOL_OFF_SEASON_SUNDAY_OPEN_TIME },
    { apiName: 'SchoolOff_Season_Sunday_Close_Time__c', label: 'Sunday Close', type: 'time', fieldRef: SCHOOL_OFF_SEASON_SUNDAY_CLOSE_TIME },
    { apiName: 'Total_School_Off_Season_Weekly_Hours__c', label: 'Total School Off Season Weekly Hours', type: 'readonly', fieldRef: TOTAL_SCHOOL_OFF_SEASON_WEEKLY_HOURS },
    { apiName: 'SchoolOff_Season_Number_of_Lifeguards__c', label: 'Number of Lifeguards', type: 'number', fieldRef: SCHOOL_OFF_SEASON_NUMBER_OF_LIFEGUARDS },
    { apiName: 'School_Off_Season_Total_Staff_Hours__c', label: 'Total Staff Hours', type: 'readonly', fieldRef: SCHOOL_OFF_SEASON_TOTAL_STAFF_HOURS }
];

const ALL_FIELDS = [...NORMAL_SEASON_FIELDS, ...SCHOOL_OFF_SEASON_FIELDS];

export default class CustomerTimeRangeEditor extends LightningElement {
    @api recordId;
    @api timeRangeLabel = '';

    formData = {};
    isLoading = true;
    isSaving = false;
    isEditing = false;
    sectionOpen = false;
    wiredRecordResult;

    @wire(getRecord, { recordId: '$recordId', fields: [Id, ...ALL_FIELDS] })
    wiredRecord(result) {
        this.wiredRecordResult = result;
        const { data, error } = result;
        this.isLoading = false;
        if (data) {
            const next = {};
            [...NORMAL_SEASON_FIELD_CONFIG, ...SCHOOL_OFF_SEASON_FIELD_CONFIG].forEach((config) => {
                const val = getFieldValue(data, config.fieldRef);
                const str = val != null ? String(val).trim() : '';
                next[config.apiName] = config.type === 'time' ? this.normalizeTimeForInput(str) : str;
            });
            this.formData = next;
        }
        if (error) {
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Error loading record', message: error.body?.message || String(error), variant: 'error' })
            );
        }
    }

    get isNormalRange() {
        return (this.timeRangeLabel || '').trim().toLowerCase() === 'normal';
    }

    get isSchoolRange() {
        return (this.timeRangeLabel || '').trim().toLowerCase() === 'school';
    }

    get currentFieldConfig() {
        if (this.isNormalRange) return NORMAL_SEASON_FIELD_CONFIG;
        if (this.isSchoolRange) return SCHOOL_OFF_SEASON_FIELD_CONFIG;
        return [];
    }

    get showForm() {
        return this.isNormalRange || this.isSchoolRange;
    }

    get sectionTitle() {
        if (this.isNormalRange) return 'Peak Bid Hours';
        if (this.isSchoolRange) return 'School Bid Hours';
        return 'Details';
    }

    get chevronClass() {
        const base = 'section-chevron slds-section__title-action-icon slds-button__icon slds-button__icon_left';
        return this.sectionOpen ? base : base + ' section-chevron-collapsed';
    }

    get sectionClass() {
        return this.sectionOpen ? 'slds-section slds-is-open' : 'slds-section';
    }

    get sectionToggleLabel() {
        const title = this.sectionTitle;
        return this.sectionOpen ? `Collapse ${title} section` : `Expand ${title} section`;
    }

    handleSectionToggle() {
        this.sectionOpen = !this.sectionOpen;
    }

    get currentFieldsWithValues() {
        return this.currentFieldConfig.map((config) => {
            const value = this.getFieldValue(config.apiName);
            return {
                ...config,
                value,
                displayValue: config.type === 'time' ? this.formatTimeForDisplay(value) : value,
                isTime: config.type === 'time',
                isNumber: config.type === 'number',
                isReadonly: config.type === 'readonly'
            };
        });
    }

    /** Normalize time from API (e.g. 11:30:00.000Z) to HH:mm for lightning-input type="time". */
    normalizeTimeForInput(val) {
        if (!val || typeof val !== 'string') return '';
        const s = val.trim().replace(/\.\d+Z?$/i, '').substring(0, 8);
        const match = s.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
        if (!match) return '';
        return match[3] != null ? `${match[1].padStart(2, '0')}:${match[2]}:${match[3]}` : `${match[1].padStart(2, '0')}:${match[2]}`;
    }

    /** Format time for display, e.g. 11:30:00.000Z or 11:30 -> "11:30 AM". */
    formatTimeForDisplay(val) {
        if (val == null || val === '') return '';
        const s = String(val).trim().replace(/\.\d+Z?$/i, '').substring(0, 8);
        const match = s.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
        if (!match) return val;
        let hours = parseInt(match[1], 10);
        const minutes = match[2];
        const period = hours >= 12 ? 'PM' : 'AM';
        hours = hours % 12;
        if (hours === 0) hours = 12;
        return `${hours}:${minutes} ${period}`;
    }

    handleEdit() {
        this.isEditing = true;
    }

    async handleCancel() {
        this.isEditing = false;
        if (this.wiredRecordResult?.data) {
            await refreshApex(this.wiredRecordResult);
        }
    }

    handleFieldChange(event) {
        const apiName = event.target.dataset.apiName;
        const value = event.target.value;
        if (!apiName) return;
        this.formData = { ...this.formData, [apiName]: value };
    }

    getFieldValue(apiName) {
        return this.formData[apiName] ?? '';
    }

    getSaveErrorMessage(err) {
        const body = err?.body;
        const output = body?.output;
        const parts = [];
        if (output?.fieldErrors && typeof output.fieldErrors === 'object') {
            Object.entries(output.fieldErrors).forEach(([field, errors]) => {
                const list = Array.isArray(errors) ? errors : [errors];
                list.forEach((e) => {
                    const m = e?.message ?? e?.fieldLabel ?? field;
                    parts.push(`${field}: ${m}`);
                });
            });
        }
        if (output?.errors?.length) {
            output.errors.forEach((e) => parts.push(e?.message ?? String(e)));
        }
        if (parts.length) return parts.join('. ');
        return body?.message || body?.pageErrors?.[0]?.message || err?.message || String(err);
    }

    /** Format time for updateRecord: "HH:mm" or "HH:mm:ss" -> "HH:mm:ss.000Z" (24-hour, leading zeros). */
    formatTimeForSave(val) {
        if (val == null || String(val).trim() === '') return null;
        const s = String(val).trim().substring(0, 8);
        const match = s.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
        if (!match) return null;
        const h = match[1].padStart(2, '0');
        const m = match[2];
        const sec = (match[3] != null ? match[3] : '00').padStart(2, '0');
        return `${h}:${m}:${sec}.000Z`;
    }

    async handleSave() {
        if (!this.recordId || !this.showForm) return;
        const config = this.currentFieldConfig;
        const editableConfig = config.filter((c) => c.type !== 'readonly');
        const fields = { Id: this.recordId };
        editableConfig.forEach((c) => {
            const v = this.formData[c.apiName];
            if (c.type === 'number') {
                fields[c.apiName] = v === '' ? null : Number(v);
            } else if (c.type === 'time') {
                fields[c.apiName] = this.formatTimeForSave(v);
            } else {
                fields[c.apiName] = v || null;
            }
        });
        this.isSaving = true;
        try {
            await updateRecord({ fields });
            if (this.wiredRecordResult?.data) {
                await refreshApex(this.wiredRecordResult);
            }
            this.isEditing = false;
            this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Record updated.', variant: 'success' }));
        } catch (err) {
            const msg = this.getSaveErrorMessage(err);
            console.error('CustomerTimeRangeEditor save error:', err, err.body?.output);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error saving',
                    message: msg,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }
}
