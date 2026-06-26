import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import getCustomers from '@salesforce/apex/MapCustomersController.getCustomers';
import ACCOUNT_OBJECT from '@salesforce/schema/Account';
import CONTRACT_BID_OBJECT from '@salesforce/schema/Contract_Bid__c';
import CONTRACT_PERIODS_FIELD from '@salesforce/schema/Account.Contract_Periods__c';
import COUNTY_FIELD from '@salesforce/schema/Account.County__c';
import CONTRACT_YEAR_FIELD from '@salesforce/schema/Contract_Bid__c.Contract_Year__c';
import STAGE_FIELD from '@salesforce/schema/Contract_Bid__c.Stage__c';

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
const STAGE_CLOSED_LOST = 'Closed - LOST';
const STAGE_CONTRACT_SENT = 'Contract Sent via DocuSign';
const CLOSED_STAGES = new Set(['Closed - WON', STAGE_CLOSED_LOST]);
const MARKER_COLOR_CURRENT = '#09A711';
const MARKER_COLOR_CONTRACT_SENT = '#FCC003';
const MARKER_COLOR_OPPORTUNITY = '#1B96FF';
const MARKER_COLOR_CLOSED_LOST = '#EA001E';
const MARKER_COLOR_ACTIVE_BID = '#FF7A00';
const MARKER_COLOR_MULTI = '#032D60';

export default class CustomersMap extends NavigationMixin(LightningElement) {
    allCustomers = [];
    filteredCustomers = [];
    filteredMapMarkers = [];
    locationGroupMap = {};
    cardTitle = 'Customer Locations';
    loadErrorMessage = '';
    @track selectedMarkerValue = '';
    @track selectedCustomerDetails = [];
    @track selectedLocationKey = '';

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
    stageOrder = [];

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

    @wire(getPicklistValues, {
        recordTypeId: '$contractBidRecordTypeId',
        fieldApiName: STAGE_FIELD
    })
    wiredStageValues({ error, data }) {
        if (data) {
            this.stageOrder = data.values.map(entry => entry.value);
            if (this.hasAnySelection) {
                this.syncSelectedCustomer();
            }
        } else if (error) {
            console.error('Error loading contract bid stage picklist values:', error);
        }
    }

    @wire(getCustomers)
    wiredCustomers({ error, data }) {
        if (data) {
            this.loadErrorMessage = '';
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
            // Show error in UI (wire errors are otherwise invisible)
            // eslint-disable-next-line no-console
            console.error('Error loading customers:', error);
            this.loadErrorMessage = this.normalizeErrorMessage(error) || 'Error loading customers.';
            this.allCustomers = [];
            this.filteredCustomers = [];
            this.filteredMapMarkers = [];
        }
    }

    normalizeErrorMessage(error) {
        if (!error) return '';
        const body = error.body;
        if (Array.isArray(body)) {
            return body.map(e => e.message).filter(Boolean).join(', ');
        }
        if (typeof body === 'string') return body;
        if (body && typeof body.message === 'string') return body.message;
        if (typeof error.message === 'string') return error.message;
        return '';
    }

    get hasLoadError() {
        return Boolean(this.loadErrorMessage);
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
        this.selectedCustomerDetails = [];
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
        if (this.selectedLocationKey) {
            const visibleCustomers = (this.locationGroupMap[this.selectedLocationKey] || [])
                .filter(customer => this.filteredCustomers.some(filtered => filtered.accountId === customer.accountId));

            if (visibleCustomers.length === 0) {
                this.clearSelection();
                return;
            }

            this.selectedCustomerDetails = visibleCustomers.map(customer =>
                this.buildCustomerDetailView(customer)
            );
            this.selectedMarkerValue = `group:${this.selectedLocationKey}`;
            return;
        }

        if (!this.selectedMarkerValue || this.selectedMarkerValue.startsWith('group:')) {
            return;
        }

        const customer = this.filteredCustomers.find(
            filtered => filtered.accountId === this.selectedMarkerValue
        );

        if (!customer) {
            this.clearSelection();
            return;
        }

        this.selectedCustomerDetails = [this.buildCustomerDetailView(customer)];
    }

    clearLocationSelection() {
        this.selectedLocationKey = '';
    }

    clearSelection() {
        this.selectedCustomerDetails = [];
        this.selectedMarkerValue = '';
        this.clearLocationSelection();
    }

    get hasAnySelection() {
        return this.selectedCustomerDetails.length > 0;
    }

    customerMatchesAllFilters(customer) {
        if (this.searchTerm) {
            const nameMatch = customer.name && customer.name.toLowerCase().includes(this.searchTerm);
            const emailMatch = customer.email && customer.email.toLowerCase().includes(this.searchTerm);
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

            const hasMatchingPeriod = this.getSelectedContractPeriods().some(selectedPeriod =>
                customerPeriods.includes(selectedPeriod)
            );

            if (!hasMatchingPeriod) {
                return false;
            }
        }

        if (this.selectedContractYear) {
            if (!customer.contractYear || customer.contractYear !== this.selectedContractYear) {
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
            'addr',
            customer.billingStreet,
            customer.billingCity,
            customer.billingState,
            customer.billingPostalCode,
            customer.billingCountry
        ].join('|').toLowerCase();
    }

    getLocationGroupDescription(customers) {
        const address = this.formatCustomerAddress(customers[0]);
        let description = `<b>${customers.length} customers share this address</b><br/>${address}<br/><br/>`;

        customers.forEach(customer => {
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
            strokeColor: '#FFFFFF',
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
            managementCompanyName: customer.managementCompanyName,
            managementCompanyUrl: customer.managementCompanyId
                ? `/lightning/r/Management_Company__c/${customer.managementCompanyId}/view`
                : '',
            hasManagementCompany: Boolean(customer.managementCompanyName),
            primaryContactId: customer.primaryContactId,
            primaryContactName: customer.primaryContactName,
            primaryContactUrl: customer.primaryContactId
                ? `/lightning/r/Contact/${customer.primaryContactId}/view`
                : '',
            primaryContactPhone: customer.primaryContactPhone,
            primaryContactEmail: customer.primaryContactEmail,
            hasPrimaryContact: Boolean(customer.primaryContactId),
            regionalManagerName: customer.regionalManagerName,
            contractBidColoredLabels: customer.contractBidColoredLabels,
            lastActivitySubject: customer.lastActivitySubject,
            lastActivityType: customer.lastActivityType,
            lastActivityDateTime: customer.lastActivityDateTime,
            contractBidUrl: customer.contractBidId
                ? `/lightning/r/Contract_Bid__c/${customer.contractBidId}/view`
                : '',
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
        ].filter(part => part);

        return addressParts.length > 0 ? addressParts.join(', ') : 'Address not available';
    }

    hasCoordinates(customer) {
        return customer.billingLatitude != null && customer.billingLongitude != null;
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

        if (customer.billingStreet || customer.billingCity || customer.billingState) {
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
                label: 'Current Customer',
                color: MARKER_COLOR_CURRENT,
                badgeClass: 'status-badge status-badge_current',
                strokeColor: '#000000'
            };
        }

        if (stage === STAGE_CLOSED_LOST) {
            return {
                label: STAGE_CLOSED_LOST,
                color: MARKER_COLOR_CLOSED_LOST,
                badgeClass: 'status-badge status-badge_closed-lost',
                strokeColor: '#FFFFFF'
            };
        }

        if (stage === STAGE_CONTRACT_SENT) {
            return {
                label: STAGE_CONTRACT_SENT,
                color: MARKER_COLOR_CONTRACT_SENT,
                badgeClass: 'status-badge status-badge_contract-sent',
                strokeColor: '#000000'
            };
        }

        if (this.isBidOpportunity(customer, today)) {
            return {
                label: 'Bid Opportunity',
                color: MARKER_COLOR_OPPORTUNITY,
                badgeClass: 'status-badge status-badge_opportunity',
                strokeColor: '#FFFFFF'
            };
        }

        if (this.isActivePipeline(customer, today)) {
            return {
                label: stage || 'Active Bid',
                color: MARKER_COLOR_ACTIVE_BID,
                badgeClass: 'status-badge status-badge_active-bid',
                strokeColor: '#000000'
            };
        }

        return {
            label: stage || 'Active Bid',
            color: MARKER_COLOR_ACTIVE_BID,
            badgeClass: 'status-badge status-badge_active-bid',
            strokeColor: '#000000'
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

        if (typeof dateValue === 'string') {
            const [year, month, day] = dateValue.split('T')[0].split('-').map(Number);
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

        if (!this.isDateInCurrentCalendarYear(customer.accountContractEndDate, today)) {
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
        if (!customer.contractPeriods) {
            return [];
        }

        return customer.contractPeriods
            .split(';')
            .map(period => period.trim())
            .filter(period => period);
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
            return '<br/><br/><b>Recent Contract Bid:</b> None';
        }

        const bidUrl = `/lightning/r/Contract_Bid__c/${customer.contractBidId}/view`;
        let description = '<br/><br/><b>Recent Contract Bid</b>';
        description += `<br/>Name: <a href="${bidUrl}" target="_blank" rel="noopener noreferrer">${customer.contractBidName || '—'}</a>`;

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
            return '';
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
        if (!this.selectedLocationKey || !this.locationGroupMap[this.selectedLocationKey]?.length) {
            return '';
        }

        return this.formatCustomerAddress(this.locationGroupMap[this.selectedLocationKey][0]);
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

            if (markerValue.startsWith('group:')) {
                const locationKey = markerValue.replace('group:', '');
                const customers = this.locationGroupMap[locationKey] || [];
                this.selectedLocationKey = locationKey;
                this.selectedCustomerDetails = customers.map(customer =>
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

            const selectedCustomer = this.allCustomers.find(customer => customer.accountId === markerValue);
            if (selectedCustomer) {
                this.selectedCustomerDetails = [this.buildCustomerDetailView(selectedCustomer)];
                this.zoomToCustomer(selectedCustomer);
            }
            this.scrollToDetails();
        } catch (error) {
            console.error('Error in handleMarkerSelect:', error);
        }
    }

    handleNavigateToAccountFromDetail(event) {
        this.navigateToAccount(event.currentTarget.dataset.id);
    }

    scrollToDetails() {
        requestAnimationFrame(() => {
            const anchor = this.template.querySelector('[data-id="detailsAnchor"]');
            if (anchor && typeof anchor.scrollIntoView === 'function') {
                anchor.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
        });
    }

    navigateToAccount(recordId) {
        if (!recordId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }
}
