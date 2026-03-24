@IsTest
public with sharing class OpportunityContactSyncServiceTest {
    @testSetup
    static void setup() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        List<Contact> contacts = new List<Contact>{
            new Contact(LastName = 'Billing Setup', AccountId = acc.Id),
            new Contact(LastName = 'Maintenance Setup', AccountId = acc.Id),
            new Contact(LastName = 'Primary Setup', AccountId = acc.Id),
            new Contact(LastName = 'Secondary Setup', AccountId = acc.Id)
        };
        insert contacts;

        acc.Billing_Contact__c = contacts[0].Id;
        acc.Maintenance_Contact__c = contacts[1].Id;
        acc.Primary_Contact__c = contacts[2].Id;
        acc.Secondary_Contact__c = contacts[3].Id;
        update acc;
    }

    @IsTest
    static void testAssignContacts() {
        Account acc = [
            SELECT Id, Billing_Contact__c, Maintenance_Contact__c, Primary_Contact__c, Secondary_Contact__c
            FROM Account
            WHERE Name = 'Test Account'
            LIMIT 1
        ];

        Opportunity opp = new Opportunity(
            Name = 'Test Account: Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Proposal Created / Ready for review',
            CloseDate = Date.today().addDays(30),
            Account_QuickBooks_Id__c = '9379992'
        );
        insert opp;

        List<Contact> newContacts = new List<Contact>{
            new Contact(LastName = 'Billing Updated', AccountId = acc.Id),
            new Contact(LastName = 'Maintenance Updated', AccountId = acc.Id),
            new Contact(LastName = 'Primary Updated', AccountId = acc.Id),
            new Contact(LastName = 'Secondary Updated', AccountId = acc.Id)
        };
        insert newContacts;

        acc.Billing_Contact__c = newContacts[0].Id;
        acc.Maintenance_Contact__c = newContacts[1].Id;
        acc.Primary_Contact__c = newContacts[2].Id;
        acc.Secondary_Contact__c = newContacts[3].Id;

        update acc;

        Account updatedAcc = [
            SELECT Id, Billing_Contact__c, Maintenance_Contact__c, Primary_Contact__c, Secondary_Contact__c
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];

        Opportunity syncOpp = new Opportunity(
            Name = 'Test Account: Sync Target',
            AccountId = updatedAcc.Id,
            StageName = 'Proposal Created / Ready for review',
            CloseDate = Date.today().addDays(15),
            Account_QuickBooks_Id__c = 'SYNC-TARGET'
        );
        insert syncOpp;

        OpportunityContactSyncService.assignContacts(new List<Account>{ updatedAcc });

        Opportunity updatedOpp = [
            SELECT Id, Customer_Billing_Contact__c, Customer_Maintenance_Contact__c, Customer_Primary_Contact__c, Customer_Secondary_Contact__c
            FROM Opportunity
            WHERE Id = :syncOpp.Id
            LIMIT 1
        ];

        System.assertEquals(newContacts[0].Id, updatedOpp.Customer_Billing_Contact__c);
        System.assertEquals(newContacts[1].Id, updatedOpp.Customer_Maintenance_Contact__c);
        System.assertEquals(newContacts[2].Id, updatedOpp.Customer_Primary_Contact__c);
        System.assertEquals(newContacts[3].Id, updatedOpp.Customer_Secondary_Contact__c);
    }

    @IsTest
    static void testAssignContactsWhenOpportunityAccountChanged() {
        Account firstAcc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

        Account secondAcc = new Account(Name = 'Second Test Account');
        insert secondAcc;

        List<Contact> secondContacts = new List<Contact>{
            new Contact(LastName = 'Second Billing', AccountId = secondAcc.Id),
            new Contact(LastName = 'Second Maintenance', AccountId = secondAcc.Id),
            new Contact(LastName = 'Second Primary', AccountId = secondAcc.Id),
            new Contact(LastName = 'Second Secondary', AccountId = secondAcc.Id)
        };
        insert secondContacts;

        secondAcc.Billing_Contact__c = secondContacts[0].Id;
        secondAcc.Maintenance_Contact__c = secondContacts[1].Id;
        secondAcc.Primary_Contact__c = secondContacts[2].Id;
        secondAcc.Secondary_Contact__c = secondContacts[3].Id;
        update secondAcc;

        Opportunity opp = new Opportunity(
            Name = 'Reassign Account Test',
            AccountId = firstAcc.Id,
            StageName = 'Proposal Created / Ready for review',
            CloseDate = Date.today().addDays(10),
            Account_QuickBooks_Id__c = 'REASSIGN-TEST'
        );
        insert opp;

        opp.AccountId = secondAcc.Id;
        update opp;

        Opportunity updatedOpp = [
            SELECT Customer_Billing_Contact__c, Customer_Maintenance_Contact__c, Customer_Primary_Contact__c, Customer_Secondary_Contact__c
            FROM Opportunity
            WHERE Id = :opp.Id
            LIMIT 1
        ];

        System.assertEquals(secondContacts[0].Id, updatedOpp.Customer_Billing_Contact__c);
        System.assertEquals(secondContacts[1].Id, updatedOpp.Customer_Maintenance_Contact__c);
        System.assertEquals(secondContacts[2].Id, updatedOpp.Customer_Primary_Contact__c);
        System.assertEquals(secondContacts[3].Id, updatedOpp.Customer_Secondary_Contact__c);
    }
}