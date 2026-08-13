public with sharing class SchemaService {
    private static final Map<String, Schema.DescribeSObjectResult> DESCRIBES = new Map<String, Schema.DescribeSObjectResult>();
    private static final Map<String, Map<String, Schema.SObjectField>> FIELD_MAPS = new Map<String, Map<String, Schema.SObjectField>>();
    private static final Map<String, Map<String, String>> REQUIRED_CREATABLE_FIELDS = new Map<String, Map<String, String>>();

    private static String cacheKey(String objectApiName) {
        return UserInfo.getUserId() + ':' + objectApiName.toLowerCase();
    }

    public static Schema.DescribeSObjectResult getDescribe(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null;
        }

        String key = cacheKey(objectApiName);
        if (DESCRIBES.containsKey(key)) {
            return DESCRIBES.get(key);
        }

        Schema.DescribeSObjectResult describe = null;
        try {
            List<Schema.DescribeSObjectResult> describes = Schema.describeSObjects(
                new List<String>{ objectApiName },
                SObjectDescribeOptions.DEFERRED
            );
            if (!describes.isEmpty()) {
                describe = describes[0];
            }
        } catch (Exception ex) {
            describe = null;
        }

        DESCRIBES.put(key, describe);
        return describe;
    }

    public static Schema.SObjectType getSObjectType(String objectApiName) {
        Schema.DescribeSObjectResult describe = getDescribe(objectApiName);
        return describe == null ? null : describe.getSObjectType();
    }

    public static Map<String, Schema.SObjectField> getFieldMap(String objectApiName) {
        Schema.DescribeSObjectResult describe = getDescribe(objectApiName);
        if (describe == null) {
            return new Map<String, Schema.SObjectField>();
        }

        String key = cacheKey(objectApiName);
        if (FIELD_MAPS.containsKey(key)) {
            return FIELD_MAPS.get(key);
        }

        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
        FIELD_MAPS.put(key, fieldMap);
        return fieldMap;
    }

    public static Schema.DescribeFieldResult getFieldDescribe(String objectApiName, String fieldName) {
        if (String.isBlank(fieldName)) {
            return null;
        }

        Schema.SObjectField token = getFieldMap(objectApiName).get(fieldName.toLowerCase());
        return token == null ? null : token.getDescribe();
    }

    public static Map<String, String> getRequiredCreatableFields(String objectApiName) {
        Schema.DescribeSObjectResult describe = getDescribe(objectApiName);
        if (describe == null) {
            return new Map<String, String>();
        }

        String key = cacheKey(objectApiName);
        if (REQUIRED_CREATABLE_FIELDS.containsKey(key)) {
            return REQUIRED_CREATABLE_FIELDS.get(key);
        }

        Map<String, String> requiredFields = new Map<String, String>();
        for (Schema.SObjectField token : getFieldMap(objectApiName).values()) {
            Schema.DescribeFieldResult fieldDescribe = token.getDescribe();
            if (fieldDescribe.isCreateable() && !fieldDescribe.isNillable() && !fieldDescribe.isDefaultedOnCreate()) {
                requiredFields.put(fieldDescribe.getName(), fieldDescribe.getLabel());
            }
        }

        REQUIRED_CREATABLE_FIELDS.put(key, requiredFields);
        return requiredFields;
    }

    public static List<String> getReadableFieldNames(String objectApiName, List<String> fieldNames) {
        List<String> readableFields = new List<String>();
        if (fieldNames == null || fieldNames.isEmpty()) {
            return readableFields;
        }

        Set<String> seen = new Set<String>();
        for (String fieldName : fieldNames) {
            Schema.DescribeFieldResult describe = getFieldDescribe(objectApiName, fieldName);
            if (describe == null || !describe.isAccessible()) {
                continue;
            }

            String apiName = describe.getName();
            if (seen.add(apiName)) {
                readableFields.add(apiName);
            }
        }

        return readableFields;
    }

    public static Boolean isCreateable(String objectApiName) {
        Schema.DescribeSObjectResult describe = getDescribe(objectApiName);
        return describe != null && describe.isCreateable();
    }

    public static Boolean isAccessible(String objectApiName) {
        Schema.DescribeSObjectResult describe = getDescribe(objectApiName);
        return describe != null && describe.isAccessible();
    }
}
