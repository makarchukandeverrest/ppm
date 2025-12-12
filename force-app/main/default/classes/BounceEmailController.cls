public with sharing class BounceEmailController {
    public static void handleBouncedContractBidPackage(List<EmailMessage> emails) {
        if (emails == null || emails.isEmpty()) {
            return;
        }

        List<Account> accounts = new List<Account>();
        List<Contact> contacts = new List<Contact>();
        Set<Id> accountsId = new Set<Id>();
        List<String> recipientEmails = new List<String>();

        // Extract recipient emails
        for (EmailMessage e : emails) {
            if (e.ToAddress != null) {
                recipientEmails.add(e.ToAddress);
            }
        }

        // Query Accounts by email
        accounts = [SELECT Id, Name, Email__c FROM Account WHERE Email__c IN :recipientEmails];

        // Build dynamic WHERE clause for Contacts
        String dynamicWhereClause = '';
        for (String email : recipientEmails) {
            if (!String.isEmpty(dynamicWhereClause)) {
                dynamicWhereClause += ' OR ';
            }
            dynamicWhereClause += 'Email__c LIKE \'%' + String.escapeSingleQuotes(email) + '%\'';
        }

        // Query Contacts
        String query = 'SELECT Id, Name, Email FROM Contact WHERE Email IN :recipientEmails';
        if (!String.isEmpty(dynamicWhereClause)) {
            query += ' OR (' + dynamicWhereClause + ')';
        }
        contacts = Database.query(query);

        // Find Accounts related to Contacts
        List<Account> accountsByContacts = new List<Account>();
        if (!contacts.isEmpty()) {
            accountsByContacts = [
                SELECT Id, Name, Primary_Contact__c
                FROM Account
                WHERE Primary_Contact__c IN :contacts
            ];
        }

        // Combine all Accounts
        if (!accountsByContacts.isEmpty()) {
            accounts.addAll(accountsByContacts);
        }

        if (!accounts.isEmpty()) {
            for (Account a : accounts) {
                accountsId.add(a.Id);
            }
            changeContractBidStage(accountsId);
            notifyManagers(emails);
        }
    }

    private static void changeContractBidStage(Set<Id> accountsId) {
        if (accountsId == null || accountsId.isEmpty()) {
            return;
        }

        List<Contract_Bid__c> contractBids = [
            SELECT Id, Name, Stage__c, Customer__c
            FROM Contract_Bid__c
            WHERE
                Customer__c IN :accountsId
                AND (Stage__c = 'Information Verified'
                OR Stage__c = 'Contract Bid Package Sent')
        ];

        if (contractBids.isEmpty()) {
            return;
        }

        // Update contract bids
        for (Contract_Bid__c c : contractBids) {
            c.Stage__c = 'Need Contact Verification';
        }

        try {
            update contractBids;
        } catch (DmlException e) {
            // Log error if needed
        }
    }

    private static void notifyManagers(List<EmailMessage> mailToNotify) {
        if (mailToNotify == null || mailToNotify.isEmpty()) {
            return;
        }

        try {
            // Fetch the Custom Notification Type by API Name
            CustomNotificationType notificationType = [
                SELECT Id, DeveloperName
                FROM CustomNotificationType
                WHERE DeveloperName = 'Bounced_Email'
                LIMIT 1
            ];

            // Send notifications for each email
            for (EmailMessage email : mailToNotify) {
                if (email == null || email.ToIds == null || email.ToIds.isEmpty()) {
                    continue;
                }

                // Send a notification to each recipient instead of only the last one
                for (Id recipientId : email.ToIds) {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setTitle('Email Bounced');
                    notification.setBody('An email has bounced.');
                    notification.setNotificationTypeId(notificationType.Id);
                    notification.setTargetId(recipientId);

                    try {
                        notification.send(new Set<String>{ email.FromId });
                    } catch (Exception ex) {
                        // Handle notification sending error
                    }
                }
            }
        } catch (Exception e) {
            // Handle query or other exceptions
        }
    }
}