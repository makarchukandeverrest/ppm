import { LightningElement, api, track } from 'lwc';
import sendEmails from '@salesforce/apex/AccountListSendController.sendEmails';

export default class AccountListSend extends LightningElement {
    @api customersEmail;

    @track attachedFiles = [];
    acceptedFormats = ['.pdf', '.png', '.jpg', '.jpeg', '.doc', '.docx'];

    customers = [];

    subject = '';
    body = '';
    isLoading = false;

    // Toast properties
    showToast = false;
    toastTitle = '';
    toastMessage = '';
    toastStyle = '';
    toastTimeout;

    connectedCallback() {
        if (!this.customersEmail) {
            this.customers = [];
            return;
        }

        try {
            // Ensure valid JSON array
            const jsonString = `[${this.customersEmail.replace(/,\s*$/, '')}]`;
            this.customers = JSON.parse(jsonString);
            console.log('Parsed customers:', JSON.stringify(this.customers));
            
        } catch (e) {
            console.error('Failed to parse customersEmail:', e);
            this.customers = [];
        }
    }

    get recipients() {
        if (!this.customersEmail) {
            return [];
        }

        // Collect all emails from all customer objects
        const allEmails = this.customers
            .map(cust => cust.email)              // get the 'email' field
            .filter(email => email)               // remove empty/null
            .flatMap(email => email.split(';'))   // split multiple emails in one string
            .map(email => email.trim())           // trim whitespace
            .filter(email => email);              // remove empty strings

        // Remove duplicates
        const uniqueEmails = [...new Set(allEmails)];

        // Map to LWC avatar objects
        return uniqueEmails.map(email => ({
            type: 'avatar',
            label: email,
            fallbackIconName: 'standard:user',
            variant: 'circle',
        }));
    }

    get accountIds() {
        return [...new Set(this.customers.map(c => c.accountId))];
    }


    handleSubjectChange(event) {
        this.subject = event.target.value;
    }

    handleBodyChange(event) {
        this.body = event.detail.value;
        console.log('Email body updated: ', JSON.stringify(this.body));
        
        // Detect if pasted/attached image or other embedded file exists
        if (this.containsAttachment(this.body)) {
            this.showCustomToast(
                'Error',
                'Attachments are not supported in this email. Please remove any images.',
                'error'
            );

            // Optional: strip images so they don't stay in the body
            this.body = this.stripImages(this.body);
            event.target.value = this.body;
        }
    }

    // Handle file upload
    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files.map(file => ({
            name: file.name,
            documentId: file.documentId
        }));
        console.log('Files uploaded: ', JSON.stringify(uploadedFiles));
        
        this.attachedFiles = [...this.attachedFiles, ...uploadedFiles];
    }

    containsAttachment(html) {
        // detects inline images or file embeds
        return html.includes('data:image') || html.includes('<img');
    }

    stripImages(html) {
        // remove <img> tags completely
        return html.replace(/<img[^>]*>/gi, '');
    }

    async handleSend() {
        // Validate inputs
        if (!this.subject || !this.body) {
            this.showCustomToast('Error', 'Please fill in all required fields', 'error');
            return;
        }

        if (!this.customersEmail) {
            this.showCustomToast('Error', 'At least one recipient is required', 'error');
            return;
        }

        this.isLoading = true;

        try {
            // Extract just the email addresses from the recipients array
            const emailAddresses = this.recipients.map(recipient => recipient.label).join(';');
            const fileIds = this.attachedFiles.map(f => f.documentId);

            const result = await sendEmails({
                accountIds: this.accountIds,
                recipients: emailAddresses, // Send just the semicolon-separated emails
                subject: this.subject,
                body: this.body,
                fileIds: fileIds
            });

            console.log('Email send result: ', JSON.stringify(result));
            
            if (result.isSuccess) {
                this.showCustomToast('Success', result.message, 'success');
                
                // Close the modal after successful send
                setTimeout(() => {
                    this.handleCancel();
                }, 2000);
            } else {
                this.showCustomToast('Error', result.message, 'error');
            }
        } catch (error) {
            console.error('Error sending email:', error);
            const errorMessage = this.extractErrorMessage(error);
            this.showCustomToast('Error', errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showCustomToast(title, message, variant) {
        // Clear any existing timeout
        if (this.toastTimeout) {
            clearTimeout(this.toastTimeout);
        }

        // Set toast properties
        this.toastTitle = title;
        this.toastMessage = message;
        
        // Set appropriate styling based on variant
        switch(variant) {
            case 'success':
                this.toastStyle = '--slds-c-toast-color-background: #4bca81; --slds-c-toast-color-border: #04844b; --slds-c-toast-text-color: #ffffff;';
                break;
            case 'error':
                this.toastStyle = '--slds-c-toast-color-background: #c23934; --slds-c-toast-color-border: #8a2924; --slds-c-toast-text-color: #ffffff;';
                break;
            case 'warning':
                this.toastStyle = '--slds-c-toast-color-background: #ffb75d; --slds-c-toast-color-border: #e29c3d; --slds-c-toast-text-color: #16325c;';
                break;
            default: // info
                this.toastStyle = '--slds-c-toast-color-background: #54698d; --slds-c-toast-color-border: #3e4e6c; --slds-c-toast-text-color: #ffffff;';
        }

        // Show toast
        this.showToast = true;

        // Auto-hide after 5 seconds
        this.toastTimeout = setTimeout(() => {
            this.hideToast();
        }, 5000);
    }

    hideToast() {
        this.showToast = false;
        if (this.toastTimeout) {
            clearTimeout(this.toastTimeout);
            this.toastTimeout = null;
        }
    }

    extractErrorMessage(error) {
        if (error.body) {
            if (error.body.message) {
                return error.body.message;
            }
            if (typeof error.body === 'string') {
                return error.body;
            }
        }
        if (error.message) {
            return error.message;
        }
        return 'An unknown error occurred';
    }

    handleCancel() {
        history.back();
    }

    handleItemRemove(event) {
        const label = event.detail.item.label;
        const currentEmails = this.customersEmail ? this.customersEmail.split(';').map(email => email.trim()) : [];
        
        const updatedEmails = currentEmails.filter(email => email !== label);
        this.customersEmail = updatedEmails.join('; ');
    }
}