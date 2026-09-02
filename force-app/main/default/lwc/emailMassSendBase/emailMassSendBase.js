import { LightningElement, api, track, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import { CloseActionScreenEvent } from "lightning/actions";

import getInitData from "@salesforce/apex/ContractMassSendController.getInitData";
import getInitDataFiltered from "@salesforce/apex/ContractMassSendController.getInitDataFiltered";
import sendContracts from "@salesforce/apex/ContractMassSendController.sendContracts";
import getTemplateDetails from "@salesforce/apex/ContractMassSendController.getTemplateDetails";
import previewEmail from "@salesforce/apex/ContractMassSendController.previewEmail";
import getFilterOptions from "@salesforce/apex/AccountFilesController.getFilterOptions";

export default class EmailMassSendBase extends NavigationMixin(
  LightningElement
) {
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

  @api mode = "simple"; // 'contracts' | 'simple'

  selectedTemplateId;
  subject = "";
  body = "";

  isLoading = false;
  isUpdating = false;
  accessError;

  // Contract file filters (contracts mode — same as contractsSendSelector)
  @track selectedRegionalManager = "";
  @track selectedCounty = "";
  @track customerNameFilter = "";
  @track selectedSupervisor = "";
  @track contractYearFilter = String(new Date().getFullYear());
  @track regionalManagerOptions = [];
  @track countyOptions = [];
  @track supervisorOptions = [];
  filtersLoaded = false;

  // 🔑 Source of truth for Apex
  inputIds = [];

  // Inputs from Flow (Legacy - String[])
  @api flowRecords;

  // Inputs from Flow (New - Single String, like accountListSend)
  @api customersData;

  // Prevent duplicate loading
  hasLoaded = false;

  hoveredPreviewSubject;
  hoveredPreviewBody;
  hoveredCustomerId;
  isHoveredPreviewLoading = false;
  mergeFieldError = false;
  mergeFieldErrorMessage;

  // customerId -> Set(contentVersionId) (used in contracts mode)
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
      this.inputIds = pageRef.state.ids.split(",");
      this.loadData();
      return;
    }

    const state = pageRef.state || {};
    const attrs = pageRef.attributes || {};
    const rid =
      state.recordId ||
      state.c__recordId ||
      attrs.recordId;

    if (rid) {
      this.recordId = rid;
    }
  }

  /* =====================================================
       FALLBACKS (Record Action / Flow / tests)
    ===================================================== */
  connectedCallback() {
    // Tab / navigation: query string (modal quick actions often have no search params)
    if (!this._recordId) {
      const urlParams = new URLSearchParams(window.location.search);
      const fromUrl =
        urlParams.get("recordId") || urlParams.get("c__recordId");
      if (fromUrl) {
        this._recordId = fromUrl;
      }
    }

    this.tryInitFromComponentInputs();
    this.loadFilterOptions();
  }

  async loadFilterOptions() {
    if (!this.isContractsMode || this.filtersLoaded) {
      return;
    }
    try {
      const data = await getFilterOptions();
      this.regionalManagerOptions = [
        { label: "-- All --", value: "" },
        ...(data?.regionalManagers || []).map((opt) => ({
          label: opt.label,
          value: opt.value
        }))
      ];
      this.countyOptions = [
        { label: "-- All --", value: "" },
        ...(data?.counties || []).map((opt) => ({
          label: opt.label,
          value: opt.value
        }))
      ];
      this.supervisorOptions = [
        { label: "-- All --", value: "" },
        ...(data?.supervisors || []).map((opt) => ({
          label: opt.label,
          value: opt.value
        }))
      ];
      this.filtersLoaded = true;
    } catch (error) {
      console.error("Error loading filter options:", error);
    }
  }

  tryInitFromComponentInputs() {
    // Priority 1: customersData (Single String, new approach)
    if (this.customersData) {
      try {
        const jsonString = `[${this.customersData.replace(/,\s*$/, "")}]`;
        const parsedObjs = JSON.parse(jsonString);

        this.inputIds = parsedObjs
          .map((obj) => obj.accountId)
          .filter((id) => !!id);

        if (this.inputIds.length > 0) {
          this.loadData();
        }
      } catch (error) {
        console.error("Error parsing customersData", error);
        this.toast("Error", "Invalid customersData: " + error.message, "error");
      }
      return;
    }

    // Priority 2: flowRecords (Array, legacy)
    if (this.flowRecords && this.flowRecords.length > 0) {
      try {
        this.inputIds = this.flowRecords
          .map((jsonStr) => {
            const obj = JSON.parse(jsonStr);
            return obj.accountId;
          })
          .filter((id) => !!id);

        if (this.inputIds.length > 0) {
          this.loadData();
        }
      } catch (error) {
        console.error("Error parsing flowRecords", error);
        this.toast("Error", "Invalid flowRecords: " + error.message, "error");
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
       UI HELPERS
    ===================================================== */
  get sendDisabled() {
    if (this.isLoading) return true;
    if (!this.selectedTemplateId) return true;
    if (!this.customers.length) return true;

    // In contracts mode require at least one selected contract
    if (this.isContractsMode) {
      for (const c of this.customers) {
        if ((c.contracts || []).some((contract) => contract.isSelected)) {
          return false;
        }
      }
      return true;
    }

    // In simple mode only template + customers are required
    return false;
  }

  get logColumns() {
    if (this.isContractsMode) {
      return [
        { label: "Customer", fieldName: "customerName", type: "text" },
        { label: "File Title", fieldName: "fileTitle", type: "text" },
        { label: "Version", fieldName: "versionNumber", type: "number" },
        { label: "Status", fieldName: "status", type: "text" },
        { label: "Message", fieldName: "message", type: "text" }
      ];
    }
    return [
      { label: "Customer", fieldName: "customerName", type: "text" },
      { label: "Status", fieldName: "status", type: "text" },
      { label: "Message", fieldName: "message", type: "text" }
    ];
  }

  get hasActiveFilters() {
    const yearIsCustom =
      this.contractYearFilter &&
      this.contractYearFilter !== String(new Date().getFullYear());

    return (
      this.selectedRegionalManager ||
      this.selectedCounty ||
      this.customerNameFilter ||
      this.selectedSupervisor ||
      yearIsCustom
    );
  }

  get hasNoActiveFilters() {
    return !this.hasActiveFilters;
  }

  get showNoResultsWithFilters() {
    return (
      this.isContractsMode &&
      this.hasActiveFilters &&
      this.customers &&
      this.customers.length === 0
    );
  }

  /* =====================================================
       LOAD DATA
    ===================================================== */
  async loadData() {
    const showFullPageSpinner = !this.customers.length;
    if (showFullPageSpinner) {
      this.isLoading = true;
    } else {
      this.isUpdating = true;
    }
    this.accessError = undefined;

    try {
      const res = this.isContractsMode
        ? await getInitDataFiltered({
            inputIds: this.inputIds,
            regionalManagerId: this.selectedRegionalManager || null,
            county: this.selectedCounty || null,
            customerName: this.customerNameFilter || null,
            supervisorId: this.selectedSupervisor || null,
            contractYear: this.contractYearFilter || null
          })
        : await getInitData({
            inputIds: this.inputIds
          });

      if (!res.hasAccess) {
        this.accessError =
          res.accessMessage ||
          "You do not have permission to use this feature.";
        this.customers = [];
        this.templateOptions = [];
        return;
      }

      this.templateOptions = (res.templates || []).map((t) => ({
        label: t.name,
        value: t.id
      }));

      const previousById = new Map(
        (this.customers || []).map((c) => [c.customerId, c])
      );

      // Always keep basic customer structure
      this.customers = (res.customers || []).map((c) => {
        const prev = previousById.get(c.customerId);
        return {
          ...c,
          expanded: prev?.expanded ?? true,
          isExpandedLabel: prev?.expanded === false ? "Expand" : "Collapse",
          isHovered: false,
          isEditing: false,
          isEditContentLoading: false,
          emailSubjectOverride: prev?.emailSubjectOverride ?? null,
          emailBodyOverride: prev?.emailBodyOverride ?? null,
          contracts: (c.contracts || []).map((cv) => {
            const prevContract = (prev?.contracts || []).find(
              (p) => p.contentVersionId === cv.contentVersionId
            );
            return {
              ...cv,
              isSelected: prevContract ? prevContract.isSelected : true
            };
          })
        };
      });
      this.applyCustomerDisplayFields();

      this.sendLog = res.recentLogs || [];
      this.selectedContractVersionIdsByCustomer = new Map();

      // Default: preselect all contracts (contracts mode only)
      if (this.isContractsMode) {
        this.customers.forEach((c) => {
          const setIds = new Set();
          (c.contracts || []).forEach((cv) => {
            if (cv.isSelected) {
              setIds.add(cv.contentVersionId);
            }
          });
          this.selectedContractVersionIdsByCustomer.set(c.customerId, setIds);
        });
      }
    } catch (e) {
      this.toast("Error", this.normalizeError(e), "error");
    } finally {
      this.isLoading = false;
      this.isUpdating = false;
    }
  }

  /* =====================================================
       CONTRACT FILE FILTERS (contracts mode)
    ===================================================== */
  handleRegionalManagerChange(event) {
    this.selectedRegionalManager = event.detail.value;
    this.loadData();
  }

  handleCountyChange(event) {
    this.selectedCounty = event.detail.value;
    this.loadData();
  }

  handleCustomerNameChange(event) {
    this.customerNameFilter = event.detail.value;
    this.loadData();
  }

  handleSupervisorChange(event) {
    this.selectedSupervisor = event.detail.value;
    this.loadData();
  }

  handleContractYearChange(event) {
    const val = (event.detail.value || "").replace(/\D/g, "");
    if (!val) {
      this.contractYearFilter = "";
      this.loadData();
      return;
    }
    this.contractYearFilter = val.slice(0, 4);
    this.loadData();
  }

  clearFilters() {
    this.selectedRegionalManager = "";
    this.selectedCounty = "";
    this.customerNameFilter = "";
    this.selectedSupervisor = "";
    this.contractYearFilter = String(new Date().getFullYear());
    this.loadData();
  }

  /* =====================================================
       EVENTS
    ===================================================== */
  async handleTemplateChange(event) {
    this.selectedTemplateId = event.detail.value;
    this.isLoading = true;

    try {
      const details = await getTemplateDetails({
        templateId: this.selectedTemplateId
      });
      this.subject = details.subject;
      this.body = details.body;
      this.customers = this.customers.map((c) => ({
        ...c,
        emailSubjectOverride: null,
        emailBodyOverride: null
      }));
      this.applyCustomerDisplayFields();
    } catch {
      this.toast("Error", "Could not load template details", "error");
    } finally {
      this.isLoading = false;
    }
  }

  handleSubjectChange(event) {
    this.subject = event.detail.value;
    this.applyCustomerDisplayFields();
  }

  handleBodyChange(event) {
    this.body = event.detail.value;
    this.applyCustomerDisplayFields();
  }

  applyCustomerDisplayFields() {
    this.customers = this.customers.map((c) => ({
      ...c,
      displaySubject:
        c.emailSubjectOverride != null ? c.emailSubjectOverride : this.subject,
      displayBody:
        c.emailBodyOverride != null ? c.emailBodyOverride : this.body
    }));
  }

  handleCustomerSubjectChange(event) {
    const customerId = event.currentTarget.dataset.customerId;
    const value = event.detail.value;
    this.customers = this.customers.map((c) => {
      if (c.customerId !== customerId) {
        return c;
      }
      return {
        ...c,
        emailSubjectOverride: value
      };
    });
    this.applyCustomerDisplayFields();
  }

  handleCustomerBodyChange(event) {
    const customerId = event.currentTarget.dataset.customerId;
    const value = event.detail.value;
    this.customers = this.customers.map((c) => {
      if (c.customerId !== customerId) {
        return c;
      }
      return {
        ...c,
        emailBodyOverride: value
      };
    });
    this.applyCustomerDisplayFields();
  }

  async handleCustomerResetEmail(event) {
    const customerId = event.currentTarget.dataset.customerId;
    if (!this.selectedTemplateId) {
      return;
    }
    this.customers = this.customers.map((c) => ({
      ...c,
      isEditContentLoading: c.customerId === customerId
    }));
    await this.loadMergedEmailForCustomer(customerId);
  }

  /**
   * Loads fully merged subject/body for this recipient (same output as preview),
   * for editing as final text — not raw template merge fields.
   */
  async loadMergedEmailForCustomer(customerId) {
    const row = this.customers.find((c) => c.customerId === customerId);
    try {
      const res = await previewEmail({
        emailTemplateId: this.selectedTemplateId,
        customerId,
        contactId: null,
        workOrderId: row?.workOrderId || null,
        subject: "",
        body: ""
      });

      this.customers = this.customers.map((c) => {
        if (c.customerId !== customerId) {
          return c;
        }
        return {
          ...c,
          emailSubjectOverride: res.subject,
          emailBodyOverride: res.body,
          isEditContentLoading: false
        };
      });
      this.applyCustomerDisplayFields();
    } catch (e) {
      this.toast("Error", this.normalizeError(e), "error");
      this.customers = this.customers.map((c) => ({
        ...c,
        isEditing:
          c.customerId === customerId ? false : c.isEditing,
        isEditContentLoading: false
      }));
    }
  }

  toggleCustomer(event) {
    const customerId = event.currentTarget.dataset.id;
    this.customers = this.customers.map((c) => {
      if (c.customerId === customerId) {
        return {
          ...c,
          expanded: !c.expanded,
          isExpandedLabel: !c.expanded ? "Collapse" : "Expand"
        };
      }
      return c;
    });
  }

  // Handle contract checkbox change (contracts mode)
  handleContractCheckbox(event) {
    const contractId = event.target.dataset.contractId;
    const customerId = event.target.dataset.customerId;
    const isChecked = event.target.checked;

    // Update customer contracts
    this.customers = this.customers.map((c) => {
      if (c.customerId === customerId) {
        return {
          ...c,
          contracts: (c.contracts || []).map((contract) => {
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
    const setIds =
      this.selectedContractVersionIdsByCustomer.get(customerId) || new Set();
    if (isChecked) {
      setIds.add(contractId);
    } else {
      setIds.delete(contractId);
    }
    this.selectedContractVersionIdsByCustomer.set(customerId, setIds);
  }

  handleToggleAllContracts(event) {
    const customerId = event.currentTarget.dataset.customerId;
    const selected = event.currentTarget.dataset.selected === "true";

    this.customers = this.customers.map((c) => {
      if (c.customerId !== customerId) {
        return c;
      }
      return {
        ...c,
        contracts: (c.contracts || []).map((contract) => ({
          ...contract,
          isSelected: selected
        }))
      };
    });

    const setIds = new Set();
    if (selected) {
      const row = this.customers.find((c) => c.customerId === customerId);
      (row?.contracts || []).forEach((cv) => setIds.add(cv.contentVersionId));
    }
    this.selectedContractVersionIdsByCustomer.set(customerId, setIds);
  }

  // Handle file preview - opens file in new browser tab (contracts mode)
  handlePreviewFile(event) {
    const fileId =
      event.target.dataset.fileId || event.currentTarget.dataset.fileId;

    if (!fileId) {
      console.error("No file ID found for preview");
      return;
    }

    const baseUrl = window.location.origin;
    const previewUrl = `${baseUrl}/lightning/page/filePreview?selectedRecordId=${fileId}`;
    window.open(previewUrl, "_blank");
  }

  /* =====================================================
       SEND
    ===================================================== */
  async handleSend() {
    this.isLoading = true;

    try {
      const payload = [];

      if (this.isContractsMode) {
        // Build payload with selected contract versions
        for (const c of this.customers) {
          const ids = (c.contracts || [])
            .filter((contract) => contract.isSelected)
            .map((contract) => contract.contentVersionId);

          if (ids.length > 0) {
            const row = {
              customerId: c.customerId,
              workOrderId: c.workOrderId || null,
              contentVersionIds: ids
            };
            if (c.emailSubjectOverride != null) {
              row.subject = c.emailSubjectOverride;
            }
            if (c.emailBodyOverride != null) {
              row.body = c.emailBodyOverride;
            }
            if (c.emailSubjectOverride != null || c.emailBodyOverride != null) {
              row.parsedContent = true;
            }
            payload.push(row);
          }
        }

        if (!payload.length) {
          this.toast(
            "Nothing to send",
            "Please select at least one contract.",
            "warning"
          );
          return;
        }
      } else {
        // Simple mode: send per-customer without specific contracts
        for (const c of this.customers) {
          const row = {
            customerId: c.customerId,
            workOrderId: c.workOrderId || null
          };
          if (c.emailSubjectOverride != null) {
            row.subject = c.emailSubjectOverride;
          }
          if (c.emailBodyOverride != null) {
            row.body = c.emailBodyOverride;
          }
          if (c.emailSubjectOverride != null || c.emailBodyOverride != null) {
            row.parsedContent = true;
          }
          payload.push(row);
        }

        if (!payload.length) {
          this.toast(
            "Nothing to send",
            "No customers found to send emails to.",
            "warning"
          );
          return;
        }
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
        "Sent",
        "Emails were processed. See Send History for details.",
        "success"
      );
    } catch (e) {
      this.toast("Error", this.normalizeError(e), "error");
    } finally {
      this.isLoading = false;
    }
  }

  /* =====================================================
       UTILS
    ===================================================== */
  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  normalizeError(e) {
    if (!e) return "Unknown error";
    if (Array.isArray(e.body)) {
      return e.body.map((x) => x.message).join(", ");
    }
    return e.body?.message || e.message || JSON.stringify(e);
  }

  closeComponent() {
    try {
      // Try to close as a quick action/modal
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch {
      // If not a quick action, try to close the tab
      this[NavigationMixin.Navigate]({
        type: "standard__navItemPage",
        attributes: {
          apiName: "Home"
        }
      });
    }
  }

  async handleEditClick(event) {
    const customerId = event.currentTarget.dataset.customerId;
    const current = this.customers.find((c) => c.customerId === customerId);
    if (current?.isEditing) {
      this.handleEditLeave();
      return;
    }

    this.hoveredCustomerId = null;
    this.hoveredPreviewSubject = null;
    this.hoveredPreviewBody = null;
    this.mergeFieldError = false;
    this.mergeFieldErrorMessage = null;

    if (!this.selectedTemplateId) {
      this.customers = this.customers.map((c) => ({
        ...c,
        isHovered: false,
        isEditing: c.customerId === customerId,
        isEditContentLoading: false
      }));
      return;
    }

    this.customers = this.customers.map((c) => ({
      ...c,
      isHovered: false,
      isEditing: c.customerId === customerId,
      isEditContentLoading: c.customerId === customerId
    }));

    await this.loadMergedEmailForCustomer(customerId);
  }

  handleEditLeave() {
    this.customers = this.customers.map((c) => ({
      ...c,
      isEditing: false,
      isEditContentLoading: false
    }));
  }

  async handlePreviewClick(event) {
    const customerId = event.currentTarget.dataset.customerId;

    this.handleEditLeave();

    // If this customer's preview is already open, close it on second click
    const currentCustomer = this.customers.find(
      (c) => c.customerId === customerId
    );
    if (currentCustomer && currentCustomer.isHovered) {
      this.handlePreviewLeave();
      return;
    }

    // Otherwise load and show preview (reuse hover handler logic)
    await this.handlePreviewHover(event);
  }

  async handlePreviewHover(event) {
    const customerId = event.currentTarget.dataset.customerId;
    this.hoveredCustomerId = customerId;
    this.isHoveredPreviewLoading = true;

    this.customers = this.customers.map((c) => ({
      ...c,
      isHovered: c.customerId === customerId,
      isEditing: false
    }));

    const previewCustomer = this.customers.find(
      (c) => c.customerId === customerId
    );

    try {
      // Stored merged text (from edit load) is final HTML — do not run through merge again.
      if (
        previewCustomer &&
        (previewCustomer.emailSubjectOverride != null ||
          previewCustomer.emailBodyOverride != null)
      ) {
        this.hoveredPreviewSubject = this.getSubjectForCustomer(previewCustomer);
        this.hoveredPreviewBody = this.getBodyForCustomer(previewCustomer);
        this.mergeFieldError = false;
        this.mergeFieldErrorMessage = null;
        return;
      }

      const res = await previewEmail({
        emailTemplateId: this.selectedTemplateId,
        customerId: customerId,
        contactId: null,
        workOrderId: previewCustomer?.workOrderId || null,
        subject: this.getSubjectForCustomer(previewCustomer),
        body: this.getBodyForCustomer(previewCustomer)
      });

      this.hoveredPreviewSubject = res.subject;
      this.hoveredPreviewBody = res.body;
      this.mergeFieldError = !!res.mergeFieldError;
      this.mergeFieldErrorMessage = this.mergeFieldError
        ? "Some merge fields could not be resolved. The preview may be missing data."
        : null;

      // тут можно показать popover
    } finally {
      this.isHoveredPreviewLoading = false;
    }
  }

  handlePreviewLeave() {
    this.hoveredCustomerId = null;
    this.hoveredPreviewSubject = null;
    this.hoveredPreviewBody = null;

    this.mergeFieldError = false;
    this.mergeFieldErrorMessage = null;

    this.customers = this.customers.map((c) => ({
      ...c,
      isHovered: false
    }));
  }

  get isSimpleMode() {
    return this.mode === "simple";
  }

  get isContractsMode() {
    return this.mode === "contracts";
  }

  getSubjectForCustomer(cust) {
    if (!cust) {
      return this.subject;
    }
    return cust.emailSubjectOverride != null
      ? cust.emailSubjectOverride
      : this.subject;
  }

  getBodyForCustomer(cust) {
    if (!cust) {
      return this.body;
    }
    return cust.emailBodyOverride != null ? cust.emailBodyOverride : this.body;
  }
}