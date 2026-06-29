public inherited sharing class ProposalStatusDefiner {

    // Not allow change Opportunity status backwards
    public static void handleStatusChange(List<Opportunity> newOppList, Map<Id, Opportunity> oldOppMap) {
        for (Opportunity o : newOppList) {
            if(o.StageName == 'Proposal Created / Ready for review' && oldOppMap.get(o.Id).StageName != 'Proposal Created / Ready for review') {
                o.StageName = oldOppMap.get(o.Id).StageName;
            }
        }
    }

    // For Opportunity trigger
    public static void updateStatus(List<Opportunity> oppList) {
        for (Opportunity o : oppList) {
            o.StageName = o.Is_Active__c ? 'Proposal Created / Ready for review' : 'Abandoned';
        }
    }

    public static void updateStatus(List<Invoice__c> invoices) {
        if (invoices == null || invoices.isEmpty()) {
            return;
        }
    
        Set<Id> proposalIds  = new Set<Id>();
        Set<Id> workOrderIds = new Set<Id>();
    
        for (Invoice__c inv : invoices) {
            if (inv.Proposal__c != null) {
                proposalIds.add(inv.Proposal__c);
            }
            if (inv.Work_Order__c != null) {
                workOrderIds.add(inv.Work_Order__c);
            }
        }
    
        // Proposals update
        if (!proposalIds.isEmpty()) {
            List<Opportunity> proposalsToUpdate = [
                SELECT Id, StageName
                FROM Opportunity
                WHERE Id IN :proposalIds
            ];
    
            for (Opportunity opp : proposalsToUpdate) {
                opp.StageName = 'Invoiced - WO Completed';
            }
    
            if (!proposalsToUpdate.isEmpty()) {
                update proposalsToUpdate;
            }
        }
    
        // Work Orders Update
        if (!workOrderIds.isEmpty()) {
            List<WorkOrder> workOrdersToUpdate = [
                SELECT Id, Status
                FROM WorkOrder
                WHERE Id IN :workOrderIds
            ];
    
            for (WorkOrder wo : workOrdersToUpdate) {
                wo.Status = 'Completed';
            }
    
            if (!workOrdersToUpdate.isEmpty()) {
                update workOrdersToUpdate;
            }
        }
    }

    // For Work Order trigger
    public static void updateStatus(List<WorkOrder> workOrders) {
        Set<Id> proposalIds = new Set<Id>();
        for (WorkOrder w : workOrders) {
            if (w.Proposal__c != null) {
                proposalIds.add(w.Proposal__c);
            }
        }
        if (proposalIds.isEmpty()) {
            return;
        }

        List<Opportunity> proposalsToUpdate = [
            SELECT Id, Is_Active__c, StageName
            FROM Opportunity
            WHERE Id IN :proposalIds
        ];
        for (Opportunity p : proposalsToUpdate) {
                p.StageName = 'WO Issued';
        }
        if (!proposalsToUpdate.isEmpty()) {
            update proposalsToUpdate;
        }
    }
}