@IsTest
private class SchemaServiceTest {
    @IsTest
    static void testGetSObjectTypeResolvesRegardlessOfCasing() {
        Schema.SObjectType first = SchemaService.getSObjectType('Contract_Bid__c');
        Schema.SObjectType second = SchemaService.getSObjectType('contract_bid__c');

        System.assertNotEquals(null, first, 'A real object should resolve');
        System.assertEquals(first, second, 'Lookups should be case-insensitive and cached');
    }

    @IsTest
    static void testGetSObjectTypeReturnsNullForUnresolvableNames() {
        System.assertEquals(null, SchemaService.getSObjectType('Not_A_Real_Object__c'));
        System.assertEquals(null, SchemaService.getSObjectType(null));
        System.assertEquals(null, SchemaService.getSObjectType(''));
    }

    @IsTest
    static void testGetFieldMapAndFieldDescribe() {
        Map<String, Schema.SObjectField> fieldMap = SchemaService.getFieldMap('Contract_Bid__c');
        System.assertEquals(true, fieldMap.containsKey('customer__c'), 'Keys are lowercased');
        System.assertEquals(
            true,
            SchemaService.getFieldMap('Not_A_Real_Object__c').isEmpty(),
            'Unknown objects have no fields'
        );

        Schema.DescribeFieldResult describe = SchemaService.getFieldDescribe(
            'Contract_Bid__c',
            'customer__c'
        );
        System.assertEquals(
            'Customer__c',
            describe.getName(),
            'The canonical API name should be returned regardless of input casing'
        );
        System.assertEquals(
            null,
            SchemaService.getFieldDescribe('Contract_Bid__c', 'Not_A_Field__c'),
            'Unknown fields resolve to null'
        );
        System.assertEquals(null, SchemaService.getFieldDescribe('Contract_Bid__c', null));
    }

    @IsTest
    static void testGetRequiredCreatableFields() {
        Map<String, String> requiredFields = SchemaService.getRequiredCreatableFields(
            'Contract_Bid__c'
        );

        System.assertEquals(
            true,
            requiredFields.containsKey('Customer__c'),
            'A master-detail relationship is required on create'
        );
        System.assertEquals(
            'Customer',
            requiredFields.get('Customer__c'),
            'The field label should be returned for user-facing messages'
        );
        System.assertEquals(
            true,
            SchemaService.getRequiredCreatableFields('Not_A_Real_Object__c').isEmpty()
        );
    }

    @IsTest
    static void testGetReadableFieldNamesDeduplicatesAndFilters() {
        List<String> readableFields = SchemaService.getReadableFieldNames(
            'Contract_Bid__c',
            new List<String>{ 'name', 'Name', 'Not_A_Field__c', '', null, 'customer__c' }
        );

        System.assertEquals(
            new List<String>{ 'Name', 'Customer__c' },
            readableFields,
            'Names are canonicalised, deduplicated and unknown fields dropped'
        );
        System.assertEquals(
            true,
            SchemaService.getReadableFieldNames('Contract_Bid__c', null).isEmpty()
        );
        System.assertEquals(
            true,
            SchemaService.getReadableFieldNames('Contract_Bid__c', new List<String>()).isEmpty()
        );
    }

    @IsTest
    static void testObjectLevelPermissionChecks() {
        System.assertEquals(true, SchemaService.isCreateable('Contract_Bid__c'));
        System.assertEquals(true, SchemaService.isAccessible('Contract_Bid__c'));
        System.assertEquals(
            false,
            SchemaService.isCreateable('Not_A_Real_Object__c'),
            'An unresolvable object is never createable'
        );
        System.assertEquals(false, SchemaService.isAccessible('Not_A_Real_Object__c'));
    }
}
