public inherited sharing class CustomerRegionalManagerService {
    public static void assignOwnerByCustomer(List<WorkOrder> newWorkOrders) {
        System.debug(LoggingLevel.ERROR, 'assignOwnerByCustomer WorkOrder, size=' + newWorkOrders.size());

        // Собираем Id аккаунтов
        Set<Id> accountIds = new Set<Id>();
        for (WorkOrder wo : newWorkOrders) {
            if (wo.AccountId != null) {
                accountIds.add(wo.AccountId);
            }
        }
        System.debug(LoggingLevel.ERROR, 'accountIds = ' + accountIds);

        if (accountIds.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'No AccountId on WorkOrders, skip');
            return;
        }

        // Тянем нужное поле с аккаунта
        Map<Id, Account> accById = new Map<Id, Account>(
            [SELECT Id, Regional_Manager__c
             FROM Account
             WHERE Id IN :accountIds]
        );
        System.debug(LoggingLevel.ERROR, 'accById = ' + accById);

        for (WorkOrder wo : newWorkOrders) {
            Account acc = accById.get(wo.AccountId);
            System.debug(LoggingLevel.ERROR,
                'WO Id=' + wo.Id +
                ', AccountId=' + wo.AccountId +
                ', acc=' + acc
            );

            if (acc != null && acc.Regional_Manager__c != null) {
                System.debug(LoggingLevel.ERROR, 'Regional_Manager__c = ' + acc.Regional_Manager__c);
                wo.OwnerId = acc.Regional_Manager__c;
                System.debug(LoggingLevel.ERROR, 'OwnerId set to ' + wo.OwnerId + ' for WO ' + wo.Id);
            } else {
                System.debug(LoggingLevel.ERROR,
                    'Skip WO Id=' + wo.Id +
                    ' – acc is ' + acc +
                    ', Regional_Manager__c is ' + (acc == null ? null : acc.Regional_Manager__c)
                );
            }
        }

        System.debug(LoggingLevel.ERROR, 'assignOwnerByCustomer done');
    }

    public static void assignOwnerByCustomerAfter(List<Invoice__c> triggerNew) {
        // Собираем Customer__c
        Set<Id> customerIds = new Set<Id>();
        for (Invoice__c i : triggerNew) {
            if (i.Customer__c != null) {
                customerIds.add(i.Customer__c);
            }
        }

        if (customerIds.isEmpty()) {
            return;
        }

        // Тянем регионального менеджера
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
        // Собираем аккаунты с Regional_Manager__c
        Map<Id, Id> accIdToRegionalMgrId = new Map<Id, Id>();
        for (Account a : newAccounts) {
            if (a.Regional_Manager__c != null) {
                accIdToRegionalMgrId.put(a.Id, a.Regional_Manager__c);
            }
        }
    
        if (accIdToRegionalMgrId.isEmpty()) {
            return;
        }
    
        // Тянем все WorkOrder разом
        List<WorkOrder> workOrdersToUpdate = [
            SELECT Id, OwnerId, AccountId
            FROM WorkOrder
            WHERE AccountId IN :accIdToRegionalMgrId.keySet()
        ];
    
        // Тянем все Invoice__c разом
        List<Invoice__c> invoicesToUpdate = [
            SELECT Id, OwnerId, Customer__c
            FROM Invoice__c
            WHERE Customer__c IN :accIdToRegionalMgrId.keySet()
        ];
    
        // Обновляем владельцев ворк-ордеров
        for (WorkOrder wo : workOrdersToUpdate) {
            Id regMgrId = accIdToRegionalMgrId.get(wo.AccountId);
            if (regMgrId != null) {
                wo.OwnerId = regMgrId;
            }
        }
    
        // Обновляем владельцев инвойсов
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