import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { FlowNavigationFinishEvent } from 'lightning/flowSupport';

import getInitData from '@salesforce/apex/ContractMassSendController.getInitData';
import sendContracts from '@salesforce/apex/ContractMassSendController.sendContracts';
import getTemplateDetails from '@salesforce/apex/ContractMassSendController.getTemplateDetails';

export default class ContractMassSend extends NavigationMixin(LightningElement) {

    /* =====================================================
       OPTIONAL INPUTS (fallback only)
    ===================================================== */
    @api recordId;
    @api selectedRecordIds = [];

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

    // Track if no customers were provided at startup
    noCustomersProvided = true;

    // customerId -> Set(contentVersionId)
    selectedContractVersionIdsByCustomer = new Map();

    /* =====================================================
       READ IDS FROM URL (Custom Tab / Navigation)
    ===================================================== */
    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        if (pageRef?.state?.ids && !this.inputIds.length) {
            this.inputIds = pageRef.state.ids.split(',');
            this.noCustomersProvided = false;
            // Load data immediately
            this.loadData();
        }
    }

    /* =====================================================
       FALLBACKS (Record Action / Flow / tests)
    ===================================================== */
    connectedCallback() {
        console.log('contractMassSend connectedCallback');
        console.log('customersData:', this.customersData);
        console.log('flowRecords:', this.flowRecords);
        console.log('recordId:', this.recordId);
        console.log('selectedRecordIds:', this.selectedRecordIds);

        // Priority 1: customersData (Single String, new approach)
        if (this.customersData) {
            try {
                const jsonString = `[${this.customersData.replace(/,\s*$/, '')}]`;
                console.log('Parsed jsonString:', jsonString);
                const parsedObjs = JSON.parse(jsonString);
                console.log('Parsed objects:', parsedObjs);

                this.inputIds = parsedObjs
                    .map(obj => obj.accountId)
                    .filter(id => !!id);

                if (this.inputIds.length > 0) {
                    this.noCustomersProvided = false;
                    this.loadData();
                }
            } catch (error) {
                console.error('Error parsing customersData', error);
                this.toast('Error', 'Invalid customersData: ' + error.message, 'error');
            }
        
        // Priority 2: flowRecords (Array, legacy)
        } else if (this.flowRecords && this.flowRecords.length > 0) {
            try {
                this.inputIds = this.flowRecords.map(jsonStr => {
                    const obj = JSON.parse(jsonStr);
                    return obj.accountId;
                }).filter(id => !!id);

                if (this.inputIds.length > 0) {
                    this.noCustomersProvided = false;
                    this.loadData();
                }
            } catch (error) {
                console.error('Error parsing flowRecords', error);
                this.toast('Error', 'Invalid flowRecords: ' + error.message, 'error');
            }
        
        // Priority 3: Direct Record ID (Quick Action)
        } else if (!this.inputIds.length && this.recordId) {
            this.inputIds = [this.recordId];
            this.noCustomersProvided = false;
            this.loadData();
        
        // Priority 4: Selected Records (List View wrapper)
        } else if (
            !this.inputIds.length &&
            this.selectedRecordIds &&
            this.selectedRecordIds.length
        ) {
            this.inputIds = [...this.selectedRecordIds];
            this.noCustomersProvided = false;
            this.loadData();
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
    get noRecordsProvided() {
        return this.noCustomersProvided;
    }

    get sendDisabled() {
        if (this.isLoading) return true;
        if (!this.selectedTemplateId) return true;

        for (const setIds of this.selectedContractVersionIdsByCustomer.values()) {
            if (setIds && setIds.size > 0) return false;
        }
        return true;
    }

    contractColumns = [
        { label: 'File Title', fieldName: 'title', type: 'text' },
        { label: 'Version', fieldName: 'versionNumber', type: 'number' },
        { label: 'File Type', fieldName: 'fileExtension', type: 'text' }
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
                selectedRows: (c.contracts || []).map(cv => cv.contentVersionId) // Pre-select all
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

    handleContractSelection(event) {
        const customerId = event.target.dataset.customerId;
        const selectedRows = event.detail.selectedRows || [];

        const setIds = new Set(
            selectedRows.map(r => r.contentVersionId)
        );
        this.selectedContractVersionIdsByCustomer.set(customerId, setIds);
        
        // Update the customer's selectedRows for UI binding
        this.customers = this.customers.map(c => {
            if (c.customerId === customerId) {
                return {
                    ...c,
                    selectedRows: Array.from(setIds)
                };
            }
            return c;
        });
    }

    /* =====================================================
       SEND
    ===================================================== */
    async handleSend() {
        this.isLoading = true;

        try {
            const payload = [];

            for (const c of this.customers) {
                const setIds =
                    this.selectedContractVersionIdsByCustomer.get(c.customerId);
                const ids = setIds ? Array.from(setIds) : [];

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
                'Contracts were processed.',
                'success'
            );
            
            // Close the component/tab
            this.closeComponent();

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
        // Try Flow finish event first (for Screen Flow)
        try {
            this.dispatchEvent(new FlowNavigationFinishEvent());
            return;
        } catch (e) {
            console.log('Not in a Flow context');
        }

        // Try to close as a quick action/modal
        try {
            this.dispatchEvent(new CloseActionScreenEvent());
            return;
        } catch (e) {
            console.log('Not a quick action context');
        }

        // If nothing else works, navigate away
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Contract_Bid__c',
                actionName: 'home'
            }
        });
    }
}