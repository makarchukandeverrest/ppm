import { LightningElement,wire,track,api  } from 'lwc';
import getAccountsWithFiles from '@salesforce/apex/AccountFilesController.getAccountsWithFiles';
import sendEnvelopeWithSignature from '@salesforce/apex/DocuSignEnvelopeService.sendEnvelopeWithSignature';
import { refreshApex } from '@salesforce/apex';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class ContractsSendSelector extends NavigationMixin(LightningElement) {
    @track accountsWithFiles;
    error;
    wiredAccountsResult;
    @track isUpdating = false;
<<<<<<< HEAD
    @track showConfirmationModal = false;
    @api recordId;

    connectedCallback() {
        // If recordId is not set via @api, try to get it from URL
        if (!this.recordId) {
            const urlParams = new URLSearchParams(window.location.search);
            this.recordId = urlParams.get('recordId') || urlParams.get('c__recordId');
            console.log('recordId from URL:', this.recordId);
        }
    }


    @wire(getAccountsWithFiles, { recordId: '$recordId' })
    wiredAccounts(result) {
        this.wiredAccountsResult = result;

        const { error, data } = result;
        console.log('getAccountsWithFiles result:', data, 'recordId:', this.recordId);

        if (data) {
            this.accountsWithFiles = data;

            if (Array.isArray(data) && data.length === 0) {
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
        console.log('handleUpdate',this.recordId);
        
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
            const filteredData = this.accountsWithFiles
                .map(account => {
                    const accountCopy = { ...account };
                    accountCopy.files = account.files.filter(file => file.ToSent === true);
                    return accountCopy;
                })
                // remove accounts without selected files
                .filter(account => account.files && account.files.length > 0);
    
            if (filteredData.length === 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Warning',
                    message: 'Please select at least one file to send',
                    variant: 'warning',
                    mode: 'dismissable'
                }));
                return;
            }
    
            this.dispatchEvent(new ShowToastEvent({
                title: 'Processing',
                message: `Sending ${filteredData.reduce((sum, acc) => sum + acc.files.length, 0)} file(s) from ${filteredData.length} account(s)`,
                variant: 'info',
                mode: 'dismissable'
            }));
    
            await sendEnvelopeWithSignature({ 
                accountsWithFilesJSON: JSON.stringify(filteredData)
            });
            
            this.error = undefined;
            
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Envelopes sent successfully!',
                variant: 'success',
                mode: 'dismissable'
            }));
            
            setTimeout(() => {
                this[NavigationMixin.Navigate]({
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: 'Contract_Bid__c',
                        actionName: 'list'
                    }
                });
            }, 2000);
            
        } catch (error) {
            console.error('Error sending envelopes:', error);
            console.error('Error details:', JSON.stringify(error, null, 2));
            
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || error.message || 'Error sending envelopes',
                variant: 'error',
                mode: 'dismissable'
            }));
        }
    }
}