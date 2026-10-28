import { LightningElement, wire, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { getPicklistValues, getObjectInfo } from "lightning/uiObjectInfoApi";
import FORM_FACTOR from "@salesforce/client/formFactor";
import { loadScript, loadStyle } from "lightning/platformResourceLoader";
import LEAFLET from "@salesforce/resourceUrl/leaflet";
import MAPTILER_API_KEY from "@salesforce/label/c.MapTiler_Api_Key";
import desktopTemplate from "./customersMap.html";
import mobileTemplate from "./customersMapMobile.html";
import getCustomers from "@salesforce/apex/MapCustomersController.getCustomers";
import saveMapCoordinates from "@salesforce/apex/MapCustomersController.saveMapCoordinates";
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
const MOBILE_BOTTOM_GAP = 8;
const MAP_TILE_URL =
  "https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=";
const MAP_ATTRIBUTION =
  '&copy; <a href="https://www.maptiler.com/copyright/">MapTiler</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';
const GEOCODE_CACHE_KEY = "ppmCustomersMapGeocodes";
const GEOCODE_MAX_BATCH = 8;
const GEOCODE_MAX_PATH = 1400;
const DEFAULT_MAP_CENTER = [39.8283, -98.5795];
const DEFAULT_MAP_ZOOM = 4;

export default class CustomersMap extends NavigationMixin(LightningElement) {
  isMobile = IS_MOBILE;
  @track isFiltersOpen = false;
  @track isLandscapeMode = false;
  locatingMessage = "";
  mapError = "";
  _restoreLandscapeAfterOverlay = false;
  _map;
  _markerLayer;
  _leafletLoading = false;
  _leafletReady = false;
  _leafletFailed = false;
  _markerSignature = "";
  _geocodeCache = {};
  _geocodeRunning = false;
  _geocodeDone = false;
  _onResize;

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

  render() {
    return IS_MOBILE ? mobileTemplate : desktopTemplate;
  }

  connectedCallback() {
    this._geocodeCache = this.readGeocodeCache();
    this._onResize = () => {
      if (IS_MOBILE) {
        this.updateMobileShellHeight();
      }
      this.refreshMapSize();
    };
    window.addEventListener("resize", this._onResize);
    window.addEventListener("orientationchange", this._onResize);
  }

  disconnectedCallback() {
    if (this._onResize) {
      window.removeEventListener("resize", this._onResize);
      window.removeEventListener("orientationchange", this._onResize);
      this._onResize = null;
    }
    this.destroyMap();
  }

  renderedCallback() {
    if (IS_MOBILE) {
      this.updateMobileShellHeight();
    }
    const mapInDom = !IS_MOBILE || this.showMapView;
    if (!mapInDom || !this.hasMapCandidates) {
      this.destroyMap();
      return;
    }
    if (this._leafletFailed) {
      return;
    }
    if (!this._leafletReady) {
      if (!this._leafletLoading) {
        this.loadLeaflet();
      }
      return;
    }
    this.ensureMap();
    this.renderMarkers();
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
      this.refreshMapSize();
      return;
    }
    const top = Math.max(shell.getBoundingClientRect().top, 0);
    const available = window.innerHeight - top - MOBILE_BOTTOM_GAP;
    const height = `${Math.max(available, MOBILE_MIN_SHELL_HEIGHT)}px`;
    if (shell.style.height !== height) {
      shell.style.height = height;
    }
    this.refreshMapSize();
  }

  loadLeaflet() {
    this._leafletLoading = true;
    Promise.all([
      loadScript(this, LEAFLET + "/leaflet.js"),
      loadStyle(this, LEAFLET + "/leaflet.css")
    ])
      .then(() => {
        this._leafletReady = true;
        this._leafletLoading = false;
        this.ensureMap();
        this.renderMarkers();
      })
      .catch((error) => {
        this._leafletLoading = false;
        this._leafletFailed = true;
        this.mapError = error?.message || "Map failed to load.";
      });
  }

  ensureMap() {
    if (this._map || !window.L) {
      return;
    }
    const root = this.template.querySelector(".map-root");
    if (!root) {
      return;
    }

    const map = window.L.map(root, {
      zoomControl: !IS_MOBILE,
      attributionControl: true
    }).setView(DEFAULT_MAP_CENTER, DEFAULT_MAP_ZOOM);
    window.L.tileLayer(MAP_TILE_URL + MAPTILER_API_KEY, {
      attribution: MAP_ATTRIBUTION,
      maxZoom: 20,
      tileSize: 256
    }).addTo(map);
    this._map = map;
    this._markerLayer = window.L.featureGroup().addTo(map);
    map.on("moveend", () => {
      if (this._ignoreMove) {
        return;
      }
      this.rememberMapView();
    });
    this.refreshMapSize();
  }

  rememberMapView() {
    if (!this._map) {
      return;
    }
    const center = this._map.getCenter();
    if (!center) {
      return;
    }
    this._savedView = {
      lat: center.lat,
      lng: center.lng,
      zoom: this._map.getZoom()
    };
  }

  applySavedView() {
    if (!this._map || !this._savedView) {
      return;
    }
    this._ignoreMove = true;
    this._map.setView(
      [this._savedView.lat, this._savedView.lng],
      this._savedView.zoom,
      {
        animate: false
      }
    );
    this._ignoreMove = false;
  }

  destroyMap() {
    if (this._map) {
      this.rememberMapView();
      this._map.remove();
    }
    this._map = null;
    this._markerLayer = null;
    this._markerSignature = "";
  }

  renderMarkers() {
    if (!this._map || !this._markerLayer) {
      return;
    }

    const markers = this.filteredMapMarkers || [];
    const signature = markers
      .map((marker) => `${marker.value}:${marker.mapIcon?.fillColor}`)
      .join("|");
    if (signature === this._markerSignature) {
      return;
    }

    this._markerSignature = signature;
    this._markerLayer.clearLayers();
    markers.forEach((pin) => {
      const latitude = pin.location?.Latitude;
      const longitude = pin.location?.Longitude;
      if (latitude == null || longitude == null) {
        return;
      }
      const marker = window.L.marker([latitude, longitude], {
        icon: this.createPinIcon(pin.mapIcon),
        title: pin.title
      });
      marker.on("click", () => this.selectMarker(pin.value));
      marker.addTo(this._markerLayer);
    });
    if (this._savedView) {
      this.applySavedView();
      this._restoreAfterSize = true;
    } else {
      this.fitMapToMarkers();
    }
    this.refreshMapSize();
  }

  createPinIcon(mapIcon) {
    const scale = mapIcon?.scale || 1;
    const width = Math.round(24 * scale);
    const height = Math.round(36 * scale);
    const fill = mapIcon?.fillColor || MARKER_COLOR_ACTIVE_BID;
    const stroke = mapIcon?.strokeColor || "#FFFFFF";
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="-12 -34 24 36"><path d="${MAP_MARKER_PATH}" fill="${fill}" stroke="${stroke}" stroke-width="1.5"/></svg>`;
    return window.L.divIcon({
      className: "customer-pin",
      html: svg,
      iconSize: [width, height],
      iconAnchor: [Math.round(width / 2), Math.round((height * 34) / 36)]
    });
  }

  fitMapToMarkers() {
    if (
      !this._map ||
      !this._markerLayer ||
      !this._markerLayer.getLayers().length
    ) {
      return;
    }
    this._ignoreMove = true;
    this._map.fitBounds(this._markerLayer.getBounds().pad(0.15), {
      animate: false,
      maxZoom: 15,
      padding: [24, 24]
    });
    this._ignoreMove = false;
  }

  refreshMapSize() {
    if (!this._map) {
      return;
    }
    this._map.invalidateSize();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.setTimeout(() => {
      if (!this._map) {
        return;
      }
      this._map.invalidateSize();
      if (this._restoreAfterSize && this._savedView) {
        this.applySavedView();
        this._restoreAfterSize = false;
      }
    }, 250);
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
    this.refreshMapSize();
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
      this.updateFilteredMapMarkers(this.filteredCustomers);
      this.scheduleGeocoding();
    } else if (error) {
      // Show error in UI (wire errors are otherwise invisible)
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
    this._savedView = null;
    this.fitMapToMarkers();
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

  getCustomerMapLocation(customer) {
    return this.getResolvedCoordinates(customer);
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

  get hasMapCandidates() {
    return (this.filteredCustomers || []).some(
      (customer) =>
        this.getResolvedCoordinates(customer) ||
        this.buildGeocodeQuery(customer)
    );
  }

  getResolvedCoordinates(customer) {
    const cached = this._geocodeCache?.[customer.accountId];
    if (cached && cached.lat != null && cached.lng != null) {
      return {
        Latitude: Number(cached.lat),
        Longitude: Number(cached.lng)
      };
    }
    if (customer.billingLatitude != null && customer.billingLongitude != null) {
      return {
        Latitude: Number(customer.billingLatitude),
        Longitude: Number(customer.billingLongitude)
      };
    }
    return null;
  }

  buildGeocodeQuery(customer) {
    return [
      customer.billingStreet,
      customer.billingCity,
      customer.billingState,
      customer.billingPostalCode,
      customer.billingCountry
    ]
      .filter((part) => part)
      .join(", ")
      .replace(/;/g, " ")
      .trim();
  }

  readGeocodeCache() {
    try {
      const raw = window.sessionStorage.getItem(GEOCODE_CACHE_KEY);
      return raw ? JSON.parse(raw) : {};
    } catch {
      return {};
    }
  }

  writeGeocodeCache() {
    try {
      window.sessionStorage.setItem(
        GEOCODE_CACHE_KEY,
        JSON.stringify(this._geocodeCache)
      );
    } catch {
      // The map still renders if the browser refuses to store the cache.
    }
  }

  scheduleGeocoding() {
    if (this._geocodeRunning || this._geocodeDone) {
      return;
    }
    const pending = (this.allCustomers || []).filter(
      (customer) =>
        !this.getResolvedCoordinates(customer) &&
        this.buildGeocodeQuery(customer)
    );
    if (!pending.length) {
      this._geocodeDone = true;
      return;
    }
    this._geocodeRunning = true;
    this.geocodeCustomers(pending);
  }

  packGeocodeBatches(customers) {
    const batches = [];
    let batch = [];
    let pathLength = 0;
    customers.forEach((customer) => {
      const encoded = encodeURIComponent(
        this.buildGeocodeQuery(customer).slice(0, 160)
      );
      const nextLength = pathLength + encoded.length + (batch.length ? 1 : 0);
      if (
        batch.length &&
        (batch.length >= GEOCODE_MAX_BATCH || nextLength > GEOCODE_MAX_PATH)
      ) {
        batches.push(batch);
        batch = [];
        pathLength = 0;
      }
      batch.push(customer);
      pathLength += encoded.length + (batch.length > 1 ? 1 : 0);
    });
    if (batch.length) {
      batches.push(batch);
    }
    return batches;
  }

  async geocodeCustomers(pending) {
    const located = [];
    let finished = 0;
    const batches = this.packGeocodeBatches(pending);
    try {
      for (const batch of batches) {
        // eslint-disable-next-line no-await-in-loop
        const found = await this.geocodeBatch(batch);
        found.forEach((item) => {
          this._geocodeCache[item.accountId] = {
            lat: item.latitude,
            lng: item.longitude
          };
          located.push(item);
        });
        this.writeGeocodeCache();
        finished += batch.length;
        this.locatingMessage = `Locating addresses ${Math.min(finished, pending.length)} of ${pending.length}`;
        this.updateFilteredMapMarkers(this.filteredCustomers);
      }
    } catch (error) {
      this.mapError = error?.message || "Addresses could not be located.";
    } finally {
      this.locatingMessage = "";
      this._geocodeRunning = false;
      this._geocodeDone = true;
    }
    if (located.length) {
      this.mapError = "";
      this.saveResolvedCoordinates(located);
    } else if (!this.hasFilteredMarkers) {
      this.mapError = "Addresses could not be located.";
    }
  }

  async geocodeBatch(customers) {
    const path = customers
      .map((customer) =>
        encodeURIComponent(this.buildGeocodeQuery(customer).slice(0, 160))
      )
      .join(";");
    const response = await fetch(
      `https://api.maptiler.com/geocoding/${path}.json?key=${MAPTILER_API_KEY}&limit=1`
    );
    if (response.status === 414 && customers.length > 1) {
      const middle = Math.ceil(customers.length / 2);
      const left = await this.geocodeBatch(customers.slice(0, middle));
      const right = await this.geocodeBatch(customers.slice(middle));
      return left.concat(right);
    }
    if (!response.ok) {
      console.error("Geocoding failed", response.status);
      return [];
    }
    const payload = await response.json();
    const collections = Array.isArray(payload) ? payload : [payload];
    const found = [];
    collections.forEach((collection, index) => {
      const coordinates = collection?.features?.[0]?.geometry?.coordinates;
      const customer = customers[index];
      if (!customer || !coordinates || coordinates.length < 2) {
        return;
      }
      found.push({
        accountId: customer.accountId,
        latitude: coordinates[1],
        longitude: coordinates[0]
      });
    });
    return found;
  }

  async saveResolvedCoordinates(rows) {
    for (let index = 0; index < rows.length; index += 200) {
      const updates = rows.slice(index, index + 200);
      try {
        // eslint-disable-next-line no-await-in-loop
        await saveMapCoordinates({ updates });
      } catch (error) {
        console.error("Error saving map coordinates:", error);
      }
    }
  }

  zoomToCustomer(customer) {
    const location = this.getCustomerMapLocation(customer);
    if (!this._map || !location) {
      return;
    }
    this._map.setView([location.Latitude, location.Longitude], 15);
  }

  selectMarker(markerValue) {
    if (!markerValue) {
      return;
    }
    try {
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
        if (firstCustomer && !IS_MOBILE) {
          this.zoomToCustomer(firstCustomer);
        }
        this.scrollToDetails();
        return;
      }

      this.clearLocationSelection();
      const selectedCustomer = this.allCustomers.find(
        (customer) => customer.accountId === markerValue
      );
      if (selectedCustomer && !IS_MOBILE) {
        this.selectedCustomerDetails = [
          this.buildCustomerDetailView(selectedCustomer)
        ];
        this.zoomToCustomer(selectedCustomer);
      } else if (selectedCustomer) {
        this.selectedCustomerDetails = [
          this.buildCustomerDetailView(selectedCustomer)
        ];
      }
      this.scrollToDetails();
    } catch (error) {
      console.error("Error in selectMarker:", error);
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
