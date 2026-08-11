@IsTest
private class SObjectFieldConverterTest {
    private static Schema.DescribeFieldResult bidField(String fieldName) {
        return SchemaService.getFieldDescribe('Contract_Bid__c', fieldName);
    }

    @IsTest
    static void testConvertReturnsNullForAbsentValues() {
        System.assertEquals(null, SObjectFieldConverter.convert(null, bidField('Name')));
        System.assertEquals(null, SObjectFieldConverter.convert('anything', null));
    }

    @IsTest
    static void testConvertDateAndDatetime() {
        System.assertEquals(
            Date.newInstance(2026, 1, 15),
            SObjectFieldConverter.convert('2026-01-15', bidField('Due_Date__c'))
        );
        System.assertEquals(
            Date.newInstance(2026, 1, 15),
            SObjectFieldConverter.convert(
                Date.newInstance(2026, 1, 15),
                bidField('Due_Date__c')
            ),
            'An already typed value should pass through'
        );

        Object converted = SObjectFieldConverter.convert(
            '2026-01-15T10:30:00.000Z',
            bidField('CreatedDate')
        );
        System.assertEquals(true, converted instanceof Datetime, 'Datetime fields accept ISO strings');
    }

    @IsTest
    static void testConvertTextPicklistAndReference() {
        System.assertEquals('Bid Name', SObjectFieldConverter.convert('Bid Name', bidField('Name')));
        System.assertEquals(
            '2025-2026',
            SObjectFieldConverter.convert('2025-2026', bidField('Contract_Year__c'))
        );

        Id someId = UserInfo.getUserId();
        System.assertEquals(
            someId,
            SObjectFieldConverter.convert(' ' + someId + ' ', bidField('Customer__c')),
            'Reference fields are trimmed and converted to Id'
        );
    }

    @IsTest
    static void testConvertBooleanAndNumbers() {
        System.assertEquals(
            true,
            SObjectFieldConverter.convert('true', bidField('IsDeleted')),
            'Boolean strings are parsed'
        );
        System.assertEquals(
            1500.5,
            SObjectFieldConverter.convert(
                1500.5,
                SchemaService.getFieldDescribe('Account', 'AnnualRevenue')
            ),
            'Currency values become Decimal'
        );
        System.assertEquals(
            42,
            SObjectFieldConverter.convert(
                '42',
                SchemaService.getFieldDescribe('Account', 'NumberOfEmployees')
            ),
            'Integer strings are parsed'
        );
    }

    @IsTest
    static void testBlankStringsClearNonTextFieldsButSurviveOnText() {
        System.assertEquals(
            null,
            SObjectFieldConverter.convert('   ', bidField('Due_Date__c')),
            'A blank string means no value for a date'
        );
        System.assertEquals(
            '',
            SObjectFieldConverter.convert('', bidField('Name')),
            'A blank string is a legitimate text value'
        );
    }

    @IsTest
    static void testConvertReportsUnparseableValues() {
        Boolean threw = false;
        String message;

        try {
            SObjectFieldConverter.convert('not-a-date', bidField('Due_Date__c'));
        } catch (SObjectFieldConverter.ConversionException ex) {
            threw = true;
            message = ex.getMessage();
        }

        System.assertEquals(true, threw, 'A bad value must be reported, not silently nulled');
        System.assertEquals(
            true,
            message.contains('not-a-date'),
            'The message should quote the offending value: ' + message
        );
    }

    @IsTest
    static void testParseTimeAcceptsSupportedShapes() {
        Time expected = Time.newInstance(9, 30, 0, 0);

        System.assertEquals(expected, SObjectFieldConverter.parseTime(expected));
        System.assertEquals(expected, SObjectFieldConverter.parseTime('09:30'));
        System.assertEquals(expected, SObjectFieldConverter.parseTime('09:30:00.000'));
        System.assertEquals(
            expected,
            SObjectFieldConverter.parseTime('2026-01-15T09:30:00.000Z'),
            'The time component of a full ISO datetime should be used'
        );
        System.assertEquals(
            expected,
            SObjectFieldConverter.parseTime(34200000),
            'Milliseconds since midnight should be supported'
        );
    }

    @IsTest
    static void testParseTimeNormalizesFractionalSeconds() {
        System.assertEquals(
            Time.newInstance(9, 30, 45, 123),
            SObjectFieldConverter.parseTime('09:30:45.1234'),
            'Fractional seconds are truncated to milliseconds'
        );
        System.assertEquals(
            Time.newInstance(9, 30, 45, 500),
            SObjectFieldConverter.parseTime('09:30:45.5'),
            'Short fractional seconds are right-padded'
        );
    }

    @IsTest
    static void testParseTimeHandlesAbsentAndInvalidValues() {
        System.assertEquals(null, SObjectFieldConverter.parseTime(null));
        System.assertEquals(null, SObjectFieldConverter.parseTime('   '));

        Boolean threw = false;
        try {
            SObjectFieldConverter.parseTime('half past nine');
        } catch (SObjectFieldConverter.ConversionException ex) {
            threw = true;
        }

        System.assertEquals(true, threw, 'An unparseable time must be reported');
    }
}
