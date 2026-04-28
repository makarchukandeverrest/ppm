public without sharing class QuickBookWorkOrderTechnicianHandler {

    private static final String NAME_DELIMITER = ', ';
    private static final Integer TECHNICIAN_MAX_LENGTH = Schema.SObjectType.WorkOrder.fields.Technician__c.getLength();


    public static void handleQuickBookWorkOrderTechnician(List<Quick_Book_Work_Order_Line_Item__c> lineItems) {
        syncTechniciansForWorkOrders(collectWorkOrderIds(lineItems));
    }

    public static void syncTechniciansForWorkOrders(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return;
        }
        workOrderIds.remove(null);

        Map<Id, Set<Id>> workOrderToMemberIds = queryDistinctMemberIdsByWorkOrder(workOrderIds);
        Set<Id> allMemberIds = flattenMemberIds(workOrderToMemberIds);
        Map<Id, Service_Team_Member__c> membersById = allMemberIds.isEmpty()
            ? new Map<Id, Service_Team_Member__c>()
            : queryServiceTeamMembersById(allMemberIds);

        Map<Id, String> workOrderIdToTechnicianValue = buildTechnicianFieldByWorkOrder(
            workOrderIds,
            workOrderToMemberIds,
            membersById
        );

        List<WorkOrder> triggeredWO = [SELECT Id, Technician__c FROM WorkOrder WHERE Id IN :workOrderIds];

        List<WorkOrder> toUpdate = new List<WorkOrder>();
        for (WorkOrder wo : triggeredWO) {
            String nextValue = workOrderIdToTechnicianValue.get(wo.Id);
            if (!technicianFieldChanged(wo.Technician__c, nextValue)) {
                continue;
            }
            wo.Technician__c = nextValue;
            toUpdate.add(wo);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static Set<Id> collectWorkOrderIds(List<Quick_Book_Work_Order_Line_Item__c> lineItems) {
        Set<Id> workOrderIds = new Set<Id>();
        if (lineItems == null) {
            return workOrderIds;
        }
        for (Quick_Book_Work_Order_Line_Item__c row : lineItems) {
            if (row.Work_Order__c != null) {
                workOrderIds.add(row.Work_Order__c);
            }
        }
        return workOrderIds;
    }

    private static Map<Id, Set<Id>> queryDistinctMemberIdsByWorkOrder(Set<Id> workOrderIds) {
        List<WorkOrder> triggered_WO_Items = [SELECT Work_Order__c, Service_Team_Member__c
            FROM Quick_Book_Work_Order_Line_Item__c
            WHERE Work_Order__c IN :workOrderIds AND Service_Team_Member__c != NULL
        ];
        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();
        for (Quick_Book_Work_Order_Line_Item__c row : triggered_WO_Items) {
            if (!result.containsKey(row.Work_Order__c)) {
                result.put(row.Work_Order__c, new Set<Id>());
            }
            result.get(row.Work_Order__c).add(row.Service_Team_Member__c);
        }
        return result;
    }

    private static Set<Id> flattenMemberIds(Map<Id, Set<Id>> workOrderToMemberIds) {
        Set<Id> all = new Set<Id>();
        for (Set<Id> ids : workOrderToMemberIds.values()) {
            all.addAll(ids);
        }
        return all;
    }

    private static Map<Id, Service_Team_Member__c> queryServiceTeamMembersById(Set<Id> memberIds) {
        return new Map<Id, Service_Team_Member__c>([
            SELECT Id, Name FROM Service_Team_Member__c WHERE Id IN :memberIds
        ]);
    }

    private static Map<Id, String> buildTechnicianFieldByWorkOrder(
        Set<Id> workOrderIds,
        Map<Id, Set<Id>> workOrderToMemberIds,
        Map<Id, Service_Team_Member__c> membersById
    ) {
        Map<Id, String> technicianByWorkOrder = new Map<Id, String>();
        for (Id woId : workOrderIds) {
            Set<Id> memberIdsForWo = workOrderToMemberIds.get(woId);
            if (memberIdsForWo == null || memberIdsForWo.isEmpty()) {
                technicianByWorkOrder.put(woId, null);
                continue;
            }
            List<String> names = new List<String>();
            for (Id memberId : memberIdsForWo) {
                Service_Team_Member__c stm = membersById.get(memberId);
                if (stm != null && String.isNotBlank(stm.Name)) {
                    names.add(stm.Name.trim());
                }
            }
            names.sort();
            String merged = names.isEmpty() ? null : String.join(names, NAME_DELIMITER);
            if (merged != null && merged.length() > TECHNICIAN_MAX_LENGTH) {
                merged = merged.substring(0, TECHNICIAN_MAX_LENGTH);
            }
            technicianByWorkOrder.put(woId, merged);
        }
        return technicianByWorkOrder;
    }

    private static Boolean technicianFieldChanged(String current, String next) {
        String c = current == null ? '' : current.trim();
        String n = next == null ? '' : next.trim();
        return c != n;
    }
}
