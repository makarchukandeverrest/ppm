public with sharing class ContractBidLabelsFiller {
    private static final List<String> DEFAULT_LABELS = new List<String>{
        'Assumptive Bid',
        'Contract Created'
    };

    public static void fillLabels(List<Contract_Bid__c> bids) {
        for (Contract_Bid__c bid : bids) {
            Set<String> labels = new Set<String>();
            if (String.isNotBlank(bid.Label__c)) {
                labels.addAll(bid.Label__c.split(';'));
            }
            labels.addAll(DEFAULT_LABELS);
            bid.Label__c = String.join(new List<String>(labels), ';');
        }
    }
}
