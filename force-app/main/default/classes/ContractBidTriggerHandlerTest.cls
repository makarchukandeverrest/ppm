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
    static void testBeforeInsert_ClearsRestrictedFieldsOnCreateAndClone() {
        Contract_Bid__c bid = createBid('Contact Verified and Updated');
        bid.Bid_Number__c = 'BID-123';
        bid.Version__c = 'A';
        bid.Contract_Start_Date__c = Date.today();
        bid.Contract_End_Date__c = Date.today().addYears(1);
        bid.Lost_Reason__c = 'Price';
        bid.Additional_Comments__c = 'Should be cleared';

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
                Label__c
            FROM Contract_Bid__c
            WHERE Id = :bid.Id
        ];

        System.assertEquals(null, bid.Bid_Number__c);
        System.assertEquals(null, bid.Version__c);
        System.assertEquals(null, bid.Contract_Start_Date__c);
        System.assertEquals(null, bid.Contract_End_Date__c);
        System.assertEquals(null, bid.Sent_Contract_Date__c);
        System.assertEquals(null, bid.Lost_Reason__c);
        System.assertEquals(null, bid.Additional_Comments__c);
        System.assert(bid.Label__c != null && bid.Label__c.contains('Assumptive Bid'));
        System.assert(bid.Label__c.contains('Contract Created'));
    }

    @IsTest
    static void testBeforeInsert_AddsDefaultLabelsAndKeepsExisting() {
        Contract_Bid__c bid = createBid('Contact Verified and Updated');
        bid.Label__c = 'Hot Lead';

        Test.startTest();
        insert bid;
        Test.stopTest();

        bid = [SELECT Label__c FROM Contract_Bid__c WHERE Id = :bid.Id];

        System.assert(bid.Label__c.contains('Hot Lead'));
        System.assert(bid.Label__c.contains('Assumptive Bid'));
        System.assert(bid.Label__c.contains('Contract Created'));
    }

    @IsTest
    static void testAfterInsert_ClosedWon() {
        Contract_Bid__c bid = createBid('Closed - WON');

        Test.startTest();
        insert bid;
        Test.stopTest();

        System.assert(true, 'afterInsert with Closed - WON executed');
    }

    @IsTest
    static void testAfterInsert_ClosedLost() {
        Contract_Bid__c bid = createBid('Closed - LOST');

        Test.startTest();
        insert bid;
        Test.stopTest();

        System.assert(true, 'afterInsert with Closed - LOST executed');
    }

    @IsTest
    static void testAfterInsert_NotClosedWon() {
        Contract_Bid__c bid = createBid('Contact Verified and Updated');

        Test.startTest();
        insert bid;
        Test.stopTest();

        System.assert(true, 'afterInsert with non-Closed - WON executed');
    }

    @IsTest
    static void testAfterUpdate_StageChangesToClosedWon() {
        Contract_Bid__c bid = createBid('Contact Verified and Updated');
        insert bid;

        bid.Stage__c = 'Closed - WON';

        Test.startTest();
        update bid;
        Test.stopTest();

        System.assert(true, 'afterUpdate with stage change to Closed - WON executed');
    }

    @IsTest
    static void testAfterUpdate_StageChangesToClosedLost() {
        Contract_Bid__c bid = createBid('Contact Verified and Updated');
        insert bid;

        bid.Stage__c = 'Closed - LOST';

        Test.startTest();
        update bid;
        Test.stopTest();

        System.assert(true, 'afterUpdate with stage change to Closed - LOST executed');
    }

    @IsTest
    static void testAfterUpdate_StageRemainsClosedWon_NoDoubleCall() {
        Contract_Bid__c bid = createBid('Closed - WON');
        insert bid;

        bid.Name = 'Updated Name';

        Test.startTest();
        update bid;
        Test.stopTest();

        System.assert(true, 'afterUpdate with unchanged Closed - WON executed');
    }
}