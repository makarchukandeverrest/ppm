public without sharing class CustomerRegionalManagerService {

    // Closed stages — these Proposals will only have Owner updated (RM frozen).
    // All other stages are considered "open" and get both RM + Owner updated.
    public static final Set<String> CLOSED_STAGES = new Set<String>{
        'Closed Won',
        'Abandoned'
    };

    // Static flag: when true, preventProposalRMOverride is skipped.
    // Used during Account cascade to avoid the nested Proposal trigger
    // from reverting the RM change we just made.
    private static Boolean bypassPreventOverride = false;

    // ─── Proposal (Opportunity) — before insert ───────────────────────────
    // AC 1: Sets Regional_Manager__c and OwnerId from the linked Customer on create.
    // Also called from beforeUpdate when AccountId changes on an existing Proposal.
    public static void syncProposalRMFromCustomer(List<Opportunity> proposals) {
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : proposals) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }

        Map<Id, Account> accById = new Map<Id, Account>([
            SELECT Id, Regional_Manager__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        for (Opportunity opp : proposals) {
            Account acc = accById.get(opp.AccountId);
            if (acc != null && acc.Regional_Manager__c != null) {
                opp.Regional_Manager__c = acc.Regional_Manager__c;
                opp.OwnerId             = acc.Regional_Manager__c;
            }
        }
    }

    // ─── Proposal (Opportunity) — before update ───────────────────────────
    // AC 4: Prevents manual override of Regional_Manager__c.
    // If the value differs from the Customer's RM, the save is blocked
    // with a clear validation message.
    public static void preventProposalRMOverride(
        List<Opportunity> proposals,
        Map<Id, Opportunity> oldMap
    ) {
        // Skip when called from Account cascade (assignOwnerByCustomer)
        if (bypassPreventOverride) {
            return;
        }

        // Collect proposals where RM was changed manually
        List<Opportunity> changed = new List<Opportunity>();
        for (Opportunity opp : proposals) {
            Opportunity old = oldMap.get(opp.Id);
            if (old != null && opp.Regional_Manager__c != old.Regional_Manager__c) {
                changed.add(opp);
            }
        }
        if (changed.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : changed) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }

        Map<Id, Account> accById = new Map<Id, Account>([
            SELECT Id, Regional_Manager__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        for (Opportunity opp : changed) {
            Account acc = accById.get(opp.AccountId);
            if (acc != null && acc.Regional_Manager__c != null
                    && opp.Regional_Manager__c != acc.Regional_Manager__c) {
                // Force Proposal RM (and Owner) to match the Customer's RM.
                opp.Regional_Manager__c = acc.Regional_Manager__c;
                opp.OwnerId             = acc.Regional_Manager__c;
            }
        }
    }

    // ─── WorkOrder — after insert ─────────────────────────────────────────
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

        Map<Id, Account> accById = new Map<Id, Account>([
            SELECT Id, Regional_Manager__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        List<WorkOrder> workOrdersToUpdate = new List<WorkOrder>();
        for (WorkOrder wo : newWorkOrders) {
            Account acc = accById.get(wo.AccountId);
            if (acc != null && acc.Regional_Manager__c != null) {
                // In before insert, WorkOrder.Id is null; set in-memory instead of DML.
                if (wo.Id == null) {
                    wo.OwnerId = acc.Regional_Manager__c;
                } else {
                    workOrdersToUpdate.add(new WorkOrder(
                        Id      = wo.Id,
                        OwnerId = acc.Regional_Manager__c
                    ));
                }
            }
        }

        if (!workOrdersToUpdate.isEmpty()) {
            update workOrdersToUpdate;
        }
    }

    // ─── Invoice — after insert ───────────────────────────────────────────
    public static void assignOwnerByCustomer(List<Invoice__c> triggerNew) {
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
                invoicesToUpdate.add(new Invoice__c(
                    Id      = i.Id,
                    OwnerId = cust.Regional_Manager__c
                ));
            }
        }

        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
    }

    // ─── Account change cascade ───────────────────────────────────────────
    // AC 2: Open Proposals  → OwnerId + Regional_Manager__c updated to new RM
    // AC 3: Closed Proposals → OwnerId updated only; Regional_Manager__c frozen
    public static void assignOwnerByCustomer(List<Account> newAccounts) {
        System.debug('>>> CRMS.assignOwnerByCustomer(Account) ENTER, count=' + newAccounts.size());

        Map<Id, Id> accIdToRegionalMgrId = new Map<Id, Id>();
        for (Account a : newAccounts) {
            if (a.Regional_Manager__c != null) {
                accIdToRegionalMgrId.put(a.Id, a.Regional_Manager__c);
                System.debug('>>> Account ' + a.Id + ' → new RM = ' + a.Regional_Manager__c);
            }
        }
        if (accIdToRegionalMgrId.isEmpty()) {
            System.debug('>>> No accounts with RM, exiting');
            return;
        }

        // ── WorkOrders ──
        List<WorkOrder> workOrdersToUpdate = [
            SELECT Id, OwnerId, AccountId
            FROM WorkOrder
            WHERE AccountId IN :accIdToRegionalMgrId.keySet()
        ];
        System.debug('>>> WorkOrders found: ' + workOrdersToUpdate.size());

        // ── Invoices ──
        List<Invoice__c> invoicesToUpdate = [
            SELECT Id, OwnerId, Customer__c
            FROM Invoice__c
            WHERE Customer__c IN :accIdToRegionalMgrId.keySet()
        ];
        System.debug('>>> Invoices found: ' + invoicesToUpdate.size());

        // ── Proposals (Opportunities) ──
        List<Opportunity> proposalsToUpdate = [
    SELECT Id, OwnerId, AccountId, Regional_Manager__c, StageName, IsClosed
    FROM Opportunity
    WHERE AccountId IN :accIdToRegionalMgrId.keySet()
];
        System.debug('>>> Proposals found: ' + proposalsToUpdate.size());

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

        for (Opportunity opp : proposalsToUpdate) {
            Id regMgrId = accIdToRegionalMgrId.get(opp.AccountId);
            if (regMgrId != null) {
                opp.OwnerId = regMgrId;
                // Only open Proposals get RM updated; closed Proposals keep RM frozen.
                if (!opp.IsClosed) {
                    opp.Regional_Manager__c = regMgrId;
                }
            }
        }

        if (!workOrdersToUpdate.isEmpty()) {
            update workOrdersToUpdate;
        }
        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
        if (!proposalsToUpdate.isEmpty()) {
            System.debug('>>> Updating ' + proposalsToUpdate.size() + ' proposals, setting bypassPreventOverride=true');
            // bypassPreventOverride ensures the nested Proposal trigger's
            // preventProposalRMOverride does not revert the cascade we just applied
            bypassPreventOverride = true;
            try {
                update proposalsToUpdate;
                System.debug('>>> Proposals updated successfully');
            } finally {
                bypassPreventOverride = false;
            }
        } else {
            System.debug('>>> No proposals to update');
        }
    }
}