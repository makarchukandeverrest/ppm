import { LightningElement, api } from 'lwc';

export default class CustomerTimeRangeEditor extends LightningElement {
    @api recordId;

    startTime = '';
    endTime = '';

    handleStartTimeChange(event) {
        this.startTime = event.target.value;
    }

    handleEndTimeChange(event) {
        this.endTime = event.target.value;
    }

    handleSave() {
        // Dispatch custom event or call Apex when save is implemented
        const detail = { startTime: this.startTime, endTime: this.endTime };
        this.dispatchEvent(new CustomEvent('save', { detail }));
    }
}
