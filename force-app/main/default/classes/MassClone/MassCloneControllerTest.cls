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

    private static MassCloneController.CreateRequest buildRequest(
        String objectApiName,
        String clonePayloadJson
    ) {
        MassCloneController.CreateRequest request = new MassCloneController.CreateRequest();
        request.objectApiName = objectApiName;
        request.clonePayloadJson = clonePayloadJson;
        return request;
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

        Test.startTest();
        List<MassCloneController.CreateResult> results = MassCloneController.createRecords(
            new List<MassCloneController.CreateRequest>{
                buildRequest('Contract_Bid__c', payloadJson)
            }
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
        List<MassCloneController.CreateResult> unknownObjectResult = MassCloneController.createRecords(
            new List<MassCloneController.CreateRequest>{
                buildRequest('Not_A_Real_Object__c', '[{"fields":{"Name":"Test"}}]')
            }
        );
        List<MassCloneController.CreateResult> invalidJsonResult = MassCloneController.createRecords(
            new List<MassCloneController.CreateRequest>{
                buildRequest('Contract_Bid__c', '{not-json')
            }
        );
        List<MassCloneController.CreateResult> emptyPayloadResult = MassCloneController.createRecords(
            new List<MassCloneController.CreateRequest>{ buildRequest('Contract_Bid__c', '[]') }
        );
        List<MassCloneController.CreateResult> emptyFieldsResult = MassCloneController.createRecords(
            new List<MassCloneController.CreateRequest>{
                buildRequest('Contract_Bid__c', '[{"sourceName":"Missing Fields","fields":{}}]')
            }
        );
        Test.stopTest();

        System.assertNotEquals(null, emptyRequests[0].errorMessage);
        System.assertNotEquals(null, blankRequest[0].errorMessage);
        System.assert(unknownObjectResult[0].errorMessage.contains('Unknown object'));
        System.assert(invalidJsonResult[0].errorMessage.contains('Invalid clone payload JSON'));
        System.assertEquals(
            'No records were found in the clone payload.',
            emptyPayloadResult[0].errorMessage
        );
        System.assertEquals(1, emptyFieldsResult[0].failureCount);
    }

    @IsTest
    static void testCreateRecordsProcessesEveryRequest() {
        Account acc = new Account(Name = 'Bulk Invocable Account');
        insert acc;

        List<MassCloneController.CreateRequest> requests = new List<MassCloneController.CreateRequest>();
        for (Integer index = 0; index < 3; index++) {
            requests.add(
                buildRequest(
                    'Contract_Bid__c',
                    '[{"sourceName":"Bulk Source ' +
                        index +
                        '","fields":{"Name":"Bulk Clone ' +
                        index +
                        '","Customer__c":"' +
                        acc.Id +
                        '","Stage__c":"Contact Verified and Updated"}}]'
                )
            );
        }

        Test.startTest();
        List<MassCloneController.CreateResult> results = MassCloneController.createRecords(requests);
        Test.stopTest();

        System.assertEquals(3, results.size(), 'Flow requires one result per request');
        for (MassCloneController.CreateResult result : results) {
            System.assertEquals(1, result.successCount, 'Every request should be processed');
        }
        System.assertEquals(
            3,
            [SELECT COUNT() FROM Contract_Bid__c WHERE Name LIKE 'Bulk Clone%'],
            'Every request should have inserted its record'
        );
    }

    @IsTest
    static void testCreateCloneRecordsHandlesManyRows() {
        Account acc = new Account(Name = 'Volume Clone Account');
        insert acc;

        List<String> payloadItems = new List<String>();
        for (Integer index = 0; index < 50; index++) {
            payloadItems.add(
                '{"sourceName":"Volume Source ' +
                    index +
                    '","fields":{"Name":"Volume Clone ' +
                    index +
                    '","Customer__c":"' +
                    acc.Id +
                    '","Stage__c":"Contact Verified and Updated"}}'
            );
        }

        Test.startTest();
        MassCloneController.CreateResult result = MassCloneController.createCloneRecords(
            'Contract_Bid__c',
            '[' + String.join(payloadItems, ',') + ']'
        );
        Test.stopTest();

        System.assertEquals(50, result.successCount, 'All rows should be created in one insert');
        System.assertEquals(0, result.failureCount, 'No failures expected');
        System.assertEquals(50, result.rowResults.size(), 'Every row should be reported');
    }

    @IsTest
    static void testRowResultsReportPerRecordOutcome() {
        Account acc = new Account(Name = 'Row Result Account');
        insert acc;

        String payloadJson =
            '[{"sourceName":"Good Row","fields":{"Name":"Good Clone","Customer__c":"' +
            acc.Id +
            '","Stage__c":"Contact Verified and Updated"}},' +
            '{"sourceName":"Bad Row","fields":{"Name":"Bad Clone","Stage__c":"Contact Verified and Updated"}}]';

        Test.startTest();
        MassCloneController.CreateResult result = MassCloneController.createCloneRecords(
            'Contract_Bid__c',
            payloadJson
        );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'The valid row should be created');
        System.assertEquals(1, result.failureCount, 'The invalid row should be reported as failed');
        System.assertEquals(2, result.rowResults.size(), 'Both rows should be reported');

        System.assertEquals(0, result.rowResults[0].rowIndex, 'Rows keep their payload order');
        System.assertEquals('Good Row', result.rowResults[0].sourceName);
        System.assertEquals(true, result.rowResults[0].isSuccess);
        System.assertNotEquals(null, result.rowResults[0].recordId, 'Created id should be reported');

        System.assertEquals('Bad Row', result.rowResults[1].sourceName);
        System.assertEquals(false, result.rowResults[1].isSuccess);
        System.assert(
            result.rowResults[1].errorMessage.contains('Customer'),
            'The failing row should name the missing field'
        );
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
        Boolean threwAuraHandled = false;

        try {
            MassCloneController.getRecordFieldValuesJson(
                'Not_A_Real_Object__c',
                new List<Id>{ UserInfo.getUserId() },
                new List<String>{ 'Name' }
            );
        } catch (AuraHandledException ex) {
            threwAuraHandled = true;
        }

        System.assertEquals(
            true,
            threwAuraHandled,
            'Unknown object should surface as an AuraHandledException'
        );
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
