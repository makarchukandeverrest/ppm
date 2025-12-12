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
    @api recordId;

    connectedCallback() {
        const urlParams = new URLSearchParams(window.location.search);
        this.recordId = urlParams.get('recordId');
        console.log('recordId from URL:', this.recordId);
    }

    @wire(getAccountsWithFiles, { recordId: '$recordId' })
    wiredAccounts(result) {
        this.wiredAccountsResult = result;
        const { error, data } = result;
        console.log('data', JSON.stringify(data));
        
        if (data) {
            this.accountsWithFiles = data;
            if (data.length === 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Info',
                    message: 'No contracts found with active stages or no files attached.',
                    variant: 'info',
                    mode: 'dismissable'
                }));
            }
        } else if (error) {
            console.error('Error loading accounts with files:', error);
        }
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
        // try {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Processing',
                message: 'Sending envelopes. You will be redirected.',
                variant: 'info',
                mode: 'dismissable'
            }));
            
            await sendEnvelopeWithSignature({ accountsWithFilesJSON: JSON.stringify(this.accountsWithFiles) });
            
            this.error = undefined;
            
            await this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Contract_Bid__c',
                    actionName: 'list'
                }
            });
            
        // } catch (error) {
        //     this.error = error;
        //     // Make sure you have a proper logger imported
        //     console.error('Error sending envelopes:', error);
        //     this.dispatchEvent(new ShowToastEvent({
        //         title: 'Error',
        //         message: error.message,
        //         variant: 'error',
        //         mode: 'dismissable'
        //     }));
        // }
    }
}