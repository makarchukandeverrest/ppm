@IsTest
private class ContractBidTriggerHandlerTest {

    private static Contract_Bid__c createBid(String stage) {
        Account acc = new Account(Name = 'Test Account ' + stage);
        insert acc;

        // Note: add any additional required fields for Contract_Bid__c in your org.
        Contract_Bid__c bid = new Contract_Bid__c(
            Name        = 'Test Bid ' + stage,
            Customer__c = acc.Id,
            Stage__c    = stage
        );
        return bid;
    }

    @IsTest
    static void testBeforeInsert_PreservesFieldsOnCreate() {
        Date startDate = Date.today();
        Date endDate = Date.today().addYears(1);
        Date sentDate = Date.today().addDays(-1);
        Date ebdDueDate = Date.today().addDays(10);
        Date dueDate = Date.today().addDays(20);

        Contract_Bid__c bid = createBid('Contact Verified and Updated');
        bid.Bid_Number__c = 'BID-123';
        bid.Version__c = 'A';
        bid.Contract_Start_Date__c = startDate;
        bid.Contract_End_Date__c = endDate;
        bid.Sent_Contract_Date__c = sentDate;
        bid.Lost_Reason__c = 'Price';
        bid.Additional_Comments__c = 'Keep this comment';
        bid.EBD_Due_Date__c = ebdDueDate;
        bid.Due_Date__c = dueDate;

        Test.startTest();
        insert bid;
        Test.stopTest();

        bid = [
            SELECT
                Bid_Number__c,
                Version__c,
                Contract_Start_Date__c,
                Contract_End_Date__c,
                Sent_Contract_Date__c,
                Lost_Reason__c,
                Additional_Comments__c,
                EBD_Due_Date__c,
                Due_Date__c
            FROM Contract_Bid__c
            WHERE Id = :bid.Id
        ];

        System.assertEquals('BID-123', bid.Bid_Number__c);
        System.assertEquals('A', bid.Version__c);
        System.assertEquals(startDate, bid.Contract_Start_Date__c);
        System.assertEquals(endDate, bid.Contract_End_Date__c);
        System.assertEquals(sentDate, bid.Sent_Contract_Date__c);
        System.assertEquals('Price', bid.Lost_Reason__c);
        System.assertEquals('Keep this comment', bid.Additional_Comments__c);
        System.assertEquals(ebdDueDate, bid.EBD_Due_Date__c);
        System.assertEquals(dueDate, bid.Due_Date__c);
    }

    @IsTest
    static void testAfterInsert_ClosedWon() {
        Contract_Bid__c bid = createBid('Closed - WON');

        Test.startTest();
        insert bid;
        Test.stopTest();

        System.assertEquals(
            true,
            getCurrentCustomer(bid.Customer__c),
            'Closed - WON insert should mark Current Customer'
        );
    }

    @IsTest
    static void testAfterInsert_ClosedLost() {
        Contract_Bid__c bid = createBid('Closed - LOST');

        Test.startTest();
        insert bid;
        Test.stopTest();

        System.assertEquals(
            false,
            getCurrentCustomer(bid.Customer__c),
            'Closed - LOST insert should leave Current Customer unchecked'
        );
    }

    @IsTest
    static void testAfterInsert_NotClosedWon() {
        Contract_Bid__c bid = createBid('Contact Verified and Updated');

        Test.startTest();
        insert bid;
        Test.stopTest();

        System.assertEquals(
            false,
            getCurrentCustomer(bid.Customer__c),
            'Non-closed insert should not mark Current Customer'
        );
    }

    @IsTest
    static void testAfterUpdate_StageChangesToClosedWon() {
        Contract_Bid__c bid = createBid('Contact Verified and Updated');
        insert bid;

        bid.Stage__c = 'Closed - WON';

        Test.startTest();
        update bid;
        Test.stopTest();

        System.assertEquals(
            true,
            getCurrentCustomer(bid.Customer__c),
            'Stage change to Closed - WON should mark Current Customer'
        );
    }

    @IsTest
    static void testAfterUpdate_StageChangesToClosedLost() {
        Contract_Bid__c bid = createBid('Contact Verified and Updated');
        insert bid;

        bid.Stage__c = 'Closed - WON';
        update bid;
        System.assertEquals(true, getCurrentCustomer(bid.Customer__c));

        bid.Stage__c = 'Closed - LOST';

        Test.startTest();
        update bid;
        Test.stopTest();

        System.assertEquals(
            false,
            getCurrentCustomer(bid.Customer__c),
            'Stage change to Closed - LOST should uncheck Current Customer'
        );
    }

    @IsTest
    static void testAfterUpdate_StageRemainsClosedWon_NoDoubleCall() {
        Contract_Bid__c bid = createBid('Closed - WON');
        insert bid;

        bid.Name = 'Updated Name';

        Test.startTest();
        update bid;
        Test.stopTest();

        System.assertEquals(
            true,
            getCurrentCustomer(bid.Customer__c),
            'Unchanged Closed - WON should keep Current Customer checked'
        );
    }

    private static Boolean getCurrentCustomer(Id accountId) {
        return [
            SELECT Current_Customer__c
            FROM Account
            WHERE Id = :accountId
        ]
        .Current_Customer__c;
    }
}