public without sharing class ContractBidActivityStampService {
    private static final Set<String> CLOSED_STAGES = loadClosedStages();
    private static final String EMAIL_STATUS_DRAFT = '5';
    private static final String TASK_SUBTYPE_CALL = 'Call';
    private static final String TASK_SUBTYPE_EMAIL = 'Email';
    public static final Set<String> POST_TYPES = new Set<String>{ 'TextPost', 'ContentPost', 'LinkPost' };

    public static void stampStageChanges(List<Contract_Bid__c> bids, Map<Id, Contract_Bid__c> oldMap) {
        Datetime now = System.now();
        for (Contract_Bid__c bid : bids) {
            bid.Previous_Stage__c = oldMap.get(bid.Id).Stage__c;
            bid.Last_Stage_Change__c = now;
        }
    }

    public static void recalculateActivityStats(Set<Id> activityParentIds) {
        List<Contract_Bid__c> bids = findAffectedBids(activityParentIds);
        if (bids.isEmpty()) {
            return;
        }
        Set<Id> sourceIds = collectSourceIds(bids);
        Map<Id, ActivityStats> statsBySourceId = new Map<Id, ActivityStats>();

        for (AggregateResult ar : [
            SELECT RelatedToId sourceId, Incoming incoming, MAX(MessageDate) lastDate, COUNT(Id) total
            FROM EmailMessage
            WHERE RelatedToId IN :sourceIds AND Status != :EMAIL_STATUS_DRAFT
            GROUP BY RelatedToId, Incoming
        ]) {
            statsFor(statsBySourceId, (Id) ar.get('sourceId')).addEmails(
                (Boolean) ar.get('incoming'),
                (Datetime) ar.get('lastDate'),
                (Integer) ar.get('total')
            );
        }

        for (AggregateResult ar : [
            SELECT WhatId sourceId, TaskSubtype subtype, MAX(CreatedDate) lastDate, COUNT(Id) total
            FROM Task
            WHERE WhatId IN :sourceIds AND TaskSubtype != :TASK_SUBTYPE_EMAIL
            GROUP BY WhatId, TaskSubtype
        ]) {
            ActivityStats stats = statsFor(statsBySourceId, (Id) ar.get('sourceId'));
            stats.otherActivityCount += (Integer) ar.get('total');
            if (ar.get('subtype') == TASK_SUBTYPE_CALL) {
                stats.latestCall = later(stats.latestCall, (Datetime) ar.get('lastDate'));
            }
        }

        for (AggregateResult ar : [
            SELECT WhatId sourceId, COUNT(Id) total
            FROM Event
            WHERE WhatId IN :sourceIds AND IsChild = false
            GROUP BY WhatId
        ]) {
            statsFor(statsBySourceId, (Id) ar.get('sourceId')).otherActivityCount += (Integer) ar.get('total');
        }

        List<Contract_Bid__c> bidsToUpdate = new List<Contract_Bid__c>();
        for (Contract_Bid__c bid : bids) {
            ActivityStats stats = new ActivityStats();
            stats.addAll(statsBySourceId.get(bid.Id));
            if (countsAccountActivities(bid)) {
                stats.addAll(statsBySourceId.get(bid.Customer__c));
            }
            bidsToUpdate.add(new Contract_Bid__c(
                Id = bid.Id,
                Last_Email_Sent__c = stats.lastSent,
                Last_Email_Received__c = stats.lastReceived,
                Email_Messages_Count__c = stats.emailCount,
                Latest_Call_Log__c = stats.latestCall,
                Total_Activities_Count__c = stats.emailCount + stats.otherActivityCount
            ));
        }
        update bidsToUpdate;
    }

    public static void recalculateLatestPost(Set<Id> feedParentIds) {
        List<Contract_Bid__c> bids = findAffectedBids(feedParentIds);
        if (bids.isEmpty()) {
            return;
        }

        Map<Id, Datetime> latestPostByParentId = new Map<Id, Datetime>();
        for (Contract_Bid__c bid : [
            SELECT Id, (SELECT CreatedDate FROM Feeds WHERE Type IN :POST_TYPES ORDER BY CreatedDate DESC LIMIT 1)
            FROM Contract_Bid__c
            WHERE Id IN :bids
        ]) {
            if (!bid.Feeds.isEmpty()) {
                latestPostByParentId.put(bid.Id, bid.Feeds[0].CreatedDate);
            }
        }

        Set<Id> accountIds = new Set<Id>();
        for (Contract_Bid__c bid : bids) {
            if (countsAccountActivities(bid)) {
                accountIds.add(bid.Customer__c);
            }
        }
        for (Account acc : [
            SELECT Id, (SELECT CreatedDate FROM Feeds WHERE Type IN :POST_TYPES ORDER BY CreatedDate DESC LIMIT 1)
            FROM Account
            WHERE Id IN :accountIds
        ]) {
            if (!acc.Feeds.isEmpty()) {
                latestPostByParentId.put(acc.Id, acc.Feeds[0].CreatedDate);
            }
        }

        List<Contract_Bid__c> bidsToUpdate = new List<Contract_Bid__c>();
        for (Contract_Bid__c bid : bids) {
            Datetime latestPost = latestPostByParentId.get(bid.Id);
            if (countsAccountActivities(bid)) {
                latestPost = later(latestPost, latestPostByParentId.get(bid.Customer__c));
            }
            bidsToUpdate.add(new Contract_Bid__c(Id = bid.Id, Latest_Post__c = latestPost));
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

    private static ActivityStats statsFor(Map<Id, ActivityStats> statsBySourceId, Id sourceId) {
        if (!statsBySourceId.containsKey(sourceId)) {
            statsBySourceId.put(sourceId, new ActivityStats());
        }
        return statsBySourceId.get(sourceId);
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

    private class ActivityStats {
        Datetime lastSent;
        Datetime lastReceived;
        Datetime latestCall;
        Integer emailCount = 0;
        Integer otherActivityCount = 0;

        void addEmails(Boolean incoming, Datetime lastDate, Integer total) {
            if (incoming) {
                lastReceived = later(lastReceived, lastDate);
            } else {
                lastSent = later(lastSent, lastDate);
            }
            emailCount += total;
        }

        void addAll(ActivityStats other) {
            if (other == null) {
                return;
            }
            lastSent = later(lastSent, other.lastSent);
            lastReceived = later(lastReceived, other.lastReceived);
            latestCall = later(latestCall, other.latestCall);
            emailCount += other.emailCount;
            otherActivityCount += other.otherActivityCount;
        }
    }
}
