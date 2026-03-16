public inherited sharing class CustomerRegionalManagerService {
    public static void assignOwnerByCustomer(List<WorkOrder> newWorkOrders) {
        for(WorkOrder wo : newWorkOrders) {
            if(wo.AccountId != null && wo.Account.Regional_Manager__c != null) {
                wo.OwnerId = wo.Account.Regional_Manager__c;
            }
        }
        update newWorkOrders;
    }

    public static void assignOwnerByCustomer(List<Invoice__c> newInvoices) {
        for(Invoice__c i : newInvoices) {
            if(i.Customer__c != null && i.Customer__r.Regional_Manager__c != null) {
                i.OwnerId = i.Customer__r.Regional_Manager__c;
            }
        }
        update newInvoices;
    }

    public static void assignOwnerByCustomer(List<Account> newAccounts) {
        List<WorkOrder> workOrdersToUpdate = new List<WorkOrder>();
        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
        for(Account a : newAccounts) {
            if(a.Regional_Manager__c != null) {
                workOrdersToUpdate.addAll([SELECT Id, OwnerId,AccountId,Account.Regional_Manager__c FROM WorkOrder WHERE AccountId = :a.Id]);
                invoicesToUpdate.addAll([SELECT Id, OwnerId,Customer__c,Customer__r.Regional_Manager__c FROM Invoice__c WHERE Customer__c = :a.Id]);
            }
        }
        for(WorkOrder wo : workOrdersToUpdate) {
            wo.OwnerId = wo.Account.Regional_Manager__c;
        }
        for(Invoice__c i : invoicesToUpdate) {
            i.OwnerId = i.Customer__r.Regional_Manager__c;
        }
        if(!workOrdersToUpdate.isEmpty()) {
            update workOrdersToUpdate;
        }
        if(!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
        // for(Account a : newAccounts) {
        //     if(a.Regional_Manager__c != null) {
        //         a.OwnerId = a.Regional_Manager__c;
        //     }
        // }
        // update newAccounts;
        // TODO confirm if we need to update the Account owner from Client
    }
}