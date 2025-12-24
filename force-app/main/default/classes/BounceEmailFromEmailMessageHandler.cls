public with sharing class BounceEmailFromEmailMessageHandler {

    public static void handle(List<EmailMessage> bouncedEmails) {
        System.debug('=== BounceEmailFromEmailMessageHandler START ===');

        if (bouncedEmails == null || bouncedEmails.isEmpty()) {
            System.debug('No bounced emails received');
            return;
        }

        // =================================================
        // 1️⃣ Resolve AccountIds via RelatedToId (PRIMARY)
        // =================================================
        Set<Id> accountIds = new Set<Id>();
        Set<Id> relatedIds = new Set<Id>();

        for (EmailMessage em : bouncedEmails) {
            if (em.RelatedToId != null) {
                relatedIds.add(em.RelatedToId);
            }
        }

        System.debug('Collected RelatedToIds: ' + relatedIds);

        // --- Case A: RelatedToId = Account
        for (Account acc : [
            SELECT Id
            FROM Account
            WHERE Id IN :relatedIds
        ]) {
            accountIds.add(acc.Id);
        }

        // --- Case B: RelatedToId = Contract_Bid__c
        for (Contract_Bid__c cb : [
            SELECT Id, Customer__c
            FROM Contract_Bid__c
            WHERE Id IN :relatedIds
        ]) {
            if (cb.Customer__c != null) {
                accountIds.add(cb.Customer__c);
            }
        }

        System.debug('AccountIds resolved via RelatedToId: ' + accountIds);

        // =================================================
        // 2️⃣ Fallback: resolve via Contact.Email (OPTIONAL)
        // =================================================
        if (accountIds.isEmpty()) {
            System.debug('⚠️ No AccountIds via RelatedToId → fallback to Email');

            Set<String> emails = new Set<String>();

            for (EmailMessage em : bouncedEmails) {
                if (String.isNotBlank(em.ToAddress)) {
                    for (String addr : em.ToAddress.split('[;,]')) {
                        emails.add(addr.trim().toLowerCase());
                    }
                }
            }

            System.debug('Collected email addresses: ' + emails);

            if (!emails.isEmpty()) {
                for (Contact c : [
                    SELECT Id, AccountId
                    FROM Contact
                    WHERE Email IN :emails
                ]) {
                    if (c.AccountId != null) {
                        accountIds.add(c.AccountId);
                    }
                }
            }
        }

        System.debug('FINAL AccountIds: ' + accountIds);

        if (accountIds.isEmpty()) {
            System.debug('❌ No AccountIds resolved → stopping processing');
            return;
        }

        // =================================================
        // 3️⃣ Update Contract Bids
        // =================================================
        updateContractBids(accountIds);

        // =================================================
        // 4️⃣ Notify Regional Managers
        // =================================================
        notifyRegionalManagers(accountIds);

        System.debug('=== BounceEmailFromEmailMessageHandler END ===');
    }

    // -------------------------------------------------
    // Update Contract Bid Stage
    // -------------------------------------------------
    private static void updateContractBids(Set<Id> accountIds) {
        System.debug('--- updateContractBids START ---');

        List<Contract_Bid__c> bids = [
            SELECT Id, Stage__c, Customer__c
            FROM Contract_Bid__c
            WHERE Customer__c IN :accountIds
            AND Stage__c != 'Need Contact Verification'
        ];

        System.debug('ContractBids found: ' + bids.size());

        for (Contract_Bid__c cb : bids) {
            cb.Stage__c = 'Need Contact Verification';
        }

        if (!bids.isEmpty()) {
            update bids;
            System.debug('ContractBids updated successfully');
        }

        System.debug('--- updateContractBids END ---');
    }

    // -------------------------------------------------
    // Notify Regional Managers
    // -------------------------------------------------
    private static void notifyRegionalManagers(Set<Id> accountIds) {
        System.debug('--- notifyRegionalManagers START ---');

        List<CustomNotificationType> types = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = 'Bounced_Email'
            LIMIT 1
        ];

        if (types.isEmpty()) {
            System.debug('❌ CustomNotificationType Bounced_Email not found');
            return;
        }

        CustomNotificationType notificationType = types[0];

        List<Account> accounts = [
            SELECT Id, Name, Regional_Manager__c
            FROM Account
            WHERE Id IN :accountIds
            AND Regional_Manager__c != null
        ];

        System.debug('Accounts with RM: ' + accounts.size());

        for (Account acc : accounts) {
            Messaging.CustomNotification notif =
                new Messaging.CustomNotification();

            notif.setTitle('Email Bounced');
            notif.setBody(
                'Contract email bounced for account: ' + acc.Name
            );
            notif.setNotificationTypeId(notificationType.Id);
            notif.setTargetId(acc.Id);

            try {
                notif.send(new Set<String>{ acc.Regional_Manager__c });
            } catch (Exception e) {
                System.debug(
                    'ERROR sending notification: ' + e.getMessage()
                );
            }
        }

        System.debug('--- notifyRegionalManagers END ---');
    }
}