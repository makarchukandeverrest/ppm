import { LightningElement, wire, track } from 'lwc';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import getCustomers from '@salesforce/apex/MapCustomersController.getCustomers';
import CONTRACT_PERIODS_FIELD from '@salesforce/schema/Account.Contract_Periods__c';
import COUNTY_FIELD from '@salesforce/schema/Account.County__c';

const REGIONAL_MANAGER_OPTIONS = [
    { label: 'All', value: '' },
    { label: 'Stephanie P.', value: 'Stephanie P.' },
    { label: 'Roman Shestakov', value: 'Roman Shestakov' },
    { label: 'Marijana Zarkovic', value: 'Marijana Zarkovic' },
    { label: 'Hamzah Alqwaqneh', value: 'Hamzah Alqwaqneh' },
    { label: 'Ammar Alkwakneh', value: 'Ammar Alkwakneh' },
    { label: 'Stanislav Kryshtalian', value: 'Stanislav Kryshtalian' }
];

const COLUMNS = [
    {
        label: 'Customer Name',
        type: 'button',
        typeAttributes: {
            label: { fieldName: 'Name' },
            variant: 'base',
            name: 'view_customer',
            title: 'Click to view customer details'
        },
        sortable: true,
        wrapText: true
    },
    {
        label: 'Street',
        fieldName: 'BillingStreet',
        type: 'text',
        sortable: true
    },
    {
        label: 'City',
        fieldName: 'BillingCity',
        type: 'text',
        sortable: true
    },
    {
        label: 'State',
        fieldName: 'BillingState',
        type: 'text',
        sortable: true
    },
    {
        label: 'Contract Periods',
        fieldName: 'Contract_Periods__c',
        type: 'text',
        sortable: true
    }
];

export default class CustomersMap extends LightningElement {
    mapMarkers = [];
    allCustomers = [];
    filteredCustomers = [];
    filteredMapMarkers = [];
    columns = COLUMNS;
    cardTitle = 'Customer Locations';
    isLoading = true;
    @track selectedMarkerValue = '';
    
    // Pagination
    @track pageSize = 10;
    @track currentPage = 1;
    
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
    @track regionalManagerOptions = REGIONAL_MANAGER_OPTIONS;
    @track countyOptions = [];
    @track contractPeriodOptions = [];
    
    // Record type ID (use default record type if you have multiple)
    // For standard objects, you can often use the default record type ID
    recordTypeId = '012000000000000AAA'; // Default record type ID
    
    // Map options
    mapOptions = {
        'disableDefaultUI': false,
        'draggable': true,
        'scrollwheel': true
    };

    // Wire for customers data
    @wire(getCustomers)
    wiredCustomers({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.allCustomers = data;
            this.filteredCustomers = data;
            this.cardTitle = `Customer Locations (${data.length})`;
            
            // Set initial center
            if (data.length > 0 && data[0].BillingPostalCode) {
                this.center = {
                    location: { PostalCode: data[0].BillingPostalCode }
                };
                this.defaultCenter = {
                    location: { PostalCode: data[0].BillingPostalCode }
                };
            }

            // Initialize markers based on current page
            this.updateFilteredMapMarkers(this.filteredCustomers);
        } else if (error) {
            console.error('Error loading customers:', error);
        }
    }

    // Wire for Contract Periods picklist values using getPicklistValues
    @wire(getPicklistValues, { 
        recordTypeId: '$recordTypeId', 
        fieldApiName: CONTRACT_PERIODS_FIELD 
    })
    wiredContractPeriods({ error, data }) {
        if (data) {
            // Convert picklist entries to options array
            this.contractPeriodOptions = data.values.map(entry => ({
                label: entry.label,
                value: entry.value
            }));
            console.log('Contract Period options loaded via getPicklistValues:', this.contractPeriodOptions);
        } else if (error) {
            console.error('Error loading contract period picklist values:', error);
            // Fallback: You could still call Apex if needed
        }
    }

    // Wire for County picklist values using getPicklistValues
    @wire(getPicklistValues, { 
        recordTypeId: '$recordTypeId', 
        fieldApiName: COUNTY_FIELD 
    })
    wiredCounty({ error, data }) {
        if (data) {
            // Convert picklist entries to options array
            this.countyOptions = data.values.map(entry => ({
                label: entry.label,
                value: entry.value
            }));
            
            // Add "All Counties" option at the beginning
            this.countyOptions.unshift({
                label: 'All Counties',
                value: ''
            });
            
            console.log('County options loaded via getPicklistValues:', this.countyOptions);
        } else if (error) {
            console.error('Error loading county picklist values:', error);
            // Fallback: You could still call Apex if needed
        }
    }

    updateMapMarkers(customerData) {
        const staticMarkers = this.mapMarkers.filter(marker => 
            marker.type === 'Polygon' || marker.mapIcon
        );
        
        // Use current page slice for markers so map matches datatable
        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        const pageCustomers = customerData.slice(start, end);
        
        const customerMarkers = pageCustomers.map(customer => {
            return {
                location: { 
                    PostalCode: customer.BillingPostalCode
                },
                value: customer.Id,
                title: customer.Name,
                description: this.getCustomerDescription(customer),
                icon: 'standard:account'
            };
        });

        this.mapMarkers = [...customerMarkers, ...staticMarkers];
        this.filteredMapMarkers = [...customerMarkers, ...staticMarkers];
    }

    // Search handlers
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

    // Handle Contract Periods multi-select
    handleContractPeriodsChange(event) {
        this.selectedContractPeriods = event.detail.value;
        this.filterCustomers();
        console.log('Selected Contract Periods:', this.selectedContractPeriods);
    }

    // Clear all filters and reset zoom
    handleClearSearch() {
        this.searchTerm = '';
        this.selectedRegionalManager = '';
        this.selectedCounty = '';
        this.selectedContractPeriods = [];
        
        // Clear input fields
        const inputs = this.template.querySelectorAll('lightning-input');
        inputs.forEach(input => {
            input.value = '';
        });
        
        // Clear comboboxes
        const stateCombo = this.template.querySelector('[name="countyFilter"]');
        const contactPeriodCombo = this.template.querySelector('[data-name="contractPeriodFilter"]');
        const regionalManagerCombo = this.template.querySelector('[data-name="regionalManagerFilter"]');
        
        if (stateCombo) stateCombo.value = '';
        if (contactPeriodCombo) contactPeriodCombo.value = [];
        if (regionalManagerCombo) regionalManagerCombo.value = '';
        
        // Reset zoom to default state
        this.resetZoomToDefault();
        
        this.filterCustomers();
    }

    // Reset zoom and center to default state
    resetZoomToDefault() {
        this.zoomLevel = this.defaultZoomLevel;
        this.center = {...this.defaultCenter};
        console.log('Map reset to default zoom and center');
    }

    // Filter customers based on all search criteria
    filterCustomers() {
        if (!this.hasActiveFilters) {
            this.filteredCustomers = [...this.allCustomers];
            this.cardTitle = `Customer Locations (${this.allCustomers.length})`;
            this.currentPage = 1;
            this.updateFilteredMapMarkers(this.filteredCustomers);
            return;
        }

        const filtered = this.allCustomers.filter(customer => 
            this.customerMatchesAllFilters(customer)
        );
        
        this.filteredCustomers = filtered;
        this.cardTitle = `Customer Locations (${filtered.length} of ${this.allCustomers.length})`;
        this.currentPage = 1;
        this.updateFilteredMapMarkers(this.filteredCustomers);
    }

    // Check if customer matches all active filters
    customerMatchesAllFilters(customer) {
        // Name/Email filter
        if (this.searchTerm) {
            const nameMatch = customer.Name && customer.Name.toLowerCase().includes(this.searchTerm);
            const emailMatch = customer.Email && customer.Email.toLowerCase().includes(this.searchTerm);
            if (!nameMatch && !emailMatch) return false;
        }

        // County filter
        if (this.selectedCounty && customer.County__c !== this.selectedCounty) {
            return false;
        }

        // Regional Manager filter
        if (this.selectedRegionalManager) {
            if (!customer.Regional_Manager__c) {
                return false;
            }
            const managerName = customer.Regional_Manager__r.Name;
            const managerMatch = managerName === this.selectedRegionalManager;
            if (!managerMatch) {
                return false;
            }
        }

        // Contract Periods filter (multi-select picklist)
        if (this.selectedContractPeriods && this.selectedContractPeriods.length > 0) {
            if (!customer.Contract_Periods__c) return false;
            
            // Split the multi-select picklist value
            const customerPeriods = customer.Contract_Periods__c.split(';').map(p => p.trim());
            
            // Check if ANY of the selected periods match ANY of the customer's periods
            const hasMatchingPeriod = this.selectedContractPeriods.some(selectedPeriod => 
                customerPeriods.includes(selectedPeriod)
            );
            
            if (!hasMatchingPeriod) return false;
        }

        return true;
    }

    // Update only the filtered map markers
    updateFilteredMapMarkers(customerData) {
        const staticMarkers = this.mapMarkers.filter(marker => 
            marker.type === 'Polygon' || marker.mapIcon
        );

        // Use current page slice so map markers match the datatable page
        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        const pageCustomers = customerData.slice(start, end);

        const customerMarkers = pageCustomers.map(customer => {
            return {
                location: { 
                    PostalCode: customer.BillingPostalCode
                },
                value: customer.Id,
                title: customer.Name,
                description: this.getCustomerDescription(customer),
                icon: 'standard:account'
            };
        });

        this.filteredMapMarkers = [...customerMarkers, ...staticMarkers];
    }

    // Pagination helpers
    get pagedCustomers() {
        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        return this.filteredCustomers.slice(start, end);
    }

    get totalPages() {
        if (!this.filteredCustomers || this.filteredCustomers.length === 0) {
            return 1;
        }
        return Math.ceil(this.filteredCustomers.length / this.pageSize);
    }

    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    get totalRecords() {
        return this.filteredCustomers ? this.filteredCustomers.length : 0;
    }

    handlePageSizeClick(event) {
        const size = parseInt(event.target.dataset.size, 10);
        if (!isNaN(size) && size > 0) {
            this.pageSize = size;
            this.currentPage = 1;
            this.updateFilteredMapMarkers(this.filteredCustomers);
        }
    }

    handleFirstPage() {
        if (!this.isFirstPage) {
            this.currentPage = 1;
            this.updateFilteredMapMarkers(this.filteredCustomers);
        }
    }

    handlePreviousPage() {
        if (!this.isFirstPage) {
            this.currentPage -= 1;
            this.updateFilteredMapMarkers(this.filteredCustomers);
        }
    }

    handleNextPage() {
        if (!this.isLastPage) {
            this.currentPage += 1;
            this.updateFilteredMapMarkers(this.filteredCustomers);
        }
    }

    handleLastPage() {
        if (!this.isLastPage) {
            this.currentPage = this.totalPages;
            this.updateFilteredMapMarkers(this.filteredCustomers);
        }
    }

    // Computed property to check if any filters are active
    get hasActiveFilters() {
        return this.searchTerm || this.selectedRegionalManager || 
               this.selectedCounty || (this.selectedContractPeriods && this.selectedContractPeriods.length > 0);
    }

    getCustomerDescription(customer) {
        const addressParts = [
            customer.BillingStreet,
            customer.BillingCity,
            customer.BillingState,
            customer.BillingPostalCode,
            customer.BillingCountry
        ].filter(part => part);

        const address = addressParts.length > 0 ? addressParts.join(', ') : 'Address not available';
        
        // Add Contract Periods to description if available
        let description = `Address: ${address}`;
        if (customer.Contract_Periods__c) {
            description += `<br/>Contract Periods: ${customer.Contract_Periods__c}`;
        }
        if (customer.Email__c) {
            description += `<br/>Email: ${customer.Email__c}`;
        }
        
        return description;
    }

    // ... other computed properties and methods remain the same
    get hasMarkers() {
        return this.mapMarkers && this.mapMarkers.length > 0;
    }

    get hasCustomers() {
        return this.allCustomers && this.allCustomers.length > 0;
    }

    get hasFilteredMarkers() {
        return this.filteredMapMarkers && this.filteredMapMarkers.length > 0;
    }

    get hasFilteredCustomers() {
        return this.filteredCustomers && this.filteredCustomers.length > 0;
    }

    handleRowAction(event) {
        try {
            const action = event.detail.action;
            const row = event.detail.row;
            
            switch (action.name) {
                case 'view_customer':
                    console.log('Customer button clicked:', row.Id);
                    this.onCustomerSelected(row.Id);
                    break;
                default:
                    console.warn('Unknown action:', action.name);
                    break;
            }
        } catch (error) {
            console.error('Error in handleRowAction:', error);
        }
    }

    onCustomerSelected(selectedId) {
        this.selectedMarkerValue = selectedId;
        
        const selectedCustomer = this.allCustomers.find(customer => customer.Id === selectedId);
        if (selectedCustomer && selectedCustomer.BillingPostalCode) {
            this.zoomToMarker(selectedCustomer.BillingPostalCode);
        }
        
        this.handleMarkerSelect({
            "isTrusted": false,
            "composed": true, 
            target: {
                "$$ShadowedNodeKey$$": 256,
                "$$HostElementKey$$": 55, 
                selectedMarkerValue: selectedId
            }
        });
    }

    zoomToMarker(postalCode) {
        this.zoomLevel = 15;
        this.center = {
            location: { PostalCode: postalCode }
        };
        console.log('Zooming to marker with postal code:', postalCode);
    }

    handleMarkerSelect(event) {
        try {
            console.log('Map marker selected:', JSON.stringify(event.target.selectedMarkerValue));
            if (event.target && event.target.selectedMarkerValue) {
                this.selectedMarkerValue = event.target.selectedMarkerValue;
                console.log('Selected customer from map:', this.selectedMarkerValue);
                
                const selectedCustomer = this.allCustomers.find(customer => customer.Id === this.selectedMarkerValue);
                if (selectedCustomer && selectedCustomer.BillingPostalCode) {
                    this.zoomToMarker(selectedCustomer.BillingPostalCode);
                }
            }
        } catch (error) {
            console.error('Error in handleMarkerSelect:', error);
        }
    }
}