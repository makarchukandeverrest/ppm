public without sharing class ContractBidActivityStampService {
    private static final Set<String> CLOSED_STAGES = loadClosedStages();
    private static final String EMAIL_STATUS_DRAFT = '5';
    private static final String TASK_SUBTYPE_CALL = 'Call';

    public static void stampStageChanges(List<Contract_Bid__c> bids, Map<Id, Contract_Bid__c> oldMap) {
        Datetime now = System.now();
        for (Contract_Bid__c bid : bids) {
            bid.Previous_Stage__c = oldMap.get(bid.Id).Stage__c;
            bid.Last_Stage_Change__c = now;
        }
    }

    public static void recalculateEmailStats(Set<Id> emailParentIds) {
        List<Contract_Bid__c> bids = findAffectedBids(emailParentIds);
        if (bids.isEmpty()) {
            return;
        }

        Map<Id, EmailStats> statsBySourceId = new Map<Id, EmailStats>();
        for (AggregateResult ar : [
            SELECT RelatedToId sourceId, Incoming incoming, MAX(MessageDate) lastDate, COUNT(Id) total
            FROM EmailMessage
            WHERE RelatedToId IN :collectSourceIds(bids) AND Status != :EMAIL_STATUS_DRAFT
            GROUP BY RelatedToId, Incoming
        ]) {
            Id sourceId = (Id) ar.get('sourceId');
            if (!statsBySourceId.containsKey(sourceId)) {
                statsBySourceId.put(sourceId, new EmailStats());
            }
            statsBySourceId.get(sourceId).add(
                (Boolean) ar.get('incoming'),
                (Datetime) ar.get('lastDate'),
                (Integer) ar.get('total')
            );
        }

        List<Contract_Bid__c> bidsToUpdate = new List<Contract_Bid__c>();
        for (Contract_Bid__c bid : bids) {
            EmailStats stats = new EmailStats();
            stats.addAll(statsBySourceId.get(bid.Id));
            if (countsAccountActivities(bid)) {
                stats.addAll(statsBySourceId.get(bid.Customer__c));
            }
            bidsToUpdate.add(new Contract_Bid__c(
                Id = bid.Id,
                Last_Email_Sent__c = stats.lastSent,
                Last_Email_Received__c = stats.lastReceived,
                Email_Messages_Count__c = stats.count
            ));
        }
        update bidsToUpdate;
    }

    public static void recalculateLatestCallLog(Set<Id> callParentIds) {
        List<Contract_Bid__c> bids = findAffectedBids(callParentIds);
        if (bids.isEmpty()) {
            return;
        }

        Map<Id, Datetime> latestCallBySourceId = new Map<Id, Datetime>();
        for (AggregateResult ar : [
            SELECT WhatId sourceId, MAX(CreatedDate) lastDate
            FROM Task
            WHERE WhatId IN :collectSourceIds(bids) AND TaskSubtype = :TASK_SUBTYPE_CALL
            GROUP BY WhatId
        ]) {
            latestCallBySourceId.put((Id) ar.get('sourceId'), (Datetime) ar.get('lastDate'));
        }

        List<Contract_Bid__c> bidsToUpdate = new List<Contract_Bid__c>();
        for (Contract_Bid__c bid : bids) {
            Datetime latestCall = latestCallBySourceId.get(bid.Id);
            if (countsAccountActivities(bid)) {
                latestCall = later(latestCall, latestCallBySourceId.get(bid.Customer__c));
            }
            bidsToUpdate.add(new Contract_Bid__c(Id = bid.Id, Latest_Call_Log__c = latestCall));
        }
        update bidsToUpdate;
    }

    private static List<Contract_Bid__c> findAffectedBids(Set<Id> parentIds) {
        if (parentIds.isEmpty()) {
            return new List<Contract_Bid__c>();
        }
        return [
            SELECT Id, Customer__c, Stage__c
            FROM Contract_Bid__c
            WHERE Id IN :parentIds
                OR (Customer__c IN :parentIds AND Stage__c NOT IN :CLOSED_STAGES)
        ];
    }

    private static Set<Id> collectSourceIds(List<Contract_Bid__c> bids) {
        Set<Id> sourceIds = new Set<Id>();
        for (Contract_Bid__c bid : bids) {
            sourceIds.add(bid.Id);
            if (countsAccountActivities(bid)) {
                sourceIds.add(bid.Customer__c);
            }
        }
        return sourceIds;
    }

    private static Set<String> loadClosedStages() {
        Set<String> stages = new Set<String>();
        StageReferenceSettings__mdt settings = StageReferenceSettings__mdt.getInstance('Closed_Stages');
        for (String stage : settings.Stage_Names__c.split(',')) {
            stages.add(stage.trim());
        }
        return stages;
    }

    private static Boolean countsAccountActivities(Contract_Bid__c bid) {
        return bid.Customer__c != null && !CLOSED_STAGES.contains(bid.Stage__c);
    }

    private static Datetime later(Datetime a, Datetime b) {
        if (a == null) {
            return b;
        }
        if (b == null) {
            return a;
        }
        return a > b ? a : b;
    }

    private class EmailStats {
        Datetime lastSent;
        Datetime lastReceived;
        Integer count = 0;

        void add(Boolean incoming, Datetime lastDate, Integer total) {
            if (incoming) {
                lastReceived = later(lastReceived, lastDate);
            } else {
                lastSent = later(lastSent, lastDate);
            }
            count += total;
        }

        void addAll(EmailStats other) {
            if (other == null) {
                return;
            }
            lastSent = later(lastSent, other.lastSent);
            lastReceived = later(lastReceived, other.lastReceived);
            count += other.count;
        }
    }
}
