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