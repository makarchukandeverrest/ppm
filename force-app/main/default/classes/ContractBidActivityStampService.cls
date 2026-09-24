public with sharing class ContractBidActivityStampService {
    public static void stampStageChanges(List<Contract_Bid__c> bids, Map<Id, Contract_Bid__c> oldMap) {
        Datetime now = System.now();
        for (Contract_Bid__c bid : bids) {
            bid.Previous_Stage__c = oldMap.get(bid.Id).Stage__c;
            bid.Last_Stage_Change__c = now;
        }
    }
}
