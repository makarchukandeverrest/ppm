import { LightningElement, api } from 'lwc';

export default class UnifiedActivityFeedActivityList extends LightningElement {
    @api activities = [];
    @api isLoading = false;
    @api isLoadingMore = false;
    @api showLoadMore = false;
    @api emptyMessage = '';

    get hasActivities() {
        return this.activities.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.isLoadingMore && !this.hasActivities;
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
