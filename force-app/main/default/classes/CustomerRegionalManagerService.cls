public inherited sharing class CustomerRegionalManagerService {
    public static void assignOwnerByCustomer(List<WorkOrder> newWorkOrders) {
        Set<Id> accountIds = new Set<Id>();
        for (WorkOrder wo : newWorkOrders) {
            if (wo.AccountId != null) {
                accountIds.add(wo.AccountId);
            }
        }

        if (accountIds.isEmpty()) {
            return;
        }

        Map<Id, Account> accById = new Map<Id, Account>(
            [SELECT Id, Regional_Manager__c
             FROM Account
             WHERE Id IN :accountIds]
        );

        for (WorkOrder wo : newWorkOrders) {
            Account acc = accById.get(wo.AccountId);
            if (acc != null && acc.Regional_Manager__c != null) {
                wo.OwnerId = acc.Regional_Manager__c;
            }
        }
    }

    public static void assignOwnerByCustomerAfter(List<Invoice__c> triggerNew) {
        Set<Id> customerIds = new Set<Id>();
        for (Invoice__c i : triggerNew) {
            if (i.Customer__c != null) {
                customerIds.add(i.Customer__c);
            }
        }

        if (customerIds.isEmpty()) {
            return;
        }

        Map<Id, Account> customersById = new Map<Id, Account>([
            SELECT Id, Regional_Manager__c
            FROM Account
            WHERE Id IN :customerIds
        ]);

        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();

        for (Invoice__c i : triggerNew) {
            Account cust = customersById.get(i.Customer__c);
            if (cust != null && cust.Regional_Manager__c != null) {
                Invoice__c invClone = new Invoice__c(
                    Id      = i.Id,
                    OwnerId = cust.Regional_Manager__c
                );
                invoicesToUpdate.add(invClone);
            }
        }

        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
    }

    public static void assignOwnerByCustomer(List<Account> newAccounts) {
        Map<Id, Id> accIdToRegionalMgrId = new Map<Id, Id>();
        for (Account a : newAccounts) {
            if (a.Regional_Manager__c != null) {
                accIdToRegionalMgrId.put(a.Id, a.Regional_Manager__c);
            }
        }
    
        if (accIdToRegionalMgrId.isEmpty()) {
            return;
        }
    
        List<WorkOrder> workOrdersToUpdate = [
            SELECT Id, OwnerId, AccountId
            FROM WorkOrder
            WHERE AccountId IN :accIdToRegionalMgrId.keySet()
        ];
    
        List<Invoice__c> invoicesToUpdate = [
            SELECT Id, OwnerId, Customer__c
            FROM Invoice__c
            WHERE Customer__c IN :accIdToRegionalMgrId.keySet()
        ];
    
        for (WorkOrder wo : workOrdersToUpdate) {
            Id regMgrId = accIdToRegionalMgrId.get(wo.AccountId);
            if (regMgrId != null) {
                wo.OwnerId = regMgrId;
            }
        }
    
        for (Invoice__c inv : invoicesToUpdate) {
            Id regMgrId = accIdToRegionalMgrId.get(inv.Customer__c);
            if (regMgrId != null) {
                inv.OwnerId = regMgrId;
            }
        }
    
        if (!workOrdersToUpdate.isEmpty()) {
            update workOrdersToUpdate;
        }
        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
    }
}