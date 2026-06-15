import { LightningElement, wire, track } from 'lwc';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import getCustomers from '@salesforce/apex/MapCustomersController.getCustomers';
import ACCOUNT_OBJECT from '@salesforce/schema/Account';
import CONTRACT_BID_OBJECT from '@salesforce/schema/Contract_Bid__c';
import CONTRACT_PERIODS_FIELD from '@salesforce/schema/Account.Contract_Periods__c';
import COUNTY_FIELD from '@salesforce/schema/Account.County__c';
import CONTRACT_YEAR_FIELD from '@salesforce/schema/Contract_Bid__c.Contract_Year__c';

const REGIONAL_MANAGER_OPTIONS = [
    { label: 'All', value: '' },
    { label: 'Stephanie P.', value: 'Stephanie P.' },
    { label: 'Roman Shestakov', value: 'Roman Shestakov' },
    { label: 'Marijana Zarkovic', value: 'Marijana Zarkovic' },
    { label: 'Hamzah Alqwaqneh', value: 'Hamzah Alqwaqneh' },
    { label: 'Ammar Alkwakneh', value: 'Ammar Alkwakneh' },
    { label: 'Stanislav Kryshtalian', value: 'Stanislav Kryshtalian' }
];

const MAP_MARKER_PATH = 'M 0,0 C -2,-20 -10,-22 -10,-30 A 10,10 0 1,1 10,-30 C 10,-22 2,-20 0,0 z';
const STAGE_CLOSED_WON = 'Closed - WON';
const STAGE_CLOSED_LOST = 'Closed - LOST';
const MARKER_COLOR_WON = '#09A711';
const MARKER_COLOR_LOST = '#000000';
const MARKER_COLOR_NO_BID = '#EA001E';
const MARKER_COLOR_OTHER = '#FCC003';
const MARKER_COLOR_MULTI = '#0176D3';

export default class CustomersMap extends LightningElement {
    allCustomers = [];
    filteredCustomers = [];
    filteredMapMarkers = [];
    locationGroupMap = {};
    cardTitle = 'Customer Locations';
    @track selectedMarkerValue = '';
    @track selectedCustomer = null;
    @track selectedLocationKey = '';
    @track customersAtSelectedLocation = [];

    // Default map settings
    @track zoomLevel = 11;
    @track defaultZoomLevel = 11;
    @track center = {};
    @track defaultCenter = {};

    // Search properties
    @track searchTerm = '';
    @track selectedRegionalManager = '';
    @track selectedCounty = '';
    @track selectedContractPeriods = [];
    @track selectedContractYear = '';
    @track regionalManagerOptions = REGIONAL_MANAGER_OPTIONS;
    @track countyOptions = [];
    @track contractPeriodOptions = [];
    @track contractYearOptions = [];

    recordTypeId;
    contractBidRecordTypeId;

    mapOptions = {
        disableDefaultUI: false,
        draggable: true,
        scrollwheel: true
    };

    @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.recordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            console.error('Error loading Account object info:', error);
        }
    }

    @wire(getObjectInfo, { objectApiName: CONTRACT_BID_OBJECT })
    wiredContractBidObjectInfo({ data, error }) {
        if (data) {
            this.contractBidRecordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            console.error('Error loading Contract Bid object info:', error);
        }
    }

    @wire(getCustomers)
    wiredCustomers({ error, data }) {
        if (data) {
            this.allCustomers = data;
            this.filteredCustomers = data;
            this.cardTitle = `Customer Locations (${data.length})`;

            const firstMappableCustomer = data.find(customer => this.getCustomerMapLocation(customer));
            if (firstMappableCustomer) {
                const location = this.getCustomerMapLocation(firstMappableCustomer);
                this.center = { location };
                this.defaultCenter = { location };
            }

            this.updateFilteredMapMarkers(this.filteredCustomers);
        } else if (error) {
            console.error('Error loading customers:', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: CONTRACT_PERIODS_FIELD
    })
    wiredContractPeriods({ error, data }) {
        if (data) {
            this.contractPeriodOptions = data.values.map(entry => ({
                label: entry.label,
                value: entry.value
            }));
        } else if (error) {
            console.error('Error loading contract period picklist values:', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: COUNTY_FIELD
    })
    wiredCounty({ error, data }) {
        if (data) {
            this.countyOptions = data.values.map(entry => ({
                label: entry.label,
                value: entry.value
            }));

            this.countyOptions.unshift({
                label: 'All Counties',
                value: ''
            });
        } else if (error) {
            console.error('Error loading county picklist values:', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$contractBidRecordTypeId',
        fieldApiName: CONTRACT_YEAR_FIELD
    })
    wiredContractYear({ error, data }) {
        if (data) {
            this.contractYearOptions = data.values.map(entry => ({
                label: entry.label,
                value: entry.value
            }));

            this.contractYearOptions.unshift({
                label: 'All Contract Years',
                value: ''
            });
        } else if (error) {
            console.error('Error loading contract year picklist values:', error);
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
        this.searchTerm = '';
        this.selectedRegionalManager = '';
        this.selectedCounty = '';
        this.selectedContractPeriods = [];
        this.selectedContractYear = '';

        const inputs = this.template.querySelectorAll('lightning-input');
        inputs.forEach(input => {
            input.value = '';
        });

        const stateCombo = this.template.querySelector('[name="countyFilter"]');
        const contractPeriodFilter = this.template.querySelector('[name="contractPeriodFilter"]');
        const contractYearFilter = this.template.querySelector('[name="contractYearFilter"]');
        const regionalManagerCombo = this.template.querySelector('[data-name="regionalManagerFilter"]');

        if (stateCombo) stateCombo.value = '';
        if (contractPeriodFilter) contractPeriodFilter.value = [];
        if (contractYearFilter) contractYearFilter.value = '';
        if (regionalManagerCombo) regionalManagerCombo.value = '';

        this.resetZoomToDefault();
        this.selectedCustomer = null;
        this.selectedMarkerValue = '';
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

        const filtered = this.allCustomers.filter(customer =>
            this.customerMatchesAllFilters(customer)
        );

        this.filteredCustomers = filtered;
        this.cardTitle = `Customer Locations (${filtered.length} of ${this.allCustomers.length})`;
        this.updateFilteredMapMarkers(this.filteredCustomers);
        this.syncSelectedCustomer();
    }

    syncSelectedCustomer() {
        if (
            this.selectedCustomer &&
            !this.filteredCustomers.some(customer => customer.Id === this.selectedCustomer.Id)
        ) {
            this.selectedCustomer = null;
            this.selectedMarkerValue = '';
        }

        if (!this.selectedLocationKey) {
            return;
        }

        const visibleCustomers = (this.locationGroupMap[this.selectedLocationKey] || [])
            .filter(customer => this.filteredCustomers.some(filtered => filtered.Id === customer.Id));

        if (visibleCustomers.length === 0) {
            this.clearLocationSelection();
            return;
        }

        this.customersAtSelectedLocation = this.buildLocationCustomerSummaries(visibleCustomers);

        if (
            this.selectedCustomer &&
            !visibleCustomers.some(customer => customer.Id === this.selectedCustomer.Id)
        ) {
            this.selectedCustomer = null;
            this.selectedMarkerValue = `group:${this.selectedLocationKey}`;
        }
    }

    clearLocationSelection() {
        this.selectedLocationKey = '';
        this.customersAtSelectedLocation = [];
    }

    customerMatchesAllFilters(customer) {
        if (this.searchTerm) {
            const nameMatch = customer.Name && customer.Name.toLowerCase().includes(this.searchTerm);
            const emailMatch = customer.Email && customer.Email.toLowerCase().includes(this.searchTerm);
            if (!nameMatch && !emailMatch) return false;
        }

        if (this.selectedCounty && customer.County__c !== this.selectedCounty) {
            return false;
        }

        if (this.selectedRegionalManager) {
            if (!customer.Regional_Manager__c) {
                return false;
            }
            const managerName = customer.Regional_Manager__r.Name;
            if (managerName !== this.selectedRegionalManager) {
                return false;
            }
        }

        if (this.getSelectedContractPeriods().length > 0) {
            const customerPeriods = this.getCustomerContractPeriods(customer);
            if (customerPeriods.length === 0) {
                return false;
            }

            const hasMatchingPeriod = this.getSelectedContractPeriods().some(selectedPeriod =>
                customerPeriods.includes(selectedPeriod)
            );

            if (!hasMatchingPeriod) {
                return false;
            }
        }

        if (this.selectedContractYear) {
            const bid = customer.Recent_Contract_Bid__r;
            if (!bid || bid.Contract_Year__c !== this.selectedContractYear) {
                return false;
            }
        }

        return true;
    }

    updateFilteredMapMarkers(customerData) {
        const groups = new Map();

        customerData.forEach(customer => {
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
                    value: customer.Id,
                    title: customer.Name,
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
            'addr',
            customer.BillingStreet,
            customer.BillingCity,
            customer.BillingState,
            customer.BillingPostalCode,
            customer.BillingCountry
        ].join('|').toLowerCase();
    }

    getLocationGroupDescription(customers) {
        const address = this.formatCustomerAddress(customers[0]);
        let description = `<b>${customers.length} customers share this address</b><br/>${address}<br/><br/>`;

        customers.forEach(customer => {
            const status = this.getCustomerMarkerStatus(customer);
            description += `&#8226; ${customer.Name} (${status.label})<br/>`;
        });

        return description;
    }

    getLocationGroupMapIcon(customerCount) {
        return {
            path: MAP_MARKER_PATH,
            fillColor: MARKER_COLOR_MULTI,
            fillOpacity: 1,
            strokeColor: '#FFFFFF',
            strokeOpacity: 1,
            strokeWeight: 1.5,
            scale: customerCount > 5 ? 1.25 : 1.1
        };
    }

    buildLocationCustomerSummaries(customers) {
        return customers.map(customer => {
            const status = this.getCustomerMarkerStatus(customer);
            return {
                id: customer.Id,
                name: customer.Name,
                statusLabel: status.label,
                statusClass: status.badgeClass
            };
        });
    }

    formatCustomerAddress(customer) {
        const addressParts = [
            customer.BillingStreet,
            customer.BillingCity,
            customer.BillingState,
            customer.BillingPostalCode,
            customer.BillingCountry
        ].filter(part => part);

        return addressParts.length > 0 ? addressParts.join(', ') : 'Address not available';
    }

    hasCoordinates(customer) {
        return customer.BillingLatitude != null && customer.BillingLongitude != null;
    }

    hasPostalCode(customer) {
        return Boolean(customer.BillingPostalCode);
    }

    getCustomerMapLocation(customer) {
        if (this.hasCoordinates(customer)) {
            return {
                Latitude: customer.BillingLatitude,
                Longitude: customer.BillingLongitude
            };
        }

        if (customer.BillingStreet || customer.BillingCity || customer.BillingState) {
            return {
                Street: customer.BillingStreet,
                City: customer.BillingCity,
                State: customer.BillingState,
                PostalCode: customer.BillingPostalCode,
                Country: customer.BillingCountry
            };
        }

        if (this.hasPostalCode(customer)) {
            return { PostalCode: customer.BillingPostalCode };
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
        const bid = customer.Recent_Contract_Bid__r;

        if (!customer.Recent_Contract_Bid__c || !bid) {
            return {
                label: 'No Recent Bid',
                color: MARKER_COLOR_NO_BID,
                badgeClass: 'status-badge status-badge_no-bid',
                strokeColor: '#000000'
            };
        }

        if (bid.Stage__c === STAGE_CLOSED_WON) {
            return {
                label: STAGE_CLOSED_WON,
                color: MARKER_COLOR_WON,
                badgeClass: 'status-badge status-badge_won',
                strokeColor: '#000000'
            };
        }

        if (bid.Stage__c === STAGE_CLOSED_LOST) {
            return {
                label: STAGE_CLOSED_LOST,
                color: MARKER_COLOR_LOST,
                badgeClass: 'status-badge status-badge_lost',
                strokeColor: '#FFFFFF'
            };
        }

        return {
            label: bid.Stage__c || 'Other Stage',
            color: MARKER_COLOR_OTHER,
            badgeClass: 'status-badge status-badge_other',
            strokeColor: '#000000'
        };
    }

    get hasActiveFilters() {
        return this.searchTerm || this.selectedRegionalManager ||
            this.selectedCounty || this.selectedContractYear ||
            this.getSelectedContractPeriods().length > 0;
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
        if (!customer.Contract_Periods__c) {
            return [];
        }

        return customer.Contract_Periods__c
            .split(';')
            .map(period => period.trim())
            .filter(period => period);
    }

    getCustomerDescription(customer) {
        const address = this.formatCustomerAddress(customer);
        const markerStatus = this.getCustomerMarkerStatus(customer);

        let description = `<b>${markerStatus.label}</b><br/>Address: ${address}`;

        if (customer.Contract_Periods__c) {
            description += `<br/>Contract Periods: ${customer.Contract_Periods__c}`;
        }
        if (customer.Email__c) {
            description += `<br/>Email: ${customer.Email__c}`;
        }

        description += this.getRecentContractBidDescription(customer);

        return description;
    }

    getRecentContractBidDescription(customer) {
        const bid = customer.Recent_Contract_Bid__r;
        if (!bid) {
            return '<br/><br/><b>Recent Contract Bid:</b> None';
        }

        let description = '<br/><br/><b>Recent Contract Bid</b>';
        description += `<br/>Name: ${bid.Name || '—'}`;

        if (bid.Stage__c) {
            description += `<br/>Stage: ${bid.Stage__c}`;
        }
        if (bid.Contract_Year__c) {
            description += `<br/>Contract Year: ${bid.Contract_Year__c}`;
        }
        if (bid.Contract_Start_Date__c) {
            description += `<br/>Start Date: ${this.formatDate(bid.Contract_Start_Date__c)}`;
        }
        if (bid.Contract_End_Date__c) {
            description += `<br/>End Date: ${this.formatDate(bid.Contract_End_Date__c)}`;
        }
        if (bid.Due_Date__c) {
            description += `<br/>Due Date: ${this.formatDate(bid.Due_Date__c)}`;
        }
        if (bid.Total__c != null) {
            description += `<br/>Total: ${bid.Total__c}`;
        }

        return description;
    }

    formatDate(dateValue) {
        if (!dateValue) {
            return '';
        }

        const date = new Date(dateValue);
        if (Number.isNaN(date.getTime())) {
            return dateValue;
        }

        return date.toLocaleDateString();
    }

    get hasSelectedCustomer() {
        return Boolean(this.selectedCustomer);
    }

    get selectedCustomerStatusLabel() {
        if (!this.selectedCustomer) {
            return '';
        }

        return this.getCustomerMarkerStatus(this.selectedCustomer).label;
    }

    get selectedCustomerStatusClass() {
        if (!this.selectedCustomer) {
            return '';
        }

        return this.getCustomerMarkerStatus(this.selectedCustomer).badgeClass;
    }

    get selectedCustomerAddress() {
        if (!this.selectedCustomer) {
            return '';
        }

        return this.formatCustomerAddress(this.selectedCustomer);
    }

    get hasSelectedLocationGroup() {
        return this.customersAtSelectedLocation.length > 1;
    }

    get selectedLocationAddress() {
        if (!this.selectedLocationKey || !this.locationGroupMap[this.selectedLocationKey]?.length) {
            return '';
        }

        return this.formatCustomerAddress(this.locationGroupMap[this.selectedLocationKey][0]);
    }

    get selectedLocationCountLabel() {
        return `${this.customersAtSelectedLocation.length} customers at this address`;
    }

    get selectedRecentBid() {
        return this.selectedCustomer?.Recent_Contract_Bid__r || null;
    }

    get hasSelectedRecentBid() {
        return Boolean(this.selectedRecentBid);
    }

    get showSelectedRecentBidTotal() {
        return this.selectedRecentBid && this.selectedRecentBid.Total__c != null;
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

            if (markerValue.startsWith('group:')) {
                const locationKey = markerValue.replace('group:', '');
                this.selectedLocationKey = locationKey;
                this.selectedCustomer = null;
                this.customersAtSelectedLocation = this.buildLocationCustomerSummaries(
                    this.locationGroupMap[locationKey] || []
                );

                const firstCustomer = this.locationGroupMap[locationKey]?.[0];
                if (firstCustomer) {
                    this.zoomToCustomer(firstCustomer);
                }
                return;
            }

            this.clearLocationSelection();

            const selectedCustomer = this.allCustomers.find(customer => customer.Id === markerValue);
            if (selectedCustomer) {
                this.selectedCustomer = selectedCustomer;
                this.zoomToCustomer(selectedCustomer);
            }
        } catch (error) {
            console.error('Error in handleMarkerSelect:', error);
        }
    }

    handleLocationCustomerSelect(event) {
        const customerId = event.currentTarget.dataset.id;
        const selectedCustomer = this.allCustomers.find(customer => customer.Id === customerId);

        if (selectedCustomer) {
            this.selectedCustomer = selectedCustomer;
            this.selectedMarkerValue = customerId;
            this.zoomToCustomer(selectedCustomer);
        }
    }
}
