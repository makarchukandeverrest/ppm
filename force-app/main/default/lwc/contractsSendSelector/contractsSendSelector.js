import { LightningElement, wire, track, api } from 'lwc';
import getAccountsWithFiles from '@salesforce/apex/AccountFilesController.getAccountsWithFiles';
import getFilterOptions from '@salesforce/apex/AccountFilesController.getFilterOptions';
import sendEnvelopeWithSignature from '@salesforce/apex/DocuSignDfsleEnvelopeService.sendEnvelopeWithSignature';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class ContractsSendSelector extends NavigationMixin(LightningElement) {
    @track accountsWithFiles;
    @track allAccountsWithFiles; // Store original data for reference
    error;
    @track isUpdating = false;
    @track showConfirmationModal = false;
    @track queryRecordIds;
    _recordId;
    _recordIds;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.syncQueryRecordIds();
    }

    @api
    get recordIds() {
        return this._recordIds;
    }
    set recordIds(value) {
        this._recordIds = value;
        this.syncQueryRecordIds();
    }

    syncQueryRecordIds() {
        if (this._recordIds && this._recordIds.length) {
            this.queryRecordIds = [...this._recordIds];
        } else if (this._recordId) {
            this.queryRecordIds = [this._recordId];
        } else {
            this.queryRecordIds = undefined;
        }
        this.loadAccounts();
    }

    // Filter state
    @track selectedRegionalManager = '';
    @track selectedCounty = '';
    @track customerNameFilter = '';
    @track selectedSupervisor = '';
    @track contractYearFilter = '';

    // Automatic Reminders
    @track automaticReminderValue = '';
    @track customReminderDays = '';
    automaticReminderOptions = [
        { label: 'Every day', value: '1' },
        { label: 'Every 2 days', value: '2' },
        { label: 'Every 3 days', value: '3' },
        { label: 'Every 4 days', value: '4' },
        { label: 'Every 5 days', value: '5' },
        { label: 'Every 6 days', value: '6' },
        { label: 'Every 7 days', value: '7' },
        { label: 'Custom', value: 'custom' }
    ];

    // Expiration (default date = today + 120 days)
    @track envelopeExpiresDate = '';
    envelopeExpiresMinDate = '2026-02-09';
    @track daysBeforeExpires = '120';

    // Filter options
    @track regionalManagerOptions = [];
    @track countyOptions = [];
    @track supervisorOptions = [];
    @track filtersLoaded = false;

    connectedCallback() {
        console.log('[SendContracts] boot 20260818c', this.recordId, JSON.stringify(this.queryRecordIds || null));
        // Default envelope expires = today + default days (120), not before min date
        const days = parseInt(this.daysBeforeExpires, 10) || 120;
        const computed = this._datePlusDays(new Date(), days);
        this.envelopeExpiresDate = computed >= this.envelopeExpiresMinDate
            ? computed
            : this.envelopeExpiresMinDate;
        this.contractYearFilter = String(new Date().getFullYear());
        this.loadAccounts();
    }

    _datePlusDays(date, days) {
        const d = new Date(date);
        d.setDate(d.getDate() + days);
        return d.toISOString().slice(0, 10);
    }

    _computeExpiresDateFromDays(days) {
        if (!days || isNaN(parseInt(days, 10))) return '';
        const computed = this._datePlusDays(new Date(), parseInt(days, 10));
        return computed >= this.envelopeExpiresMinDate ? computed : this.envelopeExpiresMinDate;
    }

    _computeDaysFromExpiresDate(dateStr) {
        if (!dateStr || typeof dateStr !== 'string') return '';
        const exp = new Date(dateStr + 'T12:00:00');
        const today = new Date();
        today.setHours(12, 0, 0, 0);
        exp.setHours(12, 0, 0, 0);
        const diffMs = exp.getTime() - today.getTime();
        const diffDays = Math.round(diffMs / (24 * 60 * 60 * 1000));
        return diffDays < 1 ? '1' : String(diffDays);
    }

    // Load filter options
    @wire(getFilterOptions)
    wiredFilterOptions({ error, data }) {
        if (data) {
            // Add empty option at the beginning for each filter
            this.regionalManagerOptions = [
                { label: '-- All --', value: '' },
                ...data.regionalManagers.map(opt => ({ label: opt.label, value: opt.value }))
            ];
            this.countyOptions = [
                { label: '-- All --', value: '' },
                ...data.counties.map(opt => ({ label: opt.label, value: opt.value }))
            ];
            this.supervisorOptions = [
                { label: '-- All --', value: '' },
                ...data.supervisors.map(opt => ({ label: opt.label, value: opt.value }))
            ];
            this.filtersLoaded = true;
        } else if (error) {
            console.error('Error loading filter options:', error);
        }
    }

    async loadAccounts() {
        this.isUpdating = true;
        try {
            const data = await getAccountsWithFiles({
                recordIds: this.queryRecordIds,
                regionalManagerId: this.selectedRegionalManager,
                county: this.selectedCounty,
                customerName: this.customerNameFilter,
                supervisorId: this.selectedSupervisor,
                contractYear: this.contractYearFilter
            });
            console.log(
                '[SendContracts] loaded',
                JSON.stringify({
                    recordId: this.recordId,
                    queryRecordIds: this.queryRecordIds,
                    rows: Array.isArray(data) ? data.length : 0
                })
            );
            this.accountsWithFiles = this._enrichAccountsWithReminders(Array.isArray(data) ? data : []);
            this.allAccountsWithFiles = this.accountsWithFiles;

            if (Array.isArray(data) && data.length === 0 && !this.hasActiveFilters) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Info',
                        message: 'No contracts found with active stages or no files attached.',
                        variant: 'info',
                        mode: 'dismissable'
                    })
                );
            }
        } catch (error) {
            console.error('[SendContracts] load error', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || 'Failed to load contracts',
                    variant: 'error',
                    mode: 'dismissable'
                })
            );
        } finally {
            this.isUpdating = false;
        }
    }

    // Check if any filters are active
    get hasActiveFilters() {
        const yearIsCustom = this.contractYearFilter
            && this.contractYearFilter !== String(new Date().getFullYear());

        return this.selectedRegionalManager || 
               this.selectedCounty || 
               this.customerNameFilter || 
               this.selectedSupervisor ||
               yearIsCustom;
    }

    // Getter for disabling Clear Filters button
    get hasNoActiveFilters() {
        return !this.hasActiveFilters;
    }

    // Getter for showing "no results" message with filters
    get showNoResultsWithFilters() {
        return this.hasActiveFilters && 
               this.accountsWithFiles && 
               this.accountsWithFiles.length === 0;
    }

    get showCustomReminderInput() {
        return this.automaticReminderValue === 'custom';
    }

    _enrichAccountsWithReminders(accounts) {
        const mainValue = this.automaticReminderValue || '';
        const mainCustomDays = mainValue === 'custom' ? (this.customReminderDays || '') : '';
        const mainEnvelopeDate = this.envelopeExpiresDate || '';
        const mainDaysBefore = this.daysBeforeExpires || '120';

        return accounts.map(acc => {
            // Prefer the flattened DTO ebdDueDate, but fall back to the
            // Contract_Bid__c.EBD_Due_Date__c if needed.
            const ebdDate =
                acc.ebdDueDate ||
                (acc.contract && acc.contract.EBD_Due_Date__c) ||
                '';
                console.log('EBD DATE '+ebdDate);
                
            // If we have an EBD due date, use that date as the default
            // envelope expiry for this row and derive the number of days
            // from today up to that date. Otherwise fall back to the
            // component‑level defaults.
            const accountEnvelopeDate = ebdDate || mainEnvelopeDate;
            const accountDaysBefore = accountEnvelopeDate
                ? this._computeDaysFromExpiresDate(accountEnvelopeDate)
                : mainDaysBefore;

            return {
                ...acc,
                reminderValue: mainValue,
                reminderCustomDays: mainCustomDays,
                reminderIsCustom: mainValue === 'custom',
                envelopeExpiresDate: accountEnvelopeDate,
                daysBeforeExpires: accountDaysBefore
            };
        });
    }

    _syncAllAccountsReminderToMain() {
        if (!this.accountsWithFiles || !Array.isArray(this.accountsWithFiles)) return;
        const mainValue = this.automaticReminderValue;
        const mainCustomDays = this.automaticReminderValue === 'custom' ? this.customReminderDays : '';
        this.accountsWithFiles = this.accountsWithFiles.map(acc => ({
            ...acc,
            reminderValue: mainValue,
            reminderCustomDays: mainCustomDays,
            reminderIsCustom: mainValue === 'custom'
        }));
    }

    _syncAllAccountsExpirationToMain() {
        if (!this.accountsWithFiles || !Array.isArray(this.accountsWithFiles)) return;
        const mainDate = this.envelopeExpiresDate || '';
        const mainDays = this.daysBeforeExpires || '';
        this.accountsWithFiles = this.accountsWithFiles.map(acc => ({
            ...acc,
            envelopeExpiresDate: mainDate,
            daysBeforeExpires: mainDays
        }));
    }

    // Handle filter changes
    handleAutomaticReminderChange(event) {
        this.automaticReminderValue = event.detail.value;
        if (this.automaticReminderValue !== 'custom') {
            this.customReminderDays = '';
        }
        this._syncAllAccountsReminderToMain();
    }

    handleCustomReminderDaysChange(event) {
        const val = event.detail.value;
        if (val === '' || val === undefined) {
            this.customReminderDays = '';
            return;
        }
        const num = parseInt(val, 10);
        this.customReminderDays = isNaN(num) ? '' : String(Math.max(1, num));
        this._syncAllAccountsReminderToMain();
    }

    handleAccountReminderChange(event) {
        const accountId = event.target.dataset.accountId;
        const value = event.detail.value || '';
        let updatedAccounts = JSON.parse(JSON.stringify(this.accountsWithFiles));
        updatedAccounts.forEach(acc => {
            if (acc.accountId === accountId) {
                acc.reminderValue = value;
                acc.reminderIsCustom = value === 'custom';
                if (value !== 'custom') acc.reminderCustomDays = '';
            }
        });
        this.accountsWithFiles = updatedAccounts;
    }

    handleAccountReminderCustomDaysChange(event) {
        const accountId = event.target.dataset.accountId;
        const val = event.detail.value;
        const num = (val === '' || val === undefined) ? '' : parseInt(val, 10);
        const str = (num === '' || isNaN(num)) ? '' : String(Math.max(1, num));
        let updatedAccounts = JSON.parse(JSON.stringify(this.accountsWithFiles));
        updatedAccounts.forEach(acc => {
            if (acc.accountId === accountId) acc.reminderCustomDays = str;
        });
        this.accountsWithFiles = updatedAccounts;
    }

    handleEnvelopeExpiresChange(event) {
        this.envelopeExpiresDate = event.detail.value || '';
        this.daysBeforeExpires = this.envelopeExpiresDate ? this._computeDaysFromExpiresDate(this.envelopeExpiresDate) : '';
        this._syncAllAccountsExpirationToMain();
    }

    handleDaysBeforeExpiresChange(event) {
        const val = event.detail.value;
        if (val === '' || val === undefined) {
            this.daysBeforeExpires = '';
            this.envelopeExpiresDate = '';
        } else {
            const num = parseInt(val, 10);
            this.daysBeforeExpires = isNaN(num) ? '' : String(Math.max(1, num));
            this.envelopeExpiresDate = this._computeExpiresDateFromDays(this.daysBeforeExpires);
        }
        this._syncAllAccountsExpirationToMain();
    }

    handleAccountEnvelopeExpiresChange(event) {
        const accountId = event.target.dataset.accountId;
        const value = event.detail.value || '';
        const daysStr = value ? this._computeDaysFromExpiresDate(value) : '';
        let updatedAccounts = JSON.parse(JSON.stringify(this.accountsWithFiles));
        updatedAccounts.forEach(acc => {
            if (acc.accountId === accountId) {
                acc.envelopeExpiresDate = value;
                acc.daysBeforeExpires = daysStr;
            }
        });
        this.accountsWithFiles = updatedAccounts;
    }

    handleAccountDaysBeforeExpiresChange(event) {
        const accountId = event.target.dataset.accountId;
        const val = event.detail.value;
        const str = (val === '' || val === undefined) ? '' : String(Math.max(1, parseInt(val, 10) || 1));
        const newDate = str ? this._computeExpiresDateFromDays(str) : '';
        let updatedAccounts = JSON.parse(JSON.stringify(this.accountsWithFiles));
        updatedAccounts.forEach(acc => {
            if (acc.accountId === accountId) {
                acc.daysBeforeExpires = str;
                acc.envelopeExpiresDate = newDate;
            }
        });
        this.accountsWithFiles = updatedAccounts;
    }
    handleRegionalManagerChange(event) {
        this.selectedRegionalManager = event.detail.value;
        this.loadAccounts();
    }

    handleCountyChange(event) {
        this.selectedCounty = event.detail.value;
        this.loadAccounts();
    }

    handleCustomerNameChange(event) {
        this.customerNameFilter = event.detail.value;
        this.loadAccounts();
    }

    handleSupervisorChange(event) {
        this.selectedSupervisor = event.detail.value;
        this.loadAccounts();
    }

    handleContractYearChange(event) {
        const val = (event.detail.value || '').replace(/\D/g, '');
        if (!val) {
            this.contractYearFilter = '';
            this.loadAccounts();
            return;
        }
        this.contractYearFilter = val.slice(0, 4);
        this.loadAccounts();
    }

    // Clear all filters
    clearFilters() {
        this.selectedRegionalManager = '';
        this.selectedCounty = '';
        this.customerNameFilter = '';
        this.selectedSupervisor = '';
        this.contractYearFilter = String(new Date().getFullYear());
        this.loadAccounts();
    }

    // Getter: returns only accounts that have selected files
    get selectedFilesForModal() {
        if (!this.accountsWithFiles) return [];
        
        return this.accountsWithFiles
            .map(acc => {
                const selectedFiles = acc.files.filter(file => file.ToSent);
                if (selectedFiles.length > 0) {
                    return {
                        accountId: acc.accountId,
                        accountName: acc.accountName,
                        newClient: acc.newClient,
                        selectedFiles: selectedFiles
                    };
                }
                return null;
            })
            .filter(acc => acc !== null);
    }

    // Getter: check if any files are selected
    get hasSelectedFiles() {
        return this.selectedFilesForModal.length > 0;
    }

    // Getter: for disabling send button when no files selected
    get noFilesSelected() {
        return !this.hasSelectedFiles;
    }

    // Open confirmation modal
    openConfirmationModal() {
        this.showConfirmationModal = true;
    }

    // Close confirmation modal
    closeConfirmationModal() {
        this.showConfirmationModal = false;
    }

    // Handle file preview - opens file in new browser tab
    handlePreviewFile(event) {
        const fileId = event.target.dataset.fileId || event.currentTarget.dataset.fileId;
        
        if (!fileId) {
            console.error('No file ID found for preview');
            return;
        }

        // Open Salesforce file preview in new tab
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: fileId
            }
        }).then(url => {
            window.open(url, '_blank');
        });
    }

    // Confirm and submit files
    async handleConfirmSubmit() {
        this.closeConfirmationModal();
        await this.handleSubmit();
    }

    handleCheckboxChange(event) {
        const accountId = event.target.dataset.accountId;
        const fileId = event.target.dataset.fileId;
        const checked = event.target.checked;
        const fieldName = event.target.name;
        
        // Create a deep copy so reactivity works
        let updatedAccounts = JSON.parse(JSON.stringify(this.accountsWithFiles));

        updatedAccounts.forEach(account => {
            if (account.accountId === accountId) {
                if (fieldName === 'newClient') {
                    account.newClient = checked;
                }
                account.files.forEach(file => {
                    if (file.Id === fileId) {
                        file.ToSent = checked;
                    }
                });
            }
        });
        this.accountsWithFiles = updatedAccounts;
    }

    async handleUpdate() {
        console.log('[SendContracts] update', this.recordId, JSON.stringify(this.queryRecordIds || null));
        await this.loadAccounts();
    }

    async handleSubmit() {
        try {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Processing',
                message: 'Sending envelopes...',
                variant: 'info'
            }));

            const payload = this.accountsWithFiles.map(acc => ({
                ...acc,
                reminderValue: acc.reminderValue === 'custom' ? (acc.reminderCustomDays || '') : (acc.reminderValue || '')
            }));
            console.log(JSON.stringify(payload));
            
            await sendEnvelopeWithSignature({
                accountsWithFilesJSON: JSON.stringify(payload)
            });

            await this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Contract_Bid__c',
                    actionName: 'list'
                }
            });
        } catch (error) {
            console.error(error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error?.body?.message || error.message,
                variant: 'error'
            }));
        }
    }
}