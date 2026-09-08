import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';

import getInitData from '@salesforce/apex/ContractMassSendController.getInitData';
import sendContracts from '@salesforce/apex/ContractMassSendController.sendContracts';
import getTemplateDetails from '@salesforce/apex/ContractMassSendController.getTemplateDetails';

export default class ContractMassSend extends NavigationMixin(LightningElement) {

    /* =====================================================
       OPTIONAL INPUTS (fallback only)
    ===================================================== */
    _recordId;
    _selectedRecordIds = [];

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.tryInitFromComponentInputs();
    }

    @api
    get selectedRecordIds() {
        return this._selectedRecordIds;
    }
    set selectedRecordIds(value) {
        this._selectedRecordIds = Array.isArray(value) ? value : [];
        this.tryInitFromComponentInputs();
    }

    /* =====================================================
       STATE
    ===================================================== */
    @track customers = [];
    @track templateOptions = [];
    @track sendLog = [];

    selectedTemplateId;
    subject = '';
    body = '';

    isLoading = false;
    accessError;

    // 🔑 Source of truth for Apex (Contract Bids or Accounts)
    inputIds = [];

    // Inputs from Flow (Legacy - String[])
    @api flowRecords;

    // Inputs from Flow (New - Single String, like accountListSend)
    @api customersData;

    // Prevent duplicate loading
    hasLoaded = false;

    // customerId -> Set(contentVersionId)
    selectedContractVersionIdsByCustomer = new Map();

    /* =====================================================
       READ IDS FROM URL (Custom Tab / Navigation)
    ===================================================== */
    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        if (!pageRef) {
            return;
        }

        if (pageRef.state?.ids && !this.inputIds.length) {
            this.inputIds = pageRef.state.ids.split(',');
            this.loadData();
            return;
        }

        const state = pageRef.state || {};
        const attrs = pageRef.attributes || {};
        const rid = state.recordId || state.c__recordId || attrs.recordId;
        if (rid) {
            this.recordId = rid;
        }
    }

    /* =====================================================
       FALLBACKS (Record Action / Flow / tests)
    ===================================================== */
    connectedCallback() {
        if (!this._recordId) {
            const urlParams = new URLSearchParams(window.location.search);
            const fromUrl =
                urlParams.get('recordId') || urlParams.get('c__recordId');
            if (fromUrl) {
                this._recordId = fromUrl;
            }
        }

        this.tryInitFromComponentInputs();
    }

    tryInitFromComponentInputs() {
        // Priority 1: customersData (Single String, new approach)
        if (this.customersData) {
            try {
                const jsonString = `[${this.customersData.replace(/,\s*$/, '')}]`;
                const parsedObjs = JSON.parse(jsonString);

                this.inputIds = parsedObjs
                    .map(obj => obj.accountId)
                    .filter(id => !!id);

                if (this.inputIds.length > 0) {
                    this.loadData();
                }
            } catch (error) {
                console.error('Error parsing customersData', error);
                this.toast('Error', 'Invalid customersData: ' + error.message, 'error');
            }
            return;
        }

        // Priority 2: flowRecords (Array, legacy)
        if (this.flowRecords && this.flowRecords.length > 0) {
            try {
                this.inputIds = this.flowRecords
                    .map(jsonStr => {
                        const obj = JSON.parse(jsonStr);
                        return obj.accountId;
                    })
                    .filter(id => !!id);

                if (this.inputIds.length > 0) {
                    this.loadData();
                }
            } catch (error) {
                console.error('Error parsing flowRecords', error);
                this.toast('Error', 'Invalid flowRecords: ' + error.message, 'error');
            }
            return;
        }

        // Priority 3: Direct Record ID (record page / quick action — often set after connect)
        if (this.recordId) {
            if (!this.inputIds.length) {
                this.inputIds = [this.recordId];
                this.loadData();
            }
            return;
        }

        // Priority 4: Selected Records (List View wrapper)
        if (this.selectedRecordIds && this.selectedRecordIds.length) {
            if (!this.inputIds.length) {
                this.inputIds = [...this.selectedRecordIds];
                this.loadData();
            }
        }
    }


    /* =====================================================
       GETTER FOR SELECTED ROWS
    ===================================================== */
    getSelectedRows(customerId) {
        const setIds = this.selectedContractVersionIdsByCustomer.get(customerId);
        return setIds ? Array.from(setIds) : [];
    }

    /* =====================================================
       UI HELPERS
    ===================================================== */
    get sendDisabled() {
        if (this.isLoading) return true;
        if (!this.selectedTemplateId) return true;

        // Check if any contract is selected
        for (const c of this.customers) {
            if ((c.contracts || []).some(contract => contract.isSelected)) {
                return false;
            }
        }
        return true;
    }

    contractColumns = [
        { label: 'File Title', fieldName: 'title', type: 'text' },
        { label: 'Version', fieldName: 'versionNumber', type: 'number' },
        { label: 'File Type', fieldName: 'fileExtension', type: 'text' },
        {
            type: 'button',
            typeAttributes: {
                label: 'Preview',
                name: 'preview',
                variant: 'base',
                iconName: 'utility:preview',
                iconPosition: 'left'
            }
        }
    ];

    logColumns = [
        { label: 'Customer', fieldName: 'customerName', type: 'text' },
        { label: 'File Title', fieldName: 'fileTitle', type: 'text' },
        { label: 'Version', fieldName: 'versionNumber', type: 'number' },
        { label: 'Status', fieldName: 'status', type: 'text' },
        { label: 'Message', fieldName: 'message', type: 'text' }
    ];

    /* =====================================================
       LOAD DATA
    ===================================================== */
    async loadData() {
        this.isLoading = true;
        this.accessError = undefined;

        try {
            const res = await getInitData({
                inputIds: this.inputIds
            });

            if (!res.hasAccess) {
                this.accessError =
                    res.accessMessage ||
                    'You do not have permission to use this feature.';
                this.customers = [];
                this.templateOptions = [];
                return;
            }

            this.templateOptions = (res.templates || []).map(t => ({
                label: t.name,
                value: t.id
            }));

            this.customers = (res.customers || []).map(c => ({
                ...c,
                expanded: true,
                isExpandedLabel: c.expanded ? 'Collapse' : 'Expand',
                contracts: (c.contracts || []).map(cv => ({
                    ...cv,
                    isSelected: true // Pre-select all contracts
                }))
            }));

            this.sendLog = res.recentLogs || [];
            this.selectedContractVersionIdsByCustomer = new Map();

            // Default: preselect all contracts
            this.customers.forEach(c => {
                const setIds = new Set();
                (c.contracts || []).forEach(cv =>
                    setIds.add(cv.contentVersionId)
                );
                this.selectedContractVersionIdsByCustomer.set(
                    c.customerId,
                    setIds
                );
            });

        } catch (e) {
            this.toast('Error', this.normalizeError(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /* =====================================================
       EVENTS
    ===================================================== */
    async handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        this.isLoading = true;

        try {
            const details = await getTemplateDetails({ templateId: this.selectedTemplateId });
            this.subject = details.subject;
            this.body = details.body;
        } catch (error) {
            this.toast('Error', 'Could not load template details', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleSubjectChange(event) {
        this.subject = event.detail.value;
    }

    handleBodyChange(event) {
        this.body = event.detail.value;
    }

    toggleCustomer(event) {
        const customerId = event.currentTarget.dataset.id;
        this.customers = this.customers.map(c => {
            if (c.customerId === customerId) {
                return {
                    ...c,
                    expanded: !c.expanded,
                    isExpandedLabel: !c.expanded ? 'Collapse' : 'Expand'
                };
            }
            return c;
        });
    }

    // Handle contract checkbox change
    handleContractCheckbox(event) {
        const contractId = event.target.dataset.contractId;
        const customerId = event.target.dataset.customerId;
        const isChecked = event.target.checked;

        // Update customer contracts
        this.customers = this.customers.map(c => {
            if (c.customerId === customerId) {
                return {
                    ...c,
                    contracts: c.contracts.map(contract => {
                        if (contract.contentVersionId === contractId) {
                            return { ...contract, isSelected: isChecked };
                        }
                        return contract;
                    })
                };
            }
            return c;
        });

        // Update selection map
        const setIds = this.selectedContractVersionIdsByCustomer.get(customerId) || new Set();
        if (isChecked) {
            setIds.add(contractId);
        } else {
            setIds.delete(contractId);
        }
        this.selectedContractVersionIdsByCustomer.set(customerId, setIds);
    }

    // Handle file preview - opens file in new browser tab
    handlePreviewFile(event) {
        const fileId = event.target.dataset.fileId || event.currentTarget.dataset.fileId;
        
        if (!fileId) {
            console.error('No file ID found for preview');
            return;
        }

        // Open Salesforce file preview in new tab using direct URL
        const baseUrl = window.location.origin;
        const previewUrl = `${baseUrl}/lightning/page/filePreview?selectedRecordId=${fileId}`;
        window.open(previewUrl, '_blank');
    }

    /* =====================================================
       SEND
    ===================================================== */
    async handleSend() {
        this.isLoading = true;

        try {
            const payload = [];

            for (const c of this.customers) {
                const ids = (c.contracts || [])
                    .filter(contract => contract.isSelected)
                    .map(contract => contract.contentVersionId);

                if (ids.length > 0) {
                    payload.push({
                        customerId: c.customerId,
                        contentVersionIds: ids
                    });
                }
            }

            if (!payload.length) {
                this.toast(
                    'Nothing to send',
                    'Please select at least one contract.',
                    'warning'
                );
                return;
            }

            const res = await sendContracts({
                inputIds: this.inputIds,
                emailTemplateId: this.selectedTemplateId,
                requestJson: JSON.stringify(payload),
                subject: this.subject,
                body: this.body
            });

            this.sendLog = res.logs || [];
            this.toast(
                'Sent',
                'Contracts were processed. See Send History for details.',
                'success'
            );
            
            // Close the component/tab
            // this.closeComponent();

        } catch (e) {
            this.toast('Error', this.normalizeError(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /* =====================================================
       UTILS
    ===================================================== */
    toast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    normalizeError(e) {
        if (!e) return 'Unknown error';
        if (Array.isArray(e.body)) {
            return e.body.map(x => x.message).join(', ');
        }
        return e.body?.message || e.message || JSON.stringify(e);
    }
    
    closeComponent() {
        try {
            // Try to close as a quick action/modal
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (e) {
            // If not a quick action, try to close the tab
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Contract_Bid__c',
                    actionName: 'home'
                }
            });
        }
    }
}