import { LightningElement, api } from 'lwc';

export default class UnifiedActivityFeedFilters extends LightningElement {
    @api selectedType;
    @api typeOptions;
    @api searchTerm;

    handleTypeChange(event) {
        this.dispatchEvent(new CustomEvent('typechange', { detail: { value: event.detail.value } }));
    }

    handleSearchChange(event) {
        this.dispatchEvent(new CustomEvent('searchchange', { detail: { value: event.target.value } }));
    }
}
