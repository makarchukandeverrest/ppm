public with sharing class InvoiceWorkOrderAssigner {
    public static void assignWorkOrder(List<Invoice__c> invoiceList) {
        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
        Set<Id> proposalIds = new Set<Id>();
        Map<Id, WorkOrder> workOrderMap = new Map<Id, WorkOrder>();

        for (Invoice__c i : invoiceList) {
            // Only consider invoices that (1) don't already have a Work Order, and
            // (2) have a QuickBooks WorkOrder Id present. Invoices without a QB Id
            // must be ignored per business rules/tests.
            if (i.Work_Order__c == null && i.WorkOrder_QuickBooks_Id__c != null) {
                proposalIds.add(i.Proposal__c);
                invoicesToUpdate.add(i);
            }
        }
        if (proposalIds.isEmpty()) {
            return;
        }else{
            List<WorkOrder> workOrders = [SELECT Id, Proposal__c FROM WorkOrder WHERE Proposal__c IN :proposalIds];
            for (WorkOrder w : workOrders) {
                workOrderMap.put(w.Proposal__c, w);
            }

            for(Invoice__c i : invoicesToUpdate){
                if(workOrderMap.containsKey(i.Proposal__c)){
                    i.Work_Order__c = workOrderMap.get(i.Proposal__c).Id;
                }
            }

            if(!invoicesToUpdate.isEmpty()){
                update invoicesToUpdate;
            }
        }


    }
}