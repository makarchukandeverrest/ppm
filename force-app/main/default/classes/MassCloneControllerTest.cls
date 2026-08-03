@IsTest
private class MassCloneControllerTest {
    private static Contract_Bid__c createSourceBid(String name, Id customerId) {
        Contract_Bid__c source = new Contract_Bid__c(
            Name = name,
            Customer__c = customerId,
            Stage__c = 'Contact Verified and Updated',
            Contract_Year__c = '2024-2025'
        );
        insert source;
        return source;
    }

    @IsTest
    static void testCreateRecordsFromPayload() {
        Account acc = new Account(Name = 'Mass Clone Account');
        insert acc;

        Contract_Bid__c source = createSourceBid('Source Bid 2025', acc.Id);

        String payloadJson =
            '[{"sourceId":"' +
            source.Id +
            '","sourceName":"Source Bid 2025","fields":{"Name":"Clone Bid 2026","Customer__c":"' +
            acc.Id +
            '","Stage__c":"Contact Verified and Updated","Contract_Year__c":"2025-2026","Due_Date__c":"2026-01-15"}}]';

        MassCloneController.CreateRequest request = new MassCloneController.CreateRequest();
        request.objectApiName = 'Contract_Bid__c';
        request.clonePayloadJson = payloadJson;

        Test.startTest();
        List<MassCloneController.CreateResult> results = MassCloneController.createRecords(
            new List<MassCloneController.CreateRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result expected');
        System.assertEquals(1, results[0].successCount, 'One record should be created');
        System.assertEquals(0, results[0].failureCount, 'No failures expected');
        System.assertEquals(1, results[0].createdRecordIds.size(), 'One id expected');

        Contract_Bid__c created = [
            SELECT Name, Contract_Year__c
            FROM Contract_Bid__c
            WHERE Id = :results[0].createdRecordIds[0]
        ];
        System.assertEquals('Clone Bid 2026', created.Name);
        System.assertEquals('2025-2026', created.Contract_Year__c);
    }

    @IsTest
    static void testCreateRecordsValidationErrors() {
        Test.startTest();
        List<MassCloneController.CreateResult> emptyRequests = MassCloneController.createRecords(
            null
        );
        List<MassCloneController.CreateResult> blankRequest = MassCloneController.createRecords(
            new List<MassCloneController.CreateRequest>{ new MassCloneController.CreateRequest() }
        );

        MassCloneController.CreateRequest unknownObject = new MassCloneController.CreateRequest();
        unknownObject.objectApiName = 'Not_A_Real_Object__c';
        unknownObject.clonePayloadJson = '[{"fields":{"Name":"Test"}}]';
        List<MassCloneController.CreateResult> unknownObjectResult = MassCloneController.createRecords(
            new List<MassCloneController.CreateRequest>{ unknownObject }
        );

        MassCloneController.CreateRequest invalidJson = new MassCloneController.CreateRequest();
        invalidJson.objectApiName = 'Contract_Bid__c';
        invalidJson.clonePayloadJson = '{not-json';
        List<MassCloneController.CreateResult> invalidJsonResult = MassCloneController.createRecords(
            new List<MassCloneController.CreateRequest>{ invalidJson }
        );

        MassCloneController.CreateRequest emptyPayload = new MassCloneController.CreateRequest();
        emptyPayload.objectApiName = 'Contract_Bid__c';
        emptyPayload.clonePayloadJson = '[]';
        List<MassCloneController.CreateResult> emptyPayloadResult = MassCloneController.createRecords(
            new List<MassCloneController.CreateRequest>{ emptyPayload }
        );

        MassCloneController.CreateRequest emptyFields = new MassCloneController.CreateRequest();
        emptyFields.objectApiName = 'Contract_Bid__c';
        emptyFields.clonePayloadJson = '[{"sourceName":"Missing Fields","fields":{}}]';
        List<MassCloneController.CreateResult> emptyFieldsResult = MassCloneController.createRecords(
            new List<MassCloneController.CreateRequest>{ emptyFields }
        );
        Test.stopTest();

        System.assertNotEquals(null, emptyRequests[0].errorMessage);
        System.assertNotEquals(null, blankRequest[0].errorMessage);
        System.assert(unknownObjectResult[0].errorMessage.contains('Unknown object'));
        System.assert(invalidJsonResult[0].errorMessage.contains('Invalid clone payload JSON'));
        System.assertEquals('No records were found in the clone payload.', emptyPayloadResult[0].errorMessage);
        System.assertEquals(1, emptyFieldsResult[0].failureCount);
    }

    @IsTest
    static void testGetRecordFieldValuesJson() {
        Account acc = new Account(Name = 'Field Values Account');
        insert acc;

        Contract_Bid__c source = createSourceBid('Field Values Bid', acc.Id);

        Test.startTest();
        String jsonResult = MassCloneController.getRecordFieldValuesJson(
            'Contract_Bid__c',
            new List<Id>{ source.Id },
            new List<String>{ 'Name', 'Customer__c', 'Stage__c' }
        );
        String emptyResult = MassCloneController.getRecordFieldValuesJson(
            'Contract_Bid__c',
            new List<Id>(),
            new List<String>{ 'Name' }
        );
        String noFieldsResult = MassCloneController.getRecordFieldValuesJson(
            'Contract_Bid__c',
            new List<Id>{ source.Id },
            new List<String>()
        );
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonResult);
        System.assertEquals(true, parsed.containsKey(source.Id), 'Source record should be returned');

        Map<String, Object> values = (Map<String, Object>) parsed.get(source.Id);
        System.assertEquals('Field Values Bid', values.get('Name'));
        System.assertEquals(acc.Id, values.get('Customer__c'));
        System.assertEquals('{}', emptyResult);
        System.assertEquals('{}', noFieldsResult);
    }

    @IsTest
    static void testGetRecordFieldValuesJsonUnknownObject() {
        Boolean threw = false;
        try {
            MassCloneController.getRecordFieldValuesJson(
                'Not_A_Real_Object__c',
                new List<Id>{ UserInfo.getUserId() },
                new List<String>{ 'Name' }
            );
        } catch (Exception ex) {
            threw = true;
        }

        System.assertEquals(true, threw, 'Unknown object should throw');
    }

    @IsTest
    static void testCreateCloneRecordsAura() {
        Account acc = new Account(Name = 'Aura Clone Account');
        insert acc;

        String payloadJson =
            '[{"sourceName":"Aura Source","fields":{"Name":"Aura Clone Bid","Customer__c":"' +
            acc.Id +
            '","Stage__c":"Contact Verified and Updated"}}]';

        Test.startTest();
        MassCloneController.CreateResult result = MassCloneController.createCloneRecords(
            'Contract_Bid__c',
            payloadJson
        );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Aura create should succeed');
        System.assertNotEquals(null, result.createdRecordIds, 'Created ids should be returned');
    }

    @IsTest
    static void testCreateCloneRecordsMissingCustomer() {
        String payloadJson =
            '[{"sourceName":"Missing Customer","fields":{"Name":"Clone Without Customer","Stage__c":"Contact Verified and Updated"}}]';

        Test.startTest();
        MassCloneController.CreateResult result = MassCloneController.createCloneRecords(
            'Contract_Bid__c',
            payloadJson
        );
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Insert should not succeed without Customer');
        System.assertEquals(1, result.failureCount, 'One failure expected');
        System.assert(result.errorMessage.contains('Customer'), 'Error should mention Customer');
    }

    @IsTest
    static void testCreateCloneRecordsWithTimeFields() {
        Account acc = new Account(Name = 'Time Field Account');
        insert acc;

        String payloadJson =
            '[{"sourceName":"Time Source","fields":{"Name":"Clone With Times","Customer__c":"' +
            acc.Id +
            '","Stage__c":"Contact Verified and Updated","Normal_Season_Monday_Open_Time__c":"09:30:00.000","Normal_Season_Monday_Close_Time__c":"17:45:00.000"}}]';

        Test.startTest();
        MassCloneController.CreateResult result = MassCloneController.createCloneRecords(
            'Contract_Bid__c',
            payloadJson
        );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Time fields should convert correctly');
        System.assertEquals(0, result.failureCount, 'No failures expected');

        Contract_Bid__c created = [
            SELECT Normal_Season_Monday_Open_Time__c, Normal_Season_Monday_Close_Time__c
            FROM Contract_Bid__c
            WHERE Id = :result.createdRecordIds[0]
        ];
        System.assertEquals(
            Time.newInstance(9, 30, 0, 0),
            created.Normal_Season_Monday_Open_Time__c
        );
        System.assertEquals(
            Time.newInstance(17, 45, 0, 0),
            created.Normal_Season_Monday_Close_Time__c
        );
    }
}
