public with sharing class MassCloneController {
    public class CreateRequest {
        @InvocableVariable(required=true label='Object API Name')
        public String objectApiName;

        @InvocableVariable(required=true label='Clone Payload JSON')
        public String clonePayloadJson;
    }

    public class CreateResult {
        @InvocableVariable(label='Created Record Ids')
        @AuraEnabled
        public List<String> createdRecordIds;

        @InvocableVariable(label='Success Count')
        @AuraEnabled
        public Integer successCount;

        @InvocableVariable(label='Failure Count')
        @AuraEnabled
        public Integer failureCount;

        @InvocableVariable(label='Error Message')
        @AuraEnabled
        public String errorMessage;
    }

    @InvocableMethod(
        label='Create Mass Clone Records'
        description='Inserts records from JSON payloads produced by massCloneBase'
        category='Mass Clone'
    )
    public static List<CreateResult> createRecords(List<CreateRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<CreateResult>{ buildErrorResult('No create request was provided.') };
        }

        CreateRequest request = requests[0];
        return new List<CreateResult>{
            createRecordsInternal(request.objectApiName, request.clonePayloadJson)
        };
    }

    @AuraEnabled
    public static CreateResult createCloneRecords(String objectApiName, String clonePayloadJson) {
        return createRecordsInternal(objectApiName, clonePayloadJson);
    }

    private static CreateResult buildErrorResult(String message) {
        CreateResult result = new CreateResult();
        result.createdRecordIds = new List<String>();
        result.successCount = 0;
        result.failureCount = 0;
        result.errorMessage = message;
        return result;
    }

    private static CreateResult createRecordsInternal(
        String objectApiName,
        String clonePayloadJson
    ) {
        CreateResult result = new CreateResult();
        result.createdRecordIds = new List<String>();
        result.successCount = 0;
        result.failureCount = 0;

        try {
            if (String.isBlank(objectApiName) || String.isBlank(clonePayloadJson)) {
                result.errorMessage = 'Object API name and clone payload JSON are required.';
                return result;
            }

            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
            if (objectType == null) {
                result.errorMessage = 'Unknown object: ' + objectApiName;
                return result;
            }

            List<Object> payloadItems;
            try {
                payloadItems = (List<Object>) JSON.deserializeUntyped(clonePayloadJson);
            } catch (Exception ex) {
                result.errorMessage = 'Invalid clone payload JSON: ' + ex.getMessage();
                return result;
            }

            if (payloadItems == null || payloadItems.isEmpty()) {
                result.errorMessage = 'No records were found in the clone payload.';
                return result;
            }

            Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
            List<SObject> recordsToInsert = new List<SObject>();
            List<String> errorMessages = new List<String>();

            for (Object payloadItem : payloadItems) {
                Map<String, Object> payload = (Map<String, Object>) payloadItem;
                Map<String, Object> fields = (Map<String, Object>) payload.get('fields');
                String sourceName = payload.containsKey('sourceName')
                    ? String.valueOf(payload.get('sourceName'))
                    : 'Record';

                if (fields == null || fields.isEmpty()) {
                    errorMessages.add(sourceName + ': no field values to create.');
                    result.failureCount++;
                    continue;
                }

                SObject record = objectType.newSObject();
                List<String> missingRequiredFields = new List<String>();

                for (String fieldName : fields.keySet()) {
                    Schema.SObjectField token = fieldMap.get(fieldName.toLowerCase());
                    if (token == null) {
                        continue;
                    }

                    Schema.DescribeFieldResult describe = token.getDescribe();
                    if (!describe.isCreateable()) {
                        continue;
                    }

                    Object convertedValue = convertValue(fields.get(fieldName), describe);
                    if (convertedValue != null) {
                        record.put(fieldName, convertedValue);
                    }
                }

                for (Schema.SObjectField token : fieldMap.values()) {
                    Schema.DescribeFieldResult describe = token.getDescribe();
                    if (!describe.isCreateable() || describe.isNillable() || describe.isDefaultedOnCreate()) {
                        continue;
                    }

                    String requiredFieldName = describe.getName();
                    if (!record.getPopulatedFieldsAsMap().containsKey(requiredFieldName)) {
                        missingRequiredFields.add(describe.getLabel());
                    }
                }

                if (!missingRequiredFields.isEmpty()) {
                    errorMessages.add(
                        sourceName +
                            ': missing required field(s): ' +
                            String.join(missingRequiredFields, ', ')
                    );
                    result.failureCount++;
                    continue;
                }

                recordsToInsert.add(record);
            }

            if (recordsToInsert.isEmpty()) {
                result.errorMessage = errorMessages.isEmpty()
                    ? 'No createable field values were found.'
                    : String.join(errorMessages, ' ');
                result.failureCount = payloadItems.size();
                return result;
            }

            Database.SaveResult[] saveResults = Database.insert(recordsToInsert, false);
            for (Database.SaveResult saveResult : saveResults) {
                if (saveResult.isSuccess()) {
                    result.createdRecordIds.add(saveResult.getId());
                    result.successCount++;
                } else {
                    result.failureCount++;
                    for (Database.Error err : saveResult.getErrors()) {
                        errorMessages.add(err.getMessage());
                    }
                }
            }

            if (!errorMessages.isEmpty()) {
                result.errorMessage = String.join(errorMessages, ' ');
            }
        } catch (Exception ex) {
            result.errorMessage = ex.getMessage();
        }

        return result;
    }

    @AuraEnabled
    public static String getRecordFieldValuesJson(
        String objectApiName,
        List<Id> recordIds,
        List<String> fieldNames
    ) {
        if (String.isBlank(objectApiName) || recordIds == null || recordIds.isEmpty()) {
            return '{}';
        }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            throw new AuraHandledException('Unknown object: ' + objectApiName);
        }

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        List<String> queryFields = new List<String>();
        if (fieldNames != null) {
            for (String fieldName : fieldNames) {
                if (String.isBlank(fieldName)) {
                    continue;
                }
                Schema.SObjectField token = fieldMap.get(fieldName.toLowerCase());
                if (token != null && token.getDescribe().isAccessible()) {
                    String apiName = token.getDescribe().getName();
                    if (!queryFields.contains(apiName)) {
                        queryFields.add(apiName);
                    }
                }
            }
        }

        if (queryFields.isEmpty()) {
            return '{}';
        }

        try {
            Map<String, Map<String, Object>> mergedResults = new Map<String, Map<String, Object>>();
            Integer chunkSize = 40;

            for (Integer startIndex = 0; startIndex < queryFields.size(); startIndex += chunkSize) {
                Integer endIndex = Math.min(startIndex + chunkSize, queryFields.size());
                List<String> chunkFields = new List<String>();
                for (Integer index = startIndex; index < endIndex; index++) {
                    chunkFields.add(queryFields[index]);
                }

                String soql =
                    'SELECT ' +
                    String.join(chunkFields, ',') +
                    ' FROM ' +
                    objectApiName +
                    ' WHERE Id IN :recordIds';
                List<SObject> records = Database.query(soql);

                for (SObject record : records) {
                    String recordId = String.valueOf(record.get('Id'));
                    if (!mergedResults.containsKey(recordId)) {
                        mergedResults.put(recordId, new Map<String, Object>());
                    }

                    Map<String, Object> values = mergedResults.get(recordId);
                    for (String fieldName : chunkFields) {
                        values.put(fieldName, record.get(fieldName));
                    }
                }
            }

            return JSON.serialize(mergedResults);
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load source records: ' + ex.getMessage());
        }
    }

    private static Object convertValue(Object value, Schema.DescribeFieldResult describe) {
        if (value == null) {
            return null;
        }

        try {
            Schema.DisplayType fieldType = describe.getType();
            if (fieldType == Schema.DisplayType.Date && value instanceof String) {
                return Date.valueOf((String) value);
            }
            if (fieldType == Schema.DisplayType.DateTime && value instanceof String) {
                return (DateTime) JSON.deserialize('"' + (String) value + '"', DateTime.class);
            }
            if (fieldType == Schema.DisplayType.Time) {
                return parseTimeValue(value);
            }
            if (fieldType == Schema.DisplayType.Boolean && value instanceof String) {
                return Boolean.valueOf((String) value);
            }
            if (
                fieldType == Schema.DisplayType.Double ||
                fieldType == Schema.DisplayType.Currency ||
                fieldType == Schema.DisplayType.Percent
            ) {
                if (value instanceof String) {
                    return Decimal.valueOf((String) value);
                }
                if (value instanceof Integer || value instanceof Long) {
                    return Decimal.valueOf(String.valueOf(value));
                }
                if (value instanceof Double) {
                    return Decimal.valueOf((Double) value);
                }
            }
            if (fieldType == Schema.DisplayType.Reference || fieldType == Schema.DisplayType.Id) {
                if (value instanceof String) {
                    String idValue = ((String) value).trim();
                    if (String.isBlank(idValue)) {
                        return null;
                    }
                    return (Id) idValue;
                }
            }
            if (fieldType == Schema.DisplayType.Picklist || fieldType == Schema.DisplayType.MultiPicklist) {
                return String.valueOf(value);
            }

            return value;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Time parseTimeValue(Object value) {
        if (value == null) {
            return null;
        }

        if (value instanceof Time) {
            return (Time) value;
        }

        if (value instanceof Integer || value instanceof Long || value instanceof Decimal) {
            Long totalMilliseconds = Long.valueOf(String.valueOf(value));
            Long totalSeconds = totalMilliseconds / 1000;
            Integer hour = (Integer)(totalSeconds / 3600);
            Integer minute = (Integer)Math.mod(totalSeconds / 60, 60);
            Integer second = (Integer)Math.mod(totalSeconds, 60);
            Integer millisecond = (Integer)Math.mod(totalMilliseconds, 1000);
            return Time.newInstance(hour, minute, second, millisecond);
        }

        if (!(value instanceof String)) {
            return null;
        }

        String timeValue = ((String) value).trim();
        if (String.isBlank(timeValue)) {
            return null;
        }

        String normalized = timeValue;
        if (normalized.endsWith('Z')) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }

        Integer timeSeparatorIndex = normalized.indexOf('T');
        if (timeSeparatorIndex >= 0) {
            normalized = normalized.substring(timeSeparatorIndex + 1);
        }

        List<String> parts = normalized.split(':');
        if (parts.size() < 2) {
            return null;
        }

        Integer hour = Integer.valueOf(parts[0]);
        Integer minute = Integer.valueOf(parts[1]);
        Integer second = 0;
        Integer millisecond = 0;

        if (parts.size() >= 3) {
            String secondPart = parts[2];
            if (secondPart.contains('.')) {
                List<String> secondParts = secondPart.split('\\.');
                second = Integer.valueOf(secondParts[0]);
                String millisecondPart = secondParts[1];
                if (millisecondPart.length() > 3) {
                    millisecondPart = millisecondPart.substring(0, 3);
                }
                while (millisecondPart.length() < 3) {
                    millisecondPart += '0';
                }
                millisecond = Integer.valueOf(millisecondPart);
            } else {
                second = Integer.valueOf(secondPart);
            }
        }

        return Time.newInstance(hour, minute, second, millisecond);
    }
}
