public with sharing class InvoiceQuickBooksProposalLinker {
    private List<Invoice__c> newList;

    public InvoiceQuickBooksProposalLinker(List<Invoice__c> newList) {
        this.newList = newList;
        linkInvoices();
    }

    private void linkInvoices() {
        try {
            Set<String> proposalQuickBooksIds = new Set<String>();
            Set<String> workOrderQuickBooksIds = new Set<String>();
            Set<String> proposalReferenceNumbers = new Set<String>();
            Set<String> accountNameFragments = new Set<String>();
            Set<String> customerQuickBooksIds = new Set<String>();

            Map<String, Id> quickBooksIdToOpportunityId = new Map<String, Id>();
            Map<String, Id> referenceNumberToOpportunityId = new Map<String, Id>();
            Map<String, Id> quickBooksIdToWorkOrderId = new Map<String, Id>();
            Map<String, Id> quickBooksIdToAccountId = new Map<String, Id>();

            Map<String, List<Account>> potentialAccountsByFragment = new Map<String, List<Account>>();

            for (Invoice__c invoice : newList) {
                if (String.isNotBlank(invoice.Name)) {
                    String accountName = extractAccountName(invoice.Name);
                    if (String.isNotBlank(accountName)) {
                        accountNameFragments.add(accountName.trim());
                    }
                }

                if (String.isNotBlank(invoice.Quickbooks_LinkedTxn_JSON__c) &&
                    (String.isBlank(invoice.Proposal_QuickBooks_Id__c) || String.isBlank(invoice.WorkOrder_QuickBooks_Id__c))) {

                    for (Map<String, Object> txn : parseLinkedTxn(invoice.Quickbooks_LinkedTxn_JSON__c)) {
                        String txnType = getStringIgnoreCase(txn, 'TxnType');
                        String txnId = getStringIgnoreCase(txn, 'TxnID');
                        if (String.isBlank(txnId)) {
                            txnId = getStringIgnoreCase(txn, 'TxnId');
                        }

                        if (String.isBlank(txnType) || String.isBlank(txnId)) {
                            continue;
                        }

                        if (String.isBlank(invoice.Proposal_QuickBooks_Id__c) && txnType == 'Estimate') {
                            invoice.Proposal_QuickBooks_Id__c = txnId;
                        } else if (String.isBlank(invoice.WorkOrder_QuickBooks_Id__c) && txnType == 'SalesOrder') {
                            invoice.WorkOrder_QuickBooks_Id__c = txnId;
                        }

                        if (String.isNotBlank(invoice.Proposal_QuickBooks_Id__c) &&
                            String.isNotBlank(invoice.WorkOrder_QuickBooks_Id__c)) {
                            break;
                        }
                    }
                }

                if (String.isNotBlank(invoice.Proposal_QuickBooks_Id__c)) {
                    proposalQuickBooksIds.add(invoice.Proposal_QuickBooks_Id__c);
                }

                if (String.isNotBlank(invoice.WorkOrder_QuickBooks_Id__c)) {
                    workOrderQuickBooksIds.add(invoice.WorkOrder_QuickBooks_Id__c);
                }

                if (String.isNotBlank(invoice.Memo__c)) {
                    String referenceNumber = extractReferenceNumber(invoice.Memo__c);
                    if (String.isNotBlank(referenceNumber)) {
                        proposalReferenceNumbers.add(referenceNumber);
                    }
                }

                if (invoice.Customer__c == null && String.isNotBlank(invoice.Customer_Quickbooks_Id__c)) {
                    String rawCustomerQb = invoice.Customer_Quickbooks_Id__c.trim();
                    Integer colonIdx = rawCustomerQb.indexOf(':');
                    String qbId = colonIdx >= 0 ? rawCustomerQb.substring(colonIdx + 1).trim() : rawCustomerQb;
                    if (String.isNotBlank(qbId)) {
                        customerQuickBooksIds.add(qbId);
                    }
                }
            }

            if (!accountNameFragments.isEmpty()) {
                List<String> conditions = new List<String>();

                for (String fragment : accountNameFragments) {
                    String safeFragment = String.escapeSingleQuotes(fragment.trim());
                    if (String.isNotBlank(safeFragment)) {
                        conditions.add('Name LIKE \'%' + safeFragment + '%\'');
                    }
                }

                if (!conditions.isEmpty()) {
                    String query = 'SELECT Id, Name FROM Account WHERE ' +
                                   String.join(conditions, ' OR ') +
                                   ' LIMIT 5000';

                    List<Account> potentialAccounts = Database.query(query);

                    for (Account acc : potentialAccounts) {
                        String accNameLower = acc.Name != null ? acc.Name.toLowerCase() : '';
                        for (String fragment : accountNameFragments) {
                            String fragmentLower = fragment.toLowerCase();
                            if (accNameLower.contains(fragmentLower)) {
                                if (!potentialAccountsByFragment.containsKey(fragment)) {
                                    potentialAccountsByFragment.put(fragment, new List<Account>());
                                }
                                potentialAccountsByFragment.get(fragment).add(acc);
                                break;
                            }
                        }
                    }
                }
            }

            if (!proposalQuickBooksIds.isEmpty()) {
                for (Opportunity opp : [
                    SELECT Id, QuickBooks_Id__c, Reference_Number__c
                    FROM Opportunity
                    WHERE QuickBooks_Id__c IN :proposalQuickBooksIds
                    LIMIT 10000
                ]) {
                    if (String.isNotBlank(opp.QuickBooks_Id__c)) {
                        quickBooksIdToOpportunityId.put(opp.QuickBooks_Id__c, opp.Id);
                    }
                    if (String.isNotBlank(opp.Reference_Number__c)) {
                        referenceNumberToOpportunityId.put(opp.Reference_Number__c, opp.Id);
                    }
                }
            }

            if (!proposalReferenceNumbers.isEmpty()) {
                for (Opportunity opp : [
                    SELECT Id, Reference_Number__c
                    FROM Opportunity
                    WHERE Reference_Number__c IN :proposalReferenceNumbers
                    LIMIT 10000
                ]) {
                    if (String.isNotBlank(opp.Reference_Number__c)) {
                        referenceNumberToOpportunityId.put(opp.Reference_Number__c, opp.Id);
                    }
                }
            }

            if (!customerQuickBooksIds.isEmpty()) {
                for (Account a : [
                    SELECT Id, QuickBooks_Id__c
                    FROM Account
                    WHERE QuickBooks_Id__c IN :customerQuickBooksIds
                    LIMIT 10000
                ]) {
                    if (String.isNotBlank(a.QuickBooks_Id__c)) {
                        quickBooksIdToAccountId.put(a.QuickBooks_Id__c, a.Id);
                    }
                }
            }

            if (!workOrderQuickBooksIds.isEmpty()) {
                for (WorkOrder wo : [
                    SELECT Id, AccountId, Quick_Books_Id__c
                    FROM WorkOrder
                    WHERE Quick_Books_Id__c IN :workOrderQuickBooksIds
                          AND AccountId != null
                    LIMIT 10000
                ]) {
                    if (String.isNotBlank(wo.Quick_Books_Id__c)) {
                        quickBooksIdToWorkOrderId.put(wo.Quick_Books_Id__c, wo.Id);
                    }
                }
            }

            for (Invoice__c invoice : newList) {

                if (invoice.Work_Order__c == null &&
                    String.isNotBlank(invoice.WorkOrder_QuickBooks_Id__c) &&
                    quickBooksIdToWorkOrderId.containsKey(invoice.WorkOrder_QuickBooks_Id__c)) {

                    invoice.Work_Order__c = quickBooksIdToWorkOrderId.get(invoice.WorkOrder_QuickBooks_Id__c);
                }

                if (invoice.Customer__c == null && String.isNotBlank(invoice.Customer_Quickbooks_Id__c)) {
                    String rawCustomerQb = invoice.Customer_Quickbooks_Id__c.trim();
                    Integer colonIdx = rawCustomerQb.indexOf(':');
                    String qbId = colonIdx >= 0 ? rawCustomerQb.substring(colonIdx + 1).trim() : rawCustomerQb;
                    if (String.isNotBlank(qbId) && quickBooksIdToAccountId.containsKey(qbId)) {
                        invoice.Customer__c = quickBooksIdToAccountId.get(qbId);
                    }
                }

                if (invoice.Proposal__c == null &&
                    String.isNotBlank(invoice.Proposal_QuickBooks_Id__c) &&
                    quickBooksIdToOpportunityId.containsKey(invoice.Proposal_QuickBooks_Id__c)) {

                    invoice.Proposal__c = quickBooksIdToOpportunityId.get(invoice.Proposal_QuickBooks_Id__c);

                } else if (invoice.Proposal__c == null && String.isNotBlank(invoice.Memo__c)) {
                    String referenceNumber = extractReferenceNumber(invoice.Memo__c);
                    if (String.isNotBlank(referenceNumber) &&
                        referenceNumberToOpportunityId.containsKey(referenceNumber)) {

                        invoice.Proposal__c = referenceNumberToOpportunityId.get(referenceNumber);
                    }
                }

                if (invoice.Customer__c == null && String.isNotBlank(invoice.Name)) {
                    String accountName = extractAccountName(invoice.Name);
                    if (String.isNotBlank(accountName)) {
                        List<Account> matches = potentialAccountsByFragment.get(accountName);
                
                        if (matches != null && !matches.isEmpty()) {
                            String target = accountName.toLowerCase();
                            Account exactMatch;
                            
                            for (Account acc : matches) {
                                if (acc.Name != null && acc.Name.toLowerCase() == target) {
                                    exactMatch = acc;
                                    break;
                                }
                            }
                
                            if (exactMatch != null) {
                                invoice.Customer__c = exactMatch.Id;
                            } else {
                                if (matches.size() == 1) {
                                    invoice.Customer__c = matches[0].Id;
                                }
                            }
                        }
                    }
                }
            }

        } catch (Exception e) {
            System.debug(
                'Error in InvoiceQuickBooksProposalLinker: ' +
                e.getMessage() +
                ' StackTrace: ' + e.getStackTraceString()
            );
        }
    }

    private static List<Map<String, Object>> parseLinkedTxn(String rawJson) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (String.isBlank(rawJson)) return out;

        Object root;
        try {
            root = JSON.deserializeUntyped(rawJson);
        } catch (Exception e) {
            return out;
        }

        List<Object> items;
        if (root instanceof List<Object>) {
            items = (List<Object>) root;
        } else if (root instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) root;
            Object linked = m.get('LinkedTxn');
            if (linked instanceof List<Object>) {
                items = (List<Object>) linked;
            } else {
                items = new List<Object>();
            }
        } else {
            items = new List<Object>();
        }

        for (Object obj : items) {
            if (obj instanceof Map<String, Object>) {
                out.add((Map<String, Object>) obj);
            }
        }

        return out;
    }

    private static String getStringIgnoreCase(Map<String, Object> m, String key) {
        if (m == null || String.isBlank(key)) return null;
        if (m.containsKey(key)) return (m.get(key) == null) ? null : String.valueOf(m.get(key));

        String keyLower = key.toLowerCase();
        for (String k : m.keySet()) {
            if (k != null && k.toLowerCase() == keyLower) {
                return (m.get(k) == null) ? null : String.valueOf(m.get(k));
            }
        }
        return null;
    }

    private String extractReferenceNumber(String memo) {
        if (String.isBlank(memo)) return null;

        try {
            Pattern pattern = Pattern.compile('(?:Estimate)?\\s*(\\d+)(?::|\\s|$)');
            Matcher matcher = pattern.matcher(memo);

            if (matcher.find()) {
                return matcher.group(1);
            }
        } catch (Exception e) {
            System.debug('Error extracting reference number from memo: ' + memo + ' - ' + e.getMessage());
        }

        return null;
    }

    private String extractAccountName(String invoiceName) {
        if (String.isBlank(invoiceName)) return null;

        try {
            if (invoiceName.contains(':')) {
                return invoiceName.split(':')[0].trim();
            }
        } catch (Exception e) {
            System.debug('Error extracting account name from: ' + invoiceName + ' - ' + e.getMessage());
        }

        return null;
    }
}