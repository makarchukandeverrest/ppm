import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getUnifiedActivities from '@salesforce/apex/UnifiedActivityController.getUnifiedActivities';

const SEARCH_DEBOUNCE_MS = 300;

export default class UnifiedActivityFeed extends NavigationMixin(LightningElement) {
    @api sortDirection = 'DESC';
    @api maxItems = 20;

    _recordId;
    activities = [];
    totalCount = 0;
    nextOffset = 0;
    hasMore = false;
    isLoading = false;
    isLoadingMore = false;
    selectedType = 'All';
    searchTerm = '';
    showComposer = false;
    searchTimeout;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        if (this._recordId !== value) {
            this._recordId = value;
            if (value) {
                this.loadActivities(true);
            } else {
                this.resetState();
            }
        }
    }

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

    get hasActivities() {
        return this.activities.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.isLoadingMore && !this.hasActivities;
    }

    get showLoadMore() {
        return this.hasMore && this.hasActivities && !this.isLoading;
    }

    get countLabel() {
        if (this.totalCount === 0) {
            return '0';
        }
        if (this.activities.length >= this.totalCount) {
            return String(this.totalCount);
        }
        return `${this.activities.length} of ${this.totalCount}`;
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

    connectedCallback() {
        if (this.recordId) {
            this.loadActivities(true);
        }
    }

    disconnectedCallback() {
        if (this.searchTimeout) {
            clearTimeout(this.searchTimeout);
        }
    }

    resetState() {
        this.activities = [];
        this.totalCount = 0;
        this.nextOffset = 0;
        this.hasMore = false;
        this.isLoading = false;
        this.isLoadingMore = false;
    }

    async loadActivities(reset) {
        if (!this.recordId) {
            return;
        }

        if (reset) {
            this.nextOffset = 0;
            this.isLoading = true;
        } else {
            this.isLoadingMore = true;
        }

        try {
            const result = await getUnifiedActivities({
                recordId: this.recordId,
                sortDirection: this.sortDirection,
                pageSize: this.maxItems,
                offset: reset ? 0 : this.nextOffset,
                activityType: this.selectedType,
                searchTerm: this.searchTerm
            });

            const enriched = this.enrichActivities(result.items || []);
            this.activities = reset ? enriched : [...this.activities, ...enriched];
            this.totalCount = result.totalCount || 0;
            this.hasMore = result.hasMore || false;
            this.nextOffset = result.nextOffset || this.activities.length;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
            this.isLoadingMore = false;
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
        this.loadActivities(true);
    }

    handleTypeChange(event) {
        this.selectedType = event.detail.value;
        this.loadActivities(true);
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;

        if (this.searchTimeout) {
            clearTimeout(this.searchTimeout);
        }

        this.searchTimeout = setTimeout(() => {
            this.loadActivities(true);
        }, SEARCH_DEBOUNCE_MS);
    }

    handleRefresh() {
        this.loadActivities(true);
    }

    handleLoadMore() {
        if (!this.hasMore || this.isLoadingMore) {
            return;
        }
        this.loadActivities(false);
    }

    handleNewTask() {
        this.openRecordModal('NewTask', this.recordId);
    }

    handleNewEvent() {
        this.openRecordModal('NewEvent', this.recordId);
    }

    handleNewPost() {
        this.showComposer = true;
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
    }

    handleComposerSuccess() {
        this.showComposer = false;
        this.loadActivities(true);
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
