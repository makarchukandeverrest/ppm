import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createChatterPost from '@salesforce/apex/UnifiedActivityController.createChatterPost';

export default class UnifiedActivityComposer extends LightningElement {
    @api recordId;
    body = '';
    isPosting = false;

    get isEmpty() {
        return !this.body || this.body.trim().length === 0;
    }

    get isDisabled() {
        return this.isEmpty || this.isPosting;
    }

    handleBodyChange(event) {
        this.body = event.target.value;
    }

    async handlePost() {
        if (this.isEmpty) return;

        this.isPosting = true;
        try {
            await createChatterPost({ recordId: this.recordId, body: this.body.trim() });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Post created',
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('success'));
            this.body = '';
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error creating post',
                message: this.extractErrorMessage(error),
                variant: 'error'
            }));
        } finally {
            this.isPosting = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    extractErrorMessage(error) {
        if (error.body?.message) return error.body.message;
        if (typeof error.body === 'string') return error.body;
        if (error.message) return error.message;
        return 'An unknown error occurred';
    }
}
