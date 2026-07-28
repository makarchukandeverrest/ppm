import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getUnifiedActivities from '@salesforce/apex/UnifiedActivityController.getUnifiedActivities';

export default class UnifiedActivityFeed extends NavigationMixin(LightningElement) {
    @api recordId;
    @api sortDirection = 'DESC';
    @api maxItems = 500;

    wiredActivitiesResult;
    activities = [];
    isLoading = false;
    selectedType = 'All';
    searchTerm = '';
    showComposer = false;
    composerType = null;

    get hasRecordId() {
        return !!this.recordId;
    }

    get isAscending() {
        return this.sortDirection.toUpperCase() === 'ASC';
    }

    get sortIcon() {
        return this.isAscending ? 'utility:arrowup' : 'utility:arrowdown';
    }

    get sortLabel() {
        return this.isAscending ? 'Oldest first' : 'Newest first';
    }

    get typeOptions() {
        return [
            { label: 'All', value: 'All' },
            { label: 'Tasks', value: 'Task' },
            { label: 'Events', value: 'Event' },
            { label: 'Emails', value: 'EmailMessage' },
            { label: 'Chatter', value: 'FeedItem' }
        ];
    }

    get filteredActivities() {
        let result = this.activities || [];

        if (this.selectedType !== 'All') {
            result = result.filter(item => item.type === this.selectedType);
        }

        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            result = result.filter(item =>
                (item.title || '').toLowerCase().includes(term) ||
                (item.description || '').toLowerCase().includes(term) ||
                (item.createdByName || '').toLowerCase().includes(term)
            );
        }

        return result;
    }

    get hasActivities() {
        return this.filteredActivities.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.hasActivities;
    }

    get emptyMessage() {
        if (this.selectedType === 'All' && !this.searchTerm) {
            return 'No activities or chatter to show.';
        }
        if (this.searchTerm) {
            return 'No matches found. Try a different search term.';
        }
        return `No ${this.selectedType.toLowerCase()} records found.`;
    }

    @wire(getUnifiedActivities, { recordId: '$recordId', sortDirection: '$sortDirection' })
    wiredActivities(result) {
        this.wiredActivitiesResult = result;
        if (result.data) {
            this.activities = this.enrichActivities(result.data);
            this.isLoading = false;
        } else if (result.error) {
            this.isLoading = false;
            this.showError(result.error);
        }
    }

    enrichActivities(data) {
        return data.map(item => {
            const contentParts = (item.contentParts || []).map((part, index) => ({
                ...part,
                key: `${item.id}-${index}`,
                isText: part.partType === 'text',
                isImage: part.partType === 'image',
                isClickable: part.partType === 'image' && !!part.contentDocumentId
            }));

            return {
                ...item,
                contentParts,
                hasContentParts: contentParts.length > 0,
                displayDate: this.formatDate(item.createdDate),
                isTask: item.type === 'Task',
                isEvent: item.type === 'Event',
                isEmail: item.type === 'EmailMessage',
                isFeed: item.type === 'FeedItem'
            };
        });
    }

    formatDate(value) {
        if (!value) return '';
        const date = new Date(value);
        return date.toLocaleDateString(undefined, {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        });
    }

    handleSortToggle() {
        this.sortDirection = this.isAscending ? 'DESC' : 'ASC';
    }

    handleTypeChange(event) {
        this.selectedType = event.detail.value;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredActivitiesResult).finally(() => {
            this.isLoading = false;
        });
    }

    handleNewTask() {
        this.openRecordModal('NewTask', this.recordId);
    }

    handleNewEvent() {
        this.openRecordModal('NewEvent', this.recordId);
    }

    handleNewPost() {
        this.showComposer = true;
        this.composerType = 'chatter';
    }

    handleNewEmail() {
        this.openRecordModal('SendEmail', this.recordId);
    }

    handleItemClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this.openRecordPage(recordId);
    }

    handleImageClick(event) {
        event.stopPropagation();
        const contentDocumentId = event.currentTarget.dataset.id;
        if (!contentDocumentId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: contentDocumentId
            }
        });
    }

    handleImageKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleImageClick(event);
        }
    }

    openRecordModal(actionName, recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: {
                apiName: actionName
            },
            state: {
                recordId: recordId
            }
        });
    }

    openRecordPage(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }

    handleComposerCancel() {
        this.showComposer = false;
        this.composerType = null;
    }

    handleComposerSuccess() {
        this.showComposer = false;
        this.composerType = null;
        this.handleRefresh();
    }

    showError(error) {
        const message = this.extractErrorMessage(error);
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error loading activities',
            message: message,
            variant: 'error'
        }));
    }

    extractErrorMessage(error) {
        if (error.body?.message) return error.body.message;
        if (typeof error.body === 'string') return error.body;
        if (error.message) return error.message;
        return 'An unknown error occurred';
    }
}
