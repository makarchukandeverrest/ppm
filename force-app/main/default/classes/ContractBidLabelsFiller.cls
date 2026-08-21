public with sharing class ContractBidLabelsFiller {
    private static final String NEW_RECORD_CREATED = 'New record created';
    private static final List<String> DEFAULT_LABELS = new List<String>{
        'Assumptive Lead',
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

    public static void replacePreviousYearLabels(List<Contract_Bid__c> newBids) {
        Set<Id> customerIds = new Set<Id>();
        for (Contract_Bid__c bid : newBids) {
            if (bid.Customer__c != null) {
                customerIds.add(bid.Customer__c);
            }
        }
        if (customerIds.isEmpty()) {
            return;
        }

        List<Contract_Bid__c> oldBids = [
            SELECT Id, Name, Customer__c, Contract_Year__c, Label__c
            FROM Contract_Bid__c
            WHERE Customer__c IN :customerIds
              AND Id NOT IN :newBids
        ];

        List<Contract_Bid__c> bidsToUpdate = new List<Contract_Bid__c>();
        for (Contract_Bid__c newBid : newBids) {
            String prevYear = previousYear(yearOf(newBid));
            if (prevYear == null) {
                continue;
            }
            for (Contract_Bid__c oldBid : oldBids) {
                if (oldBid.Customer__c == newBid.Customer__c && yearOf(oldBid) == prevYear) {
                    oldBid.Label__c = NEW_RECORD_CREATED;
                    bidsToUpdate.add(oldBid);
                }
            }
        }
        if (!bidsToUpdate.isEmpty()) {
            update bidsToUpdate;
        }
    }

    private static String yearOf(Contract_Bid__c bid) {
        if (String.isNotBlank(bid.Name)) {
            Matcher matcher = Pattern.compile('(\\d{4})\\s*-\\s*(\\d{4})$').matcher(bid.Name.trim());
            if (matcher.find()) {
                return matcher.group(1) + '-' + matcher.group(2);
            }
        }
        return bid.Contract_Year__c;
    }

    private static String previousYear(String year) {
        if (String.isBlank(year) || year.length() < 4 || !year.substring(0, 4).isNumeric()) {
            return null;
        }
        Integer startYear = Integer.valueOf(year.substring(0, 4));
        return (startYear - 1) + '-' + startYear;
    }
}
