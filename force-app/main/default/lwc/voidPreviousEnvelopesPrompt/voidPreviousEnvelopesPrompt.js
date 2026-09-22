import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import STAGE_FIELD from '@salesforce/schema/Contract_Bid__c.Stage__c';
import getPreviousOpenEnvelopes from '@salesforce/apex/DocuSignEnvelopeVoidService.getPreviousOpenEnvelopes';
import voidPreviousOpenEnvelopes from '@salesforce/apex/DocuSignEnvelopeVoidService.voidPreviousOpenEnvelopes';

const STORAGE_PREFIX = 'voidPreviousEnvelopesPrompt';
const RETRY_DELAY_MS = 5000;
const RETRY_ATTEMPTS = 6;
const JUST_SENT_MINUTES = 10;

export default class VoidPreviousEnvelopesPrompt extends LightningElement {
    @api recordId;

    showModal = false;
    isVoiding = false;
    previousCount = 0;
    newestSubject = '';
    newestId;
    retryHandle;
    retriesRemaining = RETRY_ATTEMPTS;
    lastSeenStage;

    @wire(getRecord, { recordId: '$recordId', fields: [STAGE_FIELD] })
    wiredBid({ data }) {
        if (!data) {
            return;
        }
        const stage = data.fields && data.fields.Stage__c
            ? data.fields.Stage__c.value
            : null;
        if (stage !== this.lastSeenStage) {
            this.lastSeenStage = stage;
            this.retriesRemaining = RETRY_ATTEMPTS;
            this.checkForPreviousEnvelopes();
        }
    }

    disconnectedCallback() {
        this.clearRetry();
    }

    get modalMessage() {
        const envelopeWord = this.previousCount === 1 ? 'envelope' : 'envelopes';
        return (
            'A new contract envelope was sent. There ' +
            (this.previousCount === 1 ? 'is' : 'are') +
            ' ' +
            this.previousCount +
            ' previous open ' +
            envelopeWord +
            '. Void ' +
            (this.previousCount === 1 ? 'it' : 'them') +
            ' so the customer only has the latest contract to sign?'
        );
    }

    get voidButtonLabel() {
        return this.previousCount === 1
            ? 'Void previous envelope'
            : 'Void previous envelopes';
    }

    checkForPreviousEnvelopes() {
        if (!this.recordId || this.showModal || this.isVoiding) {
            return;
        }

        getPreviousOpenEnvelopes({ contractBidId: this.recordId })
            .then((result) => {
                const newestId = result && result.newest ? result.newest.id : null;
                const seenId = this.getSeenNewestId();

                if (!result || !result.hasPrevious || !newestId) {
                    this.rememberNewest(newestId);
                    this.scheduleRetry();
                    return;
                }

                const isNewEnvelope = seenId && seenId !== newestId;
                const isJustSentWithoutBaseline =
                    !seenId && this.isJustSent(result.newest.sentDate);

                if (!isNewEnvelope && !isJustSentWithoutBaseline) {
                    this.rememberNewest(newestId);
                    this.scheduleRetry();
                    return;
                }

                this.newestId = newestId;
                this.previousCount = result.previousCount;
                this.newestSubject = result.newest.subject || '';
                this.showModal = true;
                this.clearRetry();
            })
            .catch(() => {
                this.scheduleRetry();
            });
    }

    isJustSent(sentDate) {
        if (!sentDate) {
            return false;
        }
        const sentMs = new Date(sentDate).getTime();
        if (Number.isNaN(sentMs)) {
            return false;
        }
        return Date.now() - sentMs <= JUST_SENT_MINUTES * 60 * 1000;
    }

    scheduleRetry() {
        if (this.retriesRemaining <= 0) {
            return;
        }
        this.clearRetry();
        this.retriesRemaining -= 1;
        this.retryHandle = window.setTimeout(() => {
            this.checkForPreviousEnvelopes();
        }, RETRY_DELAY_MS);
    }

    clearRetry() {
        if (this.retryHandle) {
            window.clearTimeout(this.retryHandle);
            this.retryHandle = null;
        }
    }

    handleKeep() {
        this.rememberNewest(this.newestId);
        this.showModal = false;
    }

    handleVoid() {
        if (this.isVoiding) {
            return;
        }
        this.isVoiding = true;
        voidPreviousOpenEnvelopes({ contractBidId: this.recordId })
            .then((voidedCount) => {
                this.rememberNewest(this.newestId);
                this.showModal = false;
                const count = voidedCount || this.previousCount;
                this.showToast(
                    'Previous envelopes voided',
                    count +
                        ' previous envelope' +
                        (count === 1 ? ' was' : 's were') +
                        ' voided.',
                    'success'
                );
            })
            .catch((error) => {
                this.showToast(
                    'Could not void previous envelopes',
                    this.errorMessage(error),
                    'error'
                );
            })
            .finally(() => {
                this.isVoiding = false;
            });
    }

    seenStorageKey() {
        return STORAGE_PREFIX + ':seen:' + this.recordId;
    }

    getSeenNewestId() {
        try {
            return window.localStorage.getItem(this.seenStorageKey());
        } catch (ex) {
            return null;
        }
    }

    rememberNewest(newestId) {
        if (!newestId) {
            return;
        }
        try {
            window.localStorage.setItem(this.seenStorageKey(), newestId);
        } catch (ex) {
            // Ignore storage errors.
        }
    }

    errorMessage(error) {
        return (
            (error && error.body && error.body.message) ||
            (error && error.message) ||
            'Unknown error'
        );
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
