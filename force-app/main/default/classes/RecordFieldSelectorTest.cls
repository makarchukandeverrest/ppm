@IsTest
private class RecordFieldSelectorTest {
    private static Contract_Bid__c createBid() {
        Account acc = new Account(Name = 'Selector Account');
        insert acc;

        Contract_Bid__c bid = new Contract_Bid__c(
            Name = 'Selector Bid',
            Customer__c = acc.Id,
            Stage__c = 'Contact Verified and Updated',
            Contract_Year__c = '2024-2025'
        );
        insert bid;
        return bid;
    }

    /**
     * Field names that are safe to place in a SELECT clause, used to push the selector past
     * its per-query field batch size.
     */
    private static List<String> queryableFieldNames(Integer maximum) {
        List<String> fieldNames = new List<String>();

        for (Schema.SObjectField token : SchemaService.getFieldMap('Contract_Bid__c').values()) {
            Schema.DescribeFieldResult describe = token.getDescribe();
            Schema.DisplayType fieldType = describe.getType();

            if (
                !describe.isAccessible() ||
                fieldType == Schema.DisplayType.Address ||
                fieldType == Schema.DisplayType.Location ||
                fieldType == Schema.DisplayType.Base64
            ) {
                continue;
            }

            fieldNames.add(describe.getName());
            if (fieldNames.size() == maximum) {
                break;
            }
        }

        return fieldNames;
    }

    @IsTest
    static void testGetFieldValuesReturnsRequestedFields() {
        Contract_Bid__c bid = createBid();

        Test.startTest();
        Map<Id, Map<String, Object>> values = RecordFieldSelector.getFieldValues(
            'Contract_Bid__c',
            new List<Id>{ bid.Id },
            new List<String>{ 'name', 'Stage__c' }
        );
        Test.stopTest();

        System.assertEquals(1, values.size(), 'The requested record should be returned');
        Map<String, Object> bidValues = values.get(bid.Id);
        System.assertEquals(
            'Selector Bid',
            bidValues.get('Name'),
            'Values are keyed by canonical field name'
        );
        System.assertEquals('Contact Verified and Updated', bidValues.get('Stage__c'));
    }

    @IsTest
    static void testGetFieldValuesReturnsEmptyForNothingToDo() {
        Contract_Bid__c bid = createBid();

        System.assertEquals(
            true,
            RecordFieldSelector.getFieldValues('Contract_Bid__c', new List<Id>(), new List<String>{ 'Name' })
                .isEmpty(),
            'No record ids means nothing to query'
        );
        System.assertEquals(
            true,
            RecordFieldSelector.getFieldValues('', new List<Id>{ bid.Id }, new List<String>{ 'Name' })
                .isEmpty(),
            'A blank object name means nothing to query'
        );
        System.assertEquals(
            true,
            RecordFieldSelector.getFieldValues(
                    'Contract_Bid__c',
                    new List<Id>{ bid.Id },
                    new List<String>{ 'Not_A_Field__c' }
                )
                .isEmpty(),
            'No resolvable fields means nothing to query'
        );
    }

    @IsTest
    static void testGetFieldValuesRejectsUnknownObject() {
        Boolean threw = false;

        try {
            RecordFieldSelector.getFieldValues(
                'Not_A_Real_Object__c',
                new List<Id>{ UserInfo.getUserId() },
                new List<String>{ 'Name' }
            );
        } catch (RecordFieldSelector.SelectorException ex) {
            threw = true;
        }

        System.assertEquals(true, threw, 'An unknown object should be rejected');
    }

    @IsTest
    static void testGetFieldValuesBatchesWideFieldLists() {
        Contract_Bid__c bid = createBid();
        List<String> fieldNames = queryableFieldNames(45);
        System.assertEquals(
            true,
            fieldNames.size() > 40,
            'This test needs more fields than fit in a single batch'
        );

        Test.startTest();
        Map<Id, Map<String, Object>> values = RecordFieldSelector.getFieldValues(
            'Contract_Bid__c',
            new List<Id>{ bid.Id },
            fieldNames
        );
        Test.stopTest();

        System.assertEquals(
            fieldNames.size(),
            values.get(bid.Id).size(),
            'Values from every batch should be merged into one map per record'
        );
    }
}
