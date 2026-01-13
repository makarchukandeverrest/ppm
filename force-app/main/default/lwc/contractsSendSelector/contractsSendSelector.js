import { LightningElement, wire, track, api } from 'lwc';
import getAccountsWithFiles from '@salesforce/apex/AccountFilesController.getAccountsWithFiles';
import getFilterOptions from '@salesforce/apex/AccountFilesController.getFilterOptions';
import sendEnvelopeWithSignature from '@salesforce/apex/DocuSignEnvelopeService.sendEnvelopeWithSignature';
import { refreshApex } from '@salesforce/apex';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class ContractsSendSelector extends NavigationMixin(LightningElement) {
    @track accountsWithFiles;
    @track allAccountsWithFiles; // Store original data for reference
    error;
    wiredAccountsResult;
    @track isUpdating = false;
    @track showConfirmationModal = false;
    @api recordId;

    // Filter state
    @track selectedRegionalManager = '';
    @track selectedCounty = '';
    @track customerNameFilter = '';
    @track selectedSupervisor = '';

    // Filter options
    @track regionalManagerOptions = [];
    @track countyOptions = [];
    @track supervisorOptions = [];
    @track filtersLoaded = false;

    connectedCallback() {
        // If recordId is not set via @api, try to get it from URL
        if (!this.recordId) {
            const urlParams = new URLSearchParams(window.location.search);
            this.recordId = urlParams.get('recordId') || urlParams.get('c__recordId');
            console.log('recordId from URL:', this.recordId);
        }
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

    @wire(getAccountsWithFiles, { 
        recordId: '$recordId',
        regionalManagerId: '$selectedRegionalManager',
        county: '$selectedCounty',
        customerName: '$customerNameFilter',
        supervisorId: '$selectedSupervisor'
    })
    wiredAccounts(result) {
        this.wiredAccountsResult = result;

        const { error, data } = result;
        console.log('getAccountsWithFiles result:', data, 'recordId:', this.recordId);

        if (data) {
            this.accountsWithFiles = data;
            this.allAccountsWithFiles = data;

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
        } else if (error) {
            console.error('Error loading accounts with files:', error);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || 'Failed to load contracts',
                    variant: 'error',
                    mode: 'dismissable'
                })
            );
        }
    }

    // Check if any filters are active
    get hasActiveFilters() {
        return this.selectedRegionalManager || 
               this.selectedCounty || 
               this.customerNameFilter || 
               this.selectedSupervisor;
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

    // Handle filter changes
    handleRegionalManagerChange(event) {
        this.selectedRegionalManager = event.detail.value;
    }

    handleCountyChange(event) {
        this.selectedCounty = event.detail.value;
    }

    handleCustomerNameChange(event) {
        this.customerNameFilter = event.detail.value;
    }

    handleSupervisorChange(event) {
        this.selectedSupervisor = event.detail.value;
    }

    // Clear all filters
    clearFilters() {
        this.selectedRegionalManager = '';
        this.selectedCounty = '';
        this.customerNameFilter = '';
        this.selectedSupervisor = '';
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
        console.log('handleUpdate', this.recordId);
        
        try {
            this.isUpdating = true;
            await refreshApex(this.wiredAccountsResult);
        } catch (error) {
            this.error = error;
            console.error('Error refreshing data:', error);
        } finally {
            this.isUpdating = false;
        }
    }

    async handleSubmit() {
        try {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Processing',
                message: 'Sending envelopes...',
                variant: 'info'
            }));

            await sendEnvelopeWithSignature({
                accountsWithFilesJSON: JSON.stringify(this.accountsWithFiles)
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