@IsTest
private class MassCloneServiceTest {
    private static final String OBJECT_NAME = 'Contract_Bid__c';

    private static String payloadFor(Id customerId, String extraFields) {
        return '[{"sourceName":"Service Source","fields":{"Name":"Service Clone","Customer__c":"' +
            customerId +
            '","Stage__c":"Contact Verified and Updated"' +
            extraFields +
            '}}]';
    }

    @IsTest
    static void testRejectsMissingArguments() {
        System.assertEquals(
            'Object API name and clone payload JSON are required.',
            MassCloneService.createRecords(null, null).errorMessage
        );
        System.assertEquals(
            'Object API name and clone payload JSON are required.',
            MassCloneService.createRecords(OBJECT_NAME, '   ').errorMessage
        );
    }

    @IsTest
    static void testRejectsUnknownObject() {
        MassCloneService.Result result = MassCloneService.createRecords(
            'Not_A_Real_Object__c',
            '[{"fields":{"Name":"Test"}}]'
        );

        System.assertEquals('Unknown object: Not_A_Real_Object__c', result.errorMessage);
        System.assertEquals(0, result.successCount);
    }

    @IsTest
    static void testReportsParseFailure() {
        MassCloneService.Result result = MassCloneService.createRecords(OBJECT_NAME, '{not-json');

        System.assertEquals(
            true,
            result.errorMessage.contains('Invalid clone payload JSON'),
            'A malformed payload should be reported clearly: ' + result.errorMessage
        );
        System.assertEquals(true, result.rowResults.isEmpty(), 'No rows could be identified');
    }

    @IsTest
    static void testReportsEmptyPayload() {
        MassCloneService.Result result = MassCloneService.createRecords(OBJECT_NAME, '[]');

        System.assertEquals('No records were found in the clone payload.', result.errorMessage);
        System.assertEquals(0, result.successCount);
    }

    @IsTest
    static void testReportsUnparseableFieldValueAgainstItsRow() {
        Account acc = new Account(Name = 'Conversion Account');
        insert acc;

        Test.startTest();
        MassCloneService.Result result = MassCloneService.createRecords(
            OBJECT_NAME,
            payloadFor(acc.Id, ',"Due_Date__c":"not-a-date"')
        );
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'A bad value must not be silently dropped');
        System.assertEquals(1, result.failureCount);
        System.assertEquals(1, result.rowResults.size());
        System.assertEquals('Service Source', result.rowResults[0].sourceName);
        System.assertEquals(
            true,
            result.rowResults[0].errorMessage.contains('not-a-date'),
            'The row error should quote the offending value: ' + result.rowResults[0].errorMessage
        );
    }

    @IsTest
    static void testIgnoresUnknownAndNonCreateableFields() {
        Account acc = new Account(Name = 'Unknown Field Account');
        insert acc;

        Test.startTest();
        MassCloneService.Result result = MassCloneService.createRecords(
            OBJECT_NAME,
            payloadFor(acc.Id, ',"Not_A_Field__c":"x","CreatedDate":"2020-01-01T00:00:00.000Z"')
        );
        Test.stopTest();

        System.assertEquals(
            1,
            result.successCount,
            'Unknown and read-only fields should be ignored rather than fail the row: ' +
                result.errorMessage
        );
        System.assertEquals(true, result.rowResults[0].isSuccess);
    }

    @IsTest
    static void testDeniesCreateWithoutObjectPermission() {
        List<Profile> minimumAccess = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];
        if (minimumAccess.isEmpty()) {
            return;
        }

        User restrictedUser = new User(
            Alias = 'mclone',
            Email = 'massclone.restricted@example.com.invalid',
            EmailEncodingKey = 'UTF-8',
            FirstName = 'Mass',
            LastName = 'Clone',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = minimumAccess[0].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'massclone.restricted.' + DateTime.now().getTime() + '@example.com.invalid'
        );

        // Setup-object DML is isolated so it cannot conflict with the record DML under test.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert restrictedUser;
        }

        MassCloneService.Result result;

        Test.startTest();
        System.runAs(restrictedUser) {
            // Describe results are resolved inside runAs so they reflect this user's access.
            result = MassCloneService.createRecords(
                OBJECT_NAME,
                payloadFor(UserInfo.getUserId(), '')
            );
        }
        Test.stopTest();

        System.assertNotEquals(
            null,
            result.errorMessage,
            'A user without create permission should get a clear error'
        );
        System.assertEquals(0, result.successCount, 'Nothing should be created');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Contract_Bid__c],
            'User mode DML must not insert records for an unauthorised user'
        );
    }
}
