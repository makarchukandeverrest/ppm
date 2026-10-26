import { LightningElement, wire, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { getPicklistValues, getObjectInfo } from "lightning/uiObjectInfoApi";
import FORM_FACTOR from "@salesforce/client/formFactor";
import desktopTemplate from "./customersMap.html";
import mobileTemplate from "./customersMapMobile.html";
import getCustomers from "@salesforce/apex/MapCustomersController.getCustomers";
import ACCOUNT_OBJECT from "@salesforce/schema/Account";
import CONTRACT_BID_OBJECT from "@salesforce/schema/Contract_Bid__c";
import CONTRACT_PERIODS_FIELD from "@salesforce/schema/Account.Contract_Periods__c";
import COUNTY_FIELD from "@salesforce/schema/Account.County__c";
import CONTRACT_YEAR_FIELD from "@salesforce/schema/Contract_Bid__c.Contract_Year__c";
import STAGE_FIELD from "@salesforce/schema/Contract_Bid__c.Stage__c";

const REGIONAL_MANAGER_OPTIONS = [
  { label: "All", value: "" },
  { label: "Stephanie P.", value: "Stephanie P." },
  { label: "Roman Shestakov", value: "Roman Shestakov" },
  { label: "Marijana Zarkovic", value: "Marijana Zarkovic" },
  { label: "Hamzah Alqwaqneh", value: "Hamzah Alqwaqneh" },
  { label: "Ammar Alkwakneh", value: "Ammar Alkwakneh" },
  { label: "Stanislav Kryshtalian", value: "Stanislav Kryshtalian" }
];

const MAP_MARKER_PATH =
  "M 0,0 C -2,-20 -10,-22 -10,-30 A 10,10 0 1,1 10,-30 C 10,-22 2,-20 0,0 z";
const STAGE_CLOSED_LOST = "Closed - LOST";
const STAGE_CONTRACT_SENT = "Contract Sent via DocuSign";
const CLOSED_STAGES = new Set(["Closed - WON", STAGE_CLOSED_LOST]);
const MARKER_COLOR_CURRENT = "#09A711";
const MARKER_COLOR_CONTRACT_SENT = "#FCC003";
const MARKER_COLOR_OPPORTUNITY = "#1B96FF";
const MARKER_COLOR_CLOSED_LOST = "#EA001E";
const MARKER_COLOR_ACTIVE_BID = "#FF7A00";
const MARKER_COLOR_MULTI = "#032D60";
const IS_MOBILE = FORM_FACTOR === "Small";
const MOBILE_MIN_SHELL_HEIGHT = 360;
const MOBILE_MIN_MAP_HEIGHT = 200;
const MOBILE_BOTTOM_GAP = 8;
// iOS / Salesforce Mobile WKWebView needs longer than 50ms before Google Maps
// measures a container that already has real pixels.
const MOBILE_MAP_REMOUNT_DELAY_MS = 300;
const MOBILE_MAP_HEIGHT_RECHECK_MS = 50;

export default class CustomersMap extends NavigationMixin(LightningElement) {
  isMobile = IS_MOBILE;
  @track isFiltersOpen = false;
  @track isLandscapeMode = false;
  // Delay first lightning-map mount until the pane has a real pixel height
  // (avoids blank Google Maps on iOS / Salesforce Mobile WKWebView).
  @track isMobileMapMounted = false;
  _restoreLandscapeAfterOverlay = false;
  _mobileResizeHandler;
  _mobileHeightInitialized = false;
  _lastMobileMapHeightPx = 0;
  _lastConfirmedMapHeightPx = 0;
  _mobileHeightConfirmFrame;
  _mobileHeightRecheckTimer;
  _mobileMapRemountTimer;

  allCustomers = [];
  filteredCustomers = [];
  filteredMapMarkers = [];
  locationGroupMap = {};
  cardTitle = "Customer Locations";
  loadErrorMessage = "";
  @track selectedMarkerValue = "";
  @track selectedCustomerDetails = [];
  @track selectedLocationKey = "";

  // Default map settings
  @track zoomLevel = 11;
  @track defaultZoomLevel = 11;
  @track center = {};
  @track defaultCenter = {};

  // Search properties
  @track searchTerm = "";
  @track selectedRegionalManager = "";
  @track selectedCounty = "";
  @track selectedContractPeriods = [];
  @track selectedContractYear = "";
  @track regionalManagerOptions = REGIONAL_MANAGER_OPTIONS;
  @track countyOptions = [];
  @track contractPeriodOptions = [];
  @track contractYearOptions = [];

  recordTypeId;
  contractBidRecordTypeId;
  stageOrder = [];

  mapOptions = IS_MOBILE
    ? {
        // Pinch-to-zoom covers zooming on touch devices; hide Google's desktop controls
        disableDefaultUI: true,
        zoomControl: false,
        draggable: true,
        scrollwheel: true
      }
    : {
        disableDefaultUI: false,
        draggable: true,
        scrollwheel: true
      };

  render() {
    return IS_MOBILE ? mobileTemplate : desktopTemplate;
  }

  connectedCallback() {
    if (!IS_MOBILE) {
      return;
    }
    this._mobileResizeHandler = () => this.updateMobileShellHeight();
    window.addEventListener("resize", this._mobileResizeHandler);
    window.addEventListener("orientationchange", this._mobileResizeHandler);
  }

  disconnectedCallback() {
    if (this._mobileMapRemountTimer) {
      clearTimeout(this._mobileMapRemountTimer);
      this._mobileMapRemountTimer = null;
    }
    if (this._mobileHeightConfirmFrame) {
      cancelAnimationFrame(this._mobileHeightConfirmFrame);
      this._mobileHeightConfirmFrame = null;
    }
    if (this._mobileHeightRecheckTimer) {
      clearTimeout(this._mobileHeightRecheckTimer);
      this._mobileHeightRecheckTimer = null;
    }
    if (!this._mobileResizeHandler) {
      return;
    }
    window.removeEventListener("resize", this._mobileResizeHandler);
    window.removeEventListener("orientationchange", this._mobileResizeHandler);
    this._mobileResizeHandler = null;
  }

  renderedCallback() {
    if (IS_MOBILE) {
      // Cheap (one getBoundingClientRect); re-measure on every render so late
      // layout of the Salesforce mobile header is picked up.
      this.updateMobileShellHeight();
    }
  }

  /**
   * Mobile: stretch the component to fill the remaining viewport below the
   * Salesforce app header so the map is as close to full screen as possible.
   */
  updateMobileShellHeight() {
    const shell = this.template.querySelector(".mobile-shell");
    if (!shell) {
      return;
    }
    if (this.isLandscapeMode) {
      // Landscape overlay is driven purely by CSS
      if (shell.style.height) {
        shell.style.height = "";
      }
      this.applyMobileMapPixelHeight();
      return;
    }
    const top = Math.max(shell.getBoundingClientRect().top, 0);
    const available = window.innerHeight - top - MOBILE_BOTTOM_GAP;
    const height = `${Math.max(available, MOBILE_MIN_SHELL_HEIGHT)}px`;
    if (shell.style.height !== height) {
      shell.style.height = height;
    }
    this.applyMobileMapPixelHeight();
  }

  /**
   * Give lightning-map an explicit px height and mount only after layout is
   * known. Google Maps (inside lightning-map) often paints white on iOS when
   * it first measures a %/absolute container with no resolved pixels.
   */
  applyMobileMapPixelHeight() {
    const mapPane = this.template.querySelector(".mobile-map");
    if (!mapPane) {
      return;
    }

    const heightPx = Math.floor(mapPane.getBoundingClientRect().height);
    if (heightPx >= MOBILE_MIN_MAP_HEIGHT) {
      this.writeMobileMapPixelHeight(heightPx);
    }

    // This box was already confirmed after paint. Mount if markers arrived later.
    if (
      heightPx >= MOBILE_MIN_MAP_HEIGHT &&
      heightPx === this._lastConfirmedMapHeightPx
    ) {
      this.mountMobileMapIfReady();
      return;
    }

    this.confirmMobileMapPixelHeight();
  }

  writeMobileMapPixelHeight(heightPx) {
    this._lastMobileMapHeightPx = heightPx;
    const heightStyle = `${heightPx}px`;
    const map = this.template.querySelector("lightning-map");
    if (map) {
      if (map.style.height !== heightStyle) {
        map.style.height = heightStyle;
        map.style.minHeight = heightStyle;
      }
      map.style.width = "100%";
    }
  }

  mountMobileMapIfReady() {
    if (!this.hasFilteredMarkers || !this.showMapView) {
      return;
    }
    // Mount only once the pane has a real pixel box (Google Maps init size).
    if (!this.isMobileMapMounted) {
      this.isMobileMapMounted = true;
      this._mobileHeightInitialized = true;
    }
  }

  /**
   * Re-read the pane after paint. iOS can report a height before the
   * container has actually received those pixels.
   */
  confirmMobileMapPixelHeight() {
    if (this._mobileHeightConfirmFrame || this._mobileHeightRecheckTimer) {
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._mobileHeightConfirmFrame = requestAnimationFrame(() => {
      this._mobileHeightConfirmFrame = null;
      if (this.readAndConfirmMobileMapHeight()) {
        return;
      }
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this._mobileHeightRecheckTimer = setTimeout(() => {
        this._mobileHeightRecheckTimer = null;
        this.readAndConfirmMobileMapHeight();
      }, MOBILE_MAP_HEIGHT_RECHECK_MS);
    });
  }

  readAndConfirmMobileMapHeight() {
    const mapPane = this.template.querySelector(".mobile-map");
    if (!mapPane) {
      return false;
    }
    const heightPx = Math.floor(mapPane.getBoundingClientRect().height);
    if (heightPx < MOBILE_MIN_MAP_HEIGHT) {
      return false;
    }
    this.writeMobileMapPixelHeight(heightPx);
    this._lastConfirmedMapHeightPx = heightPx;
    this.mountMobileMapIfReady();
    return true;
  }

  /**
   * Unmount and remount lightning-map after the next layout pass so Maps
   * re-initializes with the current pixel size (landscape / back-to-map).
   */
  scheduleMobileMapRemount() {
    if (!IS_MOBILE) {
      return;
    }
    if (this._mobileMapRemountTimer) {
      clearTimeout(this._mobileMapRemountTimer);
    }
    if (this._mobileHeightConfirmFrame) {
      cancelAnimationFrame(this._mobileHeightConfirmFrame);
      this._mobileHeightConfirmFrame = null;
    }
    if (this._mobileHeightRecheckTimer) {
      clearTimeout(this._mobileHeightRecheckTimer);
      this._mobileHeightRecheckTimer = null;
    }
    this.isMobileMapMounted = false;
    this._lastMobileMapHeightPx = 0;
    this._lastConfirmedMapHeightPx = 0;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._mobileMapRemountTimer = setTimeout(() => {
      this._mobileMapRemountTimer = null;
      // renderedCallback + applyMobileMapPixelHeight will mount when ready
      this.updateMobileShellHeight();
    }, MOBILE_MAP_REMOUNT_DELAY_MS);
  }

  get shouldRenderMobileMap() {
    return this.hasFilteredMarkers;
    // временно убрали && this.isMobileMapMounted для диагностики
  }

  toggleFilters() {
    if (this.isFiltersOpen) {
      this.closeFilters();
      return;
    }
    this.suspendLandscapeForOverlay();
    this.isFiltersOpen = true;
  }

  toggleLandscapeMode() {
    this.isLandscapeMode = !this.isLandscapeMode;
    // Manual toggle cancels any pending auto-restore
    this._restoreLandscapeAfterOverlay = false;
    // Shell size changes; remount so Maps picks up the new pixel box
    this.scheduleMobileMapRemount();
  }

  /**
   * Filters/details replace the map as scrollable pages. Landscape rotate
   * breaks touch-scroll on Salesforce Mobile, so exit it temporarily.
   */
  suspendLandscapeForOverlay() {
    if (!IS_MOBILE) {
      return;
    }
    if (this.isLandscapeMode) {
      this._restoreLandscapeAfterOverlay = true;
      this.isLandscapeMode = false;
    }
  }

  maybeRestoreLandscape() {
    if (!IS_MOBILE || !this._restoreLandscapeAfterOverlay) {
      return;
    }
    if (!this.isFiltersOpen && !this.hasAnySelection) {
      this._restoreLandscapeAfterOverlay = false;
      this.isLandscapeMode = true;
    }
  }

  get isDeviceLandscape() {
    return (
      typeof window !== "undefined" && window.innerWidth > window.innerHeight
    );
  }

  get shellClass() {
    if (!this.isLandscapeMode) {
      return "mobile-shell";
    }
    // Already physically landscape → no CSS rotate needed
    return this.isDeviceLandscape
      ? "mobile-shell mobile-shell_landscape mobile-shell_landscape-native"
      : "mobile-shell mobile-shell_landscape";
  }

  get landscapeIcon() {
    return this.isLandscapeMode ? "utility:contract_alt" : "utility:rotate";
  }

  get landscapeLabel() {
    return this.isLandscapeMode ? "Exit landscape" : "Landscape map";
  }

  get detailsPageTitle() {
    if (this.hasSelectedLocationGroup) {
      return this.selectedLocationCountLabel;
    }
    return this.selectedCustomerName || "Customer";
  }

  get showMapView() {
    return !this.isFiltersOpen && !this.hasAnySelection;
  }

  get showDetailsView() {
    return !this.isFiltersOpen && this.hasAnySelection;
  }

  closeFilters() {
    this.isFiltersOpen = false;
    this.maybeRestoreLandscape();
    // Map shell was torn down while filters were open — remount with fresh px height
    this.scheduleMobileMapRemount();
  }

  get activeFilterCount() {
    let count = 0;
    if (this.searchTerm) count++;
    if (this.selectedCounty) count++;
    if (this.selectedRegionalManager) count++;
    if (this.selectedContractYear) count++;
    if (this.getSelectedContractPeriods().length > 0) count++;
    return count;
  }

  get filtersButtonLabel() {
    return this.activeFilterCount > 0
      ? `Filters (${this.activeFilterCount})`
      : "Filters";
  }

  get showResultsLabel() {
    const count = this.filteredCustomers.length;
    return `Show ${count} ${count === 1 ? "customer" : "customers"}`;
  }

  get selectedCustomerName() {
    return this.selectedCustomerDetails.length > 0
      ? this.selectedCustomerDetails[0].name
      : "";
  }

  handleNavigateToRecord(event) {
    const { recordId, object } = event.currentTarget.dataset;
    this.navigateToRecord(recordId, object);
  }

  navigateToRecord(recordId, objectApiName) {
    if (!recordId) return;

    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId,
        objectApiName,
        actionName: "view"
      }
    });
  }

  @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
  wiredObjectInfo({ data, error }) {
    if (data) {
      this.recordTypeId = data.defaultRecordTypeId;
    } else if (error) {
      console.error("Error loading Account object info:", error);
    }
  }

  @wire(getObjectInfo, { objectApiName: CONTRACT_BID_OBJECT })
  wiredContractBidObjectInfo({ data, error }) {
    if (data) {
      this.contractBidRecordTypeId = data.defaultRecordTypeId;
    } else if (error) {
      console.error("Error loading Contract Bid object info:", error);
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$contractBidRecordTypeId",
    fieldApiName: STAGE_FIELD
  })
  wiredStageValues({ error, data }) {
    if (data) {
      this.stageOrder = data.values.map((entry) => entry.value);
      if (this.hasAnySelection) {
        this.syncSelectedCustomer();
      }
    } else if (error) {
      console.error("Error loading contract bid stage picklist values:", error);
    }
  }

  @wire(getCustomers)
  wiredCustomers({ error, data }) {
    if (data) {
      this.loadErrorMessage = "";
      this.allCustomers = data;
      this.filteredCustomers = data;
      this.cardTitle = `Customer Locations (${data.length})`;

      const firstMappableCustomer = data.find((customer) =>
        this.getCustomerMapLocation(customer)
      );
      if (firstMappableCustomer) {
        const location = this.getCustomerMapLocation(firstMappableCustomer);
        this.center = { location };
        this.defaultCenter = { location };
      }

      this.updateFilteredMapMarkers(this.filteredCustomers);
    } else if (error) {
      // Show error in UI (wire errors are otherwise invisible)
      // eslint-disable-next-line no-console
      console.error("Error loading customers:", error);
      this.loadErrorMessage =
        this.normalizeErrorMessage(error) || "Error loading customers.";
      this.allCustomers = [];
      this.filteredCustomers = [];
      this.filteredMapMarkers = [];
    }
  }

  normalizeErrorMessage(error) {
    if (!error) return "";
    const body = error.body;
    if (Array.isArray(body)) {
      return body
        .map((e) => e.message)
        .filter(Boolean)
        .join(", ");
    }
    if (typeof body === "string") return body;
    if (body && typeof body.message === "string") return body.message;
    if (typeof error.message === "string") return error.message;
    return "";
  }

  get hasLoadError() {
    return Boolean(this.loadErrorMessage);
  }

  @wire(getPicklistValues, {
    recordTypeId: "$recordTypeId",
    fieldApiName: CONTRACT_PERIODS_FIELD
  })
  wiredContractPeriods({ error, data }) {
    if (data) {
      this.contractPeriodOptions = data.values.map((entry) => ({
        label: entry.label,
        value: entry.value
      }));
    } else if (error) {
      console.error("Error loading contract period picklist values:", error);
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$recordTypeId",
    fieldApiName: COUNTY_FIELD
  })
  wiredCounty({ error, data }) {
    if (data) {
      this.countyOptions = data.values.map((entry) => ({
        label: entry.label,
        value: entry.value
      }));

      this.countyOptions.unshift({
        label: "All Counties",
        value: ""
      });
    } else if (error) {
      console.error("Error loading county picklist values:", error);
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$contractBidRecordTypeId",
    fieldApiName: CONTRACT_YEAR_FIELD
  })
  wiredContractYear({ error, data }) {
    if (data) {
      this.contractYearOptions = data.values.map((entry) => ({
        label: entry.label,
        value: entry.value
      }));

      this.contractYearOptions.unshift({
        label: "All Contract Years",
        value: ""
      });
    } else if (error) {
      console.error("Error loading contract year picklist values:", error);
    }
  }

  handleSearch(event) {
    this.searchTerm = event.target.value.trim().toLowerCase();
    this.filterCustomers();
  }

  handleRegionalManagerChange(event) {
    this.selectedRegionalManager = event.detail.value;
    this.filterCustomers();
  }

  handleCountyChange(event) {
    this.selectedCounty = event.detail.value;
    this.filterCustomers();
  }

  handleContractPeriodsChange(event) {
    this.selectedContractPeriods = event.detail.value || [];
    this.filterCustomers();
  }

  handleContractYearChange(event) {
    this.selectedContractYear = event.detail.value;
    this.filterCustomers();
  }

  handleClearSearch() {
    this.searchTerm = "";
    this.selectedRegionalManager = "";
    this.selectedCounty = "";
    this.selectedContractPeriods = [];
    this.selectedContractYear = "";

    const inputs = this.template.querySelectorAll("lightning-input");
    inputs.forEach((input) => {
      input.value = "";
    });

    const stateCombo = this.template.querySelector('[name="countyFilter"]');
    const contractPeriodFilter = this.template.querySelector(
      '[name="contractPeriodFilter"]'
    );
    const contractYearFilter = this.template.querySelector(
      '[name="contractYearFilter"]'
    );
    const regionalManagerCombo = this.template.querySelector(
      '[data-name="regionalManagerFilter"]'
    );

    if (stateCombo) stateCombo.value = "";
    if (contractPeriodFilter) contractPeriodFilter.value = [];
    if (contractYearFilter) contractYearFilter.value = "";
    if (regionalManagerCombo) regionalManagerCombo.value = "";

    this.resetZoomToDefault();
    this.selectedCustomerDetails = [];
    this.selectedMarkerValue = "";
    this.clearLocationSelection();
    this.filterCustomers();
  }

  resetZoomToDefault() {
    this.zoomLevel = this.defaultZoomLevel;
    this.center = { ...this.defaultCenter };
  }

  filterCustomers() {
    if (!this.hasActiveFilters) {
      this.filteredCustomers = [...this.allCustomers];
      this.cardTitle = `Customer Locations (${this.allCustomers.length})`;
      this.updateFilteredMapMarkers(this.filteredCustomers);
      this.syncSelectedCustomer();
      return;
    }

    const filtered = this.allCustomers.filter((customer) =>
      this.customerMatchesAllFilters(customer)
    );

    this.filteredCustomers = filtered;
    this.cardTitle = `Customer Locations (${filtered.length} of ${this.allCustomers.length})`;
    this.updateFilteredMapMarkers(this.filteredCustomers);
    this.syncSelectedCustomer();
  }

  syncSelectedCustomer() {
    if (this.selectedLocationKey) {
      const visibleCustomers = (
        this.locationGroupMap[this.selectedLocationKey] || []
      ).filter((customer) =>
        this.filteredCustomers.some(
          (filtered) => filtered.accountId === customer.accountId
        )
      );

      if (visibleCustomers.length === 0) {
        this.clearSelection();
        return;
      }

      this.selectedCustomerDetails = visibleCustomers.map((customer) =>
        this.buildCustomerDetailView(customer)
      );
      this.selectedMarkerValue = `group:${this.selectedLocationKey}`;
      return;
    }

    if (
      !this.selectedMarkerValue ||
      this.selectedMarkerValue.startsWith("group:")
    ) {
      return;
    }

    const customer = this.filteredCustomers.find(
      (filtered) => filtered.accountId === this.selectedMarkerValue
    );

    if (!customer) {
      this.clearSelection();
      return;
    }

    this.selectedCustomerDetails = [this.buildCustomerDetailView(customer)];
  }

  clearLocationSelection() {
    this.selectedLocationKey = "";
  }

  clearSelection() {
    this.selectedCustomerDetails = [];
    this.selectedMarkerValue = "";
    this.clearLocationSelection();
    this.maybeRestoreLandscape();
    // Details view replaced the map shell — remount with fresh px height
    this.scheduleMobileMapRemount();
  }

  get hasAnySelection() {
    return this.selectedCustomerDetails.length > 0;
  }

  customerMatchesAllFilters(customer) {
    if (this.searchTerm) {
      const nameMatch =
        customer.name && customer.name.toLowerCase().includes(this.searchTerm);
      const emailMatch =
        customer.email &&
        customer.email.toLowerCase().includes(this.searchTerm);
      if (!nameMatch && !emailMatch) return false;
    }

    if (this.selectedCounty && customer.county !== this.selectedCounty) {
      return false;
    }

    if (this.selectedRegionalManager) {
      if (!customer.regionalManagerName) {
        return false;
      }
      if (customer.regionalManagerName !== this.selectedRegionalManager) {
        return false;
      }
    }

    if (this.getSelectedContractPeriods().length > 0) {
      const customerPeriods = this.getCustomerContractPeriods(customer);
      if (customerPeriods.length === 0) {
        return false;
      }

      const hasMatchingPeriod = this.getSelectedContractPeriods().some(
        (selectedPeriod) => customerPeriods.includes(selectedPeriod)
      );

      if (!hasMatchingPeriod) {
        return false;
      }
    }

    if (this.selectedContractYear) {
      if (
        !customer.contractYear ||
        customer.contractYear !== this.selectedContractYear
      ) {
        return false;
      }
    }

    return true;
  }

  updateFilteredMapMarkers(customerData) {
    const groups = new Map();

    customerData.forEach((customer) => {
      const location = this.getCustomerMapLocation(customer);
      if (!location) {
        return;
      }

      const locationKey = this.getAddressKey(customer, location);
      if (!groups.has(locationKey)) {
        groups.set(locationKey, {
          location,
          customers: []
        });
      }

      groups.get(locationKey).customers.push(customer);
    });

    this.locationGroupMap = {};
    const customerMarkers = [];

    groups.forEach((group, locationKey) => {
      this.locationGroupMap[locationKey] = group.customers;
      const customerCount = group.customers.length;

      if (customerCount === 1) {
        const customer = group.customers[0];
        customerMarkers.push({
          location: group.location,
          value: customer.accountId,
          title: customer.name,
          description: this.getCustomerDescription(customer),
          mapIcon: this.getCustomerMapIcon(customer)
        });
        return;
      }

      customerMarkers.push({
        location: group.location,
        value: `group:${locationKey}`,
        title: `${customerCount} customers at this address`,
        description: this.getLocationGroupDescription(group.customers),
        mapIcon: this.getLocationGroupMapIcon(customerCount)
      });
    });

    this.filteredMapMarkers = customerMarkers;
  }

  getAddressKey(customer, location) {
    if (location.Latitude != null && location.Longitude != null) {
      return `coord:${location.Latitude},${location.Longitude}`;
    }

    return [
      "addr",
      customer.billingStreet,
      customer.billingCity,
      customer.billingState,
      customer.billingPostalCode,
      customer.billingCountry
    ]
      .join("|")
      .toLowerCase();
  }

  getLocationGroupDescription(customers) {
    const address = this.formatCustomerAddress(customers[0]);
    let description = `<b>${customers.length} customers share this address</b><br/>${address}<br/><br/>`;

    customers.forEach((customer) => {
      const status = this.getCustomerMarkerStatus(customer);
      description += `&#8226; ${customer.name} (${status.label})<br/>`;
    });

    return description;
  }

  getLocationGroupMapIcon(customerCount) {
    return {
      path: MAP_MARKER_PATH,
      fillColor: MARKER_COLOR_MULTI,
      fillOpacity: 1,
      strokeColor: "#FFFFFF",
      strokeOpacity: 1,
      strokeWeight: 1.5,
      scale: customerCount > 5 ? 1.25 : 1.1
    };
  }

  buildCustomerDetailView(customer) {
    const status = this.getCustomerMarkerStatus(customer);
    const nextStage = this.getNextStage(customer.contractBidStage);
    const recentBid = customer.contractBidId
      ? {
          Name: customer.contractBidName,
          Stage__c: customer.contractBidStage,
          Contract_Year__c: customer.contractYear,
          Contract_Start_Date__c: customer.contractStartDate,
          Contract_End_Date__c: customer.contractEndDate,
          Due_Date__c: customer.dueDate,
          Total__c: customer.total
        }
      : null;

    return {
      accountId: customer.accountId,
      name: customer.name,
      statusLabel: status.label,
      statusClass: status.badgeClass,
      address: this.formatCustomerAddress(customer),
      accountUrl: `/lightning/r/Account/${customer.accountId}/view`,
      managementCompanyId: customer.managementCompanyId,
      managementCompanyName: customer.managementCompanyName,
      managementCompanyUrl: customer.managementCompanyId
        ? `/lightning/r/Management_Company__c/${customer.managementCompanyId}/view`
        : "",
      hasManagementCompany: Boolean(customer.managementCompanyName),
      primaryContactId: customer.primaryContactId,
      primaryContactName: customer.primaryContactName,
      primaryContactUrl: customer.primaryContactId
        ? `/lightning/r/Contact/${customer.primaryContactId}/view`
        : "",
      primaryContactPhone: customer.primaryContactPhone,
      primaryContactEmail: customer.primaryContactEmail,
      hasPrimaryContact: Boolean(customer.primaryContactId),
      regionalManagerName: customer.regionalManagerName,
      contractBidColoredLabels: customer.contractBidColoredLabels,
      lastActivitySubject: customer.lastActivitySubject,
      lastActivityType: customer.lastActivityType,
      lastActivityDateTime: customer.lastActivityDateTime,
      contractBidId: customer.contractBidId,
      contractBidUrl: customer.contractBidId
        ? `/lightning/r/Contract_Bid__c/${customer.contractBidId}/view`
        : "",
      hasContractBid: Boolean(customer.contractBidId),
      recentBid,
      hasRecentBid: Boolean(recentBid),
      showRecentBidTotal: recentBid && recentBid.Total__c != null,
      contractBidDescription: customer.contractBidDescription,
      nextStage,
      hasNextStage: Boolean(nextStage)
    };
  }

  getNextStage(currentStage) {
    if (!currentStage || !this.stageOrder.length) {
      return null;
    }

    if (CLOSED_STAGES.has(currentStage)) {
      return null;
    }

    const currentIndex = this.stageOrder.indexOf(currentStage);
    if (currentIndex === -1 || currentIndex >= this.stageOrder.length - 1) {
      return null;
    }

    return this.stageOrder[currentIndex + 1];
  }

  formatCustomerAddress(customer) {
    const addressParts = [
      customer.billingStreet,
      customer.billingCity,
      customer.billingState,
      customer.billingPostalCode,
      customer.billingCountry
    ].filter((part) => part);

    return addressParts.length > 0
      ? addressParts.join(", ")
      : "Address not available";
  }

  hasCoordinates(customer) {
    return (
      customer.billingLatitude != null && customer.billingLongitude != null
    );
  }

  hasPostalCode(customer) {
    return Boolean(customer.billingPostalCode);
  }

  getCustomerMapLocation(customer) {
    if (this.hasCoordinates(customer)) {
      return {
        Latitude: customer.billingLatitude,
        Longitude: customer.billingLongitude
      };
    }

    if (
      customer.billingStreet ||
      customer.billingCity ||
      customer.billingState
    ) {
      return {
        Street: customer.billingStreet,
        City: customer.billingCity,
        State: customer.billingState,
        PostalCode: customer.billingPostalCode,
        Country: customer.billingCountry
      };
    }

    if (this.hasPostalCode(customer)) {
      return { PostalCode: customer.billingPostalCode };
    }

    return null;
  }

  getCustomerMapIcon(customer) {
    const status = this.getCustomerMarkerStatus(customer);

    return {
      path: MAP_MARKER_PATH,
      fillColor: status.color,
      fillOpacity: 1,
      strokeColor: status.strokeColor,
      strokeOpacity: 1,
      strokeWeight: 1,
      scale: 1
    };
  }

  getCustomerMarkerStatus(customer) {
    const stage = customer.contractBidStage;
    const today = this.getTodayDate();

    if (customer.currentCustomer === true) {
      return {
        label: "Current Customer",
        color: MARKER_COLOR_CURRENT,
        badgeClass: "status-badge status-badge_current",
        strokeColor: "#000000"
      };
    }

    if (stage === STAGE_CLOSED_LOST) {
      return {
        label: STAGE_CLOSED_LOST,
        color: MARKER_COLOR_CLOSED_LOST,
        badgeClass: "status-badge status-badge_closed-lost",
        strokeColor: "#FFFFFF"
      };
    }

    if (stage === STAGE_CONTRACT_SENT) {
      return {
        label: STAGE_CONTRACT_SENT,
        color: MARKER_COLOR_CONTRACT_SENT,
        badgeClass: "status-badge status-badge_contract-sent",
        strokeColor: "#000000"
      };
    }

    if (this.isBidOpportunity(customer, today)) {
      return {
        label: "Bid Opportunity",
        color: MARKER_COLOR_OPPORTUNITY,
        badgeClass: "status-badge status-badge_opportunity",
        strokeColor: "#FFFFFF"
      };
    }

    if (this.isActivePipeline(customer, today)) {
      return {
        label: stage || "Active Bid",
        color: MARKER_COLOR_ACTIVE_BID,
        badgeClass: "status-badge status-badge_active-bid",
        strokeColor: "#000000"
      };
    }

    return {
      label: stage || "Active Bid",
      color: MARKER_COLOR_ACTIVE_BID,
      badgeClass: "status-badge status-badge_active-bid",
      strokeColor: "#000000"
    };
  }

  getTodayDate() {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    return today;
  }

  parseSalesforceDate(dateValue) {
    if (!dateValue) {
      return null;
    }

    if (typeof dateValue === "string") {
      const [year, month, day] = dateValue.split("T")[0].split("-").map(Number);
      return new Date(year, month - 1, day);
    }

    const date = new Date(dateValue);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  isDateInCurrentCalendarYear(dateValue, today) {
    const date = this.parseSalesforceDate(dateValue);
    if (!date) {
      return false;
    }

    return date.getFullYear() === today.getFullYear();
  }

  isDateAfterToday(dateValue, today) {
    const date = this.parseSalesforceDate(dateValue);
    if (!date) {
      return false;
    }

    return date.getTime() > today.getTime();
  }

  isClosedStage(stage) {
    return CLOSED_STAGES.has(stage);
  }

  isBidOpportunity(customer, today) {
    if (!customer.contractBidId) {
      return true;
    }

    if (!customer.hasCurrentYearBid) {
      return true;
    }

    if (
      !this.isDateInCurrentCalendarYear(customer.accountContractEndDate, today)
    ) {
      return true;
    }

    return false;
  }

  isActivePipeline(customer, today) {
    if (!customer.contractBidId) {
      return false;
    }

    if (!this.isClosedStage(customer.contractBidStage)) {
      return true;
    }

    return this.isDateAfterToday(customer.contractEndDate, today);
  }

  get hasActiveFilters() {
    return (
      this.searchTerm ||
      this.selectedRegionalManager ||
      this.selectedCounty ||
      this.selectedContractYear ||
      this.getSelectedContractPeriods().length > 0
    );
  }

  getSelectedContractPeriods() {
    if (!this.selectedContractPeriods) {
      return [];
    }

    if (Array.isArray(this.selectedContractPeriods)) {
      return this.selectedContractPeriods;
    }

    return [this.selectedContractPeriods];
  }

  getCustomerContractPeriods(customer) {
    if (!customer.contractPeriods) {
      return [];
    }

    return customer.contractPeriods
      .split(";")
      .map((period) => period.trim())
      .filter((period) => period);
  }

  getCustomerDescription(customer) {
    const address = this.formatCustomerAddress(customer);
    const markerStatus = this.getCustomerMarkerStatus(customer);

    const accountUrl = `/lightning/r/Account/${customer.accountId}/view`;
    let description =
      `<a href="${accountUrl}" target="_blank" rel="noopener noreferrer">${customer.name}</a>` +
      `<br/><b>${markerStatus.label}</b><br/>Address: ${address}`;

    if (customer.contractPeriods) {
      description += `<br/>Contract Periods: ${customer.contractPeriods}`;
    }
    if (customer.email) {
      description += `<br/>Email: ${customer.email}`;
    }

    description += this.getRecentContractBidDescription(customer);

    return description;
  }

  getRecentContractBidDescription(customer) {
    if (!customer.contractBidId) {
      return "<br/><br/><b>Recent Contract Bid:</b> None";
    }

    const bidUrl = `/lightning/r/Contract_Bid__c/${customer.contractBidId}/view`;
    let description = "<br/><br/><b>Recent Contract Bid</b>";
    description += `<br/>Name: <a href="${bidUrl}" target="_blank" rel="noopener noreferrer">${customer.contractBidName || "—"}</a>`;

    if (customer.contractBidStage) {
      description += `<br/>Stage: ${customer.contractBidStage}`;
    }
    if (customer.contractYear) {
      description += `<br/>Contract Year: ${customer.contractYear}`;
    }
    if (customer.contractStartDate) {
      description += `<br/>Start Date: ${this.formatDate(customer.contractStartDate)}`;
    }
    if (customer.contractEndDate) {
      description += `<br/>End Date: ${this.formatDate(customer.contractEndDate)}`;
    }
    if (customer.dueDate) {
      description += `<br/>Due Date: ${this.formatDate(customer.dueDate)}`;
    }
    if (customer.total != null) {
      description += `<br/>Total: ${customer.total}`;
    }

    return description;
  }

  formatDate(dateValue) {
    if (!dateValue) {
      return "";
    }

    const date = new Date(dateValue);
    if (Number.isNaN(date.getTime())) {
      return dateValue;
    }

    return date.toLocaleDateString();
  }

  get hasSelectedLocationGroup() {
    return this.selectedCustomerDetails.length > 1;
  }

  get selectedLocationAddress() {
    if (
      !this.selectedLocationKey ||
      !this.locationGroupMap[this.selectedLocationKey]?.length
    ) {
      return "";
    }

    return this.formatCustomerAddress(
      this.locationGroupMap[this.selectedLocationKey][0]
    );
  }

  get selectedLocationCountLabel() {
    return `${this.selectedCustomerDetails.length} customers at this address`;
  }

  get hasFilteredMarkers() {
    return this.filteredMapMarkers && this.filteredMapMarkers.length > 0;
  }

  zoomToCustomer(customer) {
    const location = this.getCustomerMapLocation(customer);
    if (!location) {
      return;
    }

    this.zoomLevel = 15;
    this.center = { location };
  }

  handleMarkerSelect(event) {
    try {
      if (!event.target?.selectedMarkerValue) {
        return;
      }

      const markerValue = event.target.selectedMarkerValue;
      this.selectedMarkerValue = markerValue;
      this.suspendLandscapeForOverlay();

      if (markerValue.startsWith("group:")) {
        const locationKey = markerValue.replace("group:", "");
        const customers = this.locationGroupMap[locationKey] || [];
        this.selectedLocationKey = locationKey;
        this.selectedCustomerDetails = customers.map((customer) =>
          this.buildCustomerDetailView(customer)
        );

        const firstCustomer = customers[0];
        if (firstCustomer) {
          this.zoomToCustomer(firstCustomer);
        }
        this.scrollToDetails();
        return;
      }

      this.clearLocationSelection();

      const selectedCustomer = this.allCustomers.find(
        (customer) => customer.accountId === markerValue
      );
      if (selectedCustomer) {
        this.selectedCustomerDetails = [
          this.buildCustomerDetailView(selectedCustomer)
        ];
        this.zoomToCustomer(selectedCustomer);
      }
      this.scrollToDetails();
    } catch (error) {
      console.error("Error in handleMarkerSelect:", error);
    }
  }

  handleNavigateToAccountFromDetail(event) {
    this.navigateToAccount(event.currentTarget.dataset.id);
  }

  scrollToDetails() {
    // Mobile uses a full-page details view; desktop scrolls to the side panel.
    if (IS_MOBILE) {
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => {
      const anchor = this.template.querySelector('[data-id="detailsAnchor"]');
      if (anchor && typeof anchor.scrollIntoView === "function") {
        anchor.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    });
  }

  navigateToAccount(recordId) {
    if (!recordId) return;

    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId,
        objectApiName: "Account",
        actionName: "view"
      }
    });
  }
}
