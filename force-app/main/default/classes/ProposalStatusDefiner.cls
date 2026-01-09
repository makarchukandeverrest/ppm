public with sharing class ProposalStatusDefiner {

    // Not allow change Opportunity status backwards
    public static void handleStatusChange(List<Opportunity> newOppList, Map<Id, Opportunity> oldOppMap) {
        for (Opportunity o : newOppList) {
            if(o.StageName == 'Pending' && oldOppMap.get(o.Id).StageName != 'Pending') {
                o.StageName = oldOppMap.get(o.Id).StageName;
            }
        }
    }

    // For Opportunity trigger
    public static void updateStatus(List<Opportunity> oppList) {
        for (Opportunity o : oppList) {
            o.StageName = o.Is_Active__c ? 'Pending' : 'Abandoned';
        }
    }

    // For Invoice trigger
    public static void updateStatus(List<Invoice__c> invoiceList) {
        Set<Id> proposalIds = new Set<Id>();
        for (Invoice__c i : invoiceList) {
            if (i.Proposal__c != null) {
                proposalIds.add(i.Proposal__c);
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
                p.StageName = 'Invoiced - WO Completed';
        }

        if (!proposalsToUpdate.isEmpty()) {
            update proposalsToUpdate;
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
                p.StageName = 'Approved - WO Issued';
        }
        if (!proposalsToUpdate.isEmpty()) {
            update proposalsToUpdate;
        }
    }
}