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
    }

    @wire(getAccountsWithFiles, { recordId: '$recordId' })
    wiredAccounts(result) {
        this.wiredAccountsResult = result;
        const { error, data } = result;
        
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
        this.accountsWithFiles = null;
    await refreshApex(this.wiredAccountsResult);
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
    
            // 3. Отправляем только отфильтрованные данные
            await sendEnvelopeWithSignature({ 
                accountsWithFilesJSON: JSON.stringify(filteredData),
                recordId: this.recordId // Добавляем recordId если нужно в Apex
            });
            
            this.error = undefined;
            
            // 4. Показываем success сообщение перед редиректом
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Envelopes sent successfully!',
                variant: 'success',
                mode: 'dismissable'
            }));
            
            // 5. Редирект с небольшой задержкой, чтобы пользователь увидел сообщение
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