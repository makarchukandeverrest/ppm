import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import { getRecord } from 'lightning/uiRecordApi';
import getUnifiedActivities from '@salesforce/apex/UnifiedActivityController.getUnifiedActivities';

const SEARCH_DEBOUNCE_MS = 300;
const WHO_ID_OBJECTS = new Set(['Contact', 'Lead']);

export default class UnifiedActivityFeed extends NavigationMixin(LightningElement) {
    @api sortDirection = 'DESC';
    @api maxItems = 20;
    @api relatedRecordConfig = '';
    @api currentRecordLabel = '';

    _recordId;
    objectApiName;
    refreshHandlerId;
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

    @wire(getRecord, { recordId: '$recordId', layoutTypes: ['Compact'] })
    wiredRecord({ data }) {
        if (data) {
            this.objectApiName = data.apiName;
        }
    }

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

    get countLabel() {
        if (this.totalCount === 0) {
            return '0';
        }
        if (this.activities.length >= this.totalCount) {
            return String(this.totalCount);
        }
        return `${this.activities.length} of ${this.totalCount}`;
    }

    get showLoadMore() {
        return this.hasMore && this.activities.length > 0 && !this.isLoading;
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
        this.refreshHandlerId = registerRefreshHandler(this, this.handleRefreshView.bind(this));
        if (this.recordId) {
            this.loadActivities(true);
        }
    }

    disconnectedCallback() {
        if (this.searchTimeout) {
            clearTimeout(this.searchTimeout);
        }
        if (this.refreshHandlerId) {
            unregisterRefreshHandler(this.refreshHandlerId);
        }
    }

    handleRefreshView() {
        return this.loadActivities(true)
            .then(() => true)
            .catch(() => false);
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
                searchTerm: this.searchTerm,
                relatedRecordConfig: this.relatedRecordConfig,
                currentRecordLabel: this.currentRecordLabel
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
                hasDescription: !!(item.description && String(item.description).trim()),
                hasDisplayBody: contentParts.length > 0 || !!(item.description && String(item.description).trim()),
                showSourceLabel: this.showSourceLabels && !!item.sourceLabel,
                displayDate: this.formatDate(item.createdDate),
                isTask: item.type === 'Task',
                isEvent: item.type === 'Event',
                isEmail: item.type === 'EmailMessage',
                isFeed: item.type === 'FeedItem',
                attachmentCount: item.attachmentCount || 0,
                hasAttachments: item.type === 'EmailMessage' && (item.attachmentCount || 0) > 0,
                attachmentLabel: item.type === 'EmailMessage' && (item.attachmentCount || 0) > 0
                    ? ((item.attachmentCount === 1) ? '1 attachment' : `${item.attachmentCount} attachments`)
                    : ''
            };
        });
    }

    get showSourceLabels() {
        return !!this.relatedRecordConfig && this.relatedRecordConfig.trim().length > 0;
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
        this.searchTerm = event.detail.value;

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
        this.openNewActivityRecord('Task');
    }

    handleNewEvent() {
        this.openNewActivityRecord('Event');
    }

    handleNewPost() {
        this.showComposer = true;
    }

    handleNewEmail() {
        this.openGlobalQuickAction('Global.SendEmail');
    }

    getActivityDefaults() {
        if (WHO_ID_OBJECTS.has(this.objectApiName)) {
            return { WhoId: this.recordId };
        }
        return { WhatId: this.recordId };
    }

    openGlobalQuickAction(apiName) {
        if (!this.recordId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: { apiName },
            state: { recordId: this.recordId }
        });
    }

    openNewActivityRecord(objectApiName) {
        if (!this.recordId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName,
                actionName: 'new'
            },
            state: {
                defaultFieldValues: encodeDefaultFieldValues(this.getActivityDefaults()),
                navigationLocation: 'RELATED_LIST'
            }
        });
    }

    handleItemClick(event) {
        const recordId = event.detail.recordId;
        this.openRecordPage(recordId);
    }

    handleImageClick(event) {
        const contentDocumentId = event.detail.contentDocumentId;
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
