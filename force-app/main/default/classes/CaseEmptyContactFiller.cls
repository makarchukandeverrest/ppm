public with sharing class CaseEmptyContactFiller {
    public static void fillEmptyContactByCustomer(List<Case> cases) {
        if (cases == null || cases.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();

        for (Case c : cases) {
            if (c.AccountId != null) {
                accountIds.add(c.AccountId);
            }
        }

        if (accountIds.isEmpty()) {
            return;
        }

        Map<Id, Account> accountsById = new Map<Id, Account>([
            SELECT Id, Primary_Contact__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        for (Case c : cases) {
            if (c.ContactId != null || c.AccountId == null) {
                continue;
            }

            if (accountsById.get(c.AccountId).Primary_Contact__c != null) {
                c.ContactId = accountsById.get(c.AccountId).Primary_Contact__c;
            }
        }
    }
}
