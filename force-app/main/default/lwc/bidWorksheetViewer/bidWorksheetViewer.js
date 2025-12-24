import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import getBidWorksheets from '@salesforce/apex/BidWorksheetController.getBidWorksheets';

export default class BidWorksheetViewer extends NavigationMixin(LightningElement) {

    @api recordId;

    wiredResult;
    files = [];
    isLoading = false;
    error;

    /* =========================
       LOAD FILES
    ========================= */

    @wire(getBidWorksheets, { customerId: '$recordId' })
    wiredFiles(result) {
        this.wiredResult = result;
        const { data, error } = result;
        this.isLoading = true;

        if (data) {
            this.files = data.map(file => ({
                ...file,
                iconName: this.getFileIcon(file.fileExtension),
                formattedSize: this.formatFileSize(file.fileSize),
                formattedDate: this.formatDate(file.lastModified)
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.files = [];
        }

        this.isLoading = false;
    }

    /* =========================
       GETTERS
    ========================= */

    get hasFiles() {
        return this.files.length > 0;
    }

    /* =========================
       EVENTS
    ========================= */

    handlePreview(event) {
        const versionId = event.currentTarget.dataset.fileId;
        const file = this.files.find(f => f.contentVersionId === versionId);
        
        if (file && file.contentDocumentId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: {
                    pageName: 'filePreview'
                },
                state: {
                    recordIds: file.contentDocumentId,
                    selectedRecordId: file.contentDocumentId
                }
            });
        }
    }

    handleDownload(event) {
        const fileId = event.currentTarget.dataset.fileId;
        window.open(
            `/sfc/servlet.shepherd/version/download/${fileId}`,
            '_blank'
        );
    }

    handleRefresh() {
        this.isLoading = true;

        refreshApex(this.wiredResult)
            .finally(() => {
                this.isLoading = false;
            });
    }

    /* =========================
       HELPERS
    ========================= */

    formatFileSize(bytes) {
        if (!bytes) return '0 B';
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1048576) return Math.round(bytes / 1024) + ' KB';
        return Math.round(bytes / 1048576 * 10) / 10 + ' MB';
    }

    formatDate(dateString) {
        const date = new Date(dateString);
        return date.toLocaleDateString();
    }

    getFileIcon(ext) {
        return ext === 'docx' ? 'doctype:word' : 'doctype:unknown';
    }
}
