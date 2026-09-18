import { LightningElement, api } from 'lwc';

export default class UnifiedActivityFeedActivityList extends LightningElement {
    @api activities = [];
    @api isLoading = false;
    @api isLoadingMore = false;
    @api showLoadMore = false;
    @api emptyMessage = '';

    expandedActivityIds = [];

    get hasActivities() {
        return this.activities.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.isLoadingMore && !this.hasActivities;
    }

    get displayActivities() {
        const expandedIds = new Set(this.expandedActivityIds);
        return (this.activities || []).map(item => {
            const isExpanded = expandedIds.has(item.id);
            const isCollapsible = item.isCollapsibleBody === true;
            return {
                ...item,
                isExpanded,
                showPreview: isCollapsible && !isExpanded && !!item.bodyPreview,
                showCollapsedStatus: isCollapsible && !isExpanded && !!item.status,
                showFullBody: !isCollapsible || isExpanded,
                toggleLabel: isExpanded ? 'Hide email body' : 'Show email body',
                expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                expandAria: isExpanded ? 'true' : 'false'
            };
        });
    }

    handleToggleBody(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) {
            return;
        }
        if (this.expandedActivityIds.includes(recordId)) {
            this.expandedActivityIds = this.expandedActivityIds.filter(id => id !== recordId);
        } else {
            this.expandedActivityIds = [...this.expandedActivityIds, recordId];
        }
    }

    handleItemClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('itemclick', { detail: { recordId } }));
    }

    handleImageClick(event) {
        event.stopPropagation();
        const contentDocumentId = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('imageclick', { detail: { contentDocumentId } }));
    }

    handleImageKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleImageClick(event);
        }
    }

    handleLoadMore() {
        this.dispatchEvent(new CustomEvent('loadmore'));
    }
}
