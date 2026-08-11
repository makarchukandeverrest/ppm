public with sharing class RecordFieldSelector {
    public class SelectorException extends Exception {
    }

    private static final Integer FIELDS_PER_QUERY = 40;

    public static Map<Id, Map<String, Object>> getFieldValues(
        String objectApiName,
        List<Id> recordIds,
        List<String> fieldNames
    ) {
        Map<Id, Map<String, Object>> valuesByRecordId = new Map<Id, Map<String, Object>>();

        if (String.isBlank(objectApiName) || recordIds == null || recordIds.isEmpty()) {
            return valuesByRecordId;
        }

        Schema.DescribeSObjectResult objectDescribe = SchemaService.getDescribe(objectApiName);
        if (objectDescribe == null) {
            throw new SelectorException('Unknown object: ' + objectApiName);
        }

        if (!objectDescribe.isAccessible()) {
            throw new SelectorException('You do not have permission to read ' + objectDescribe.getLabel() + ' records.');
        }

        List<String> queryFields = SchemaService.getReadableFieldNames(objectApiName, fieldNames);
        if (queryFields.isEmpty()) {
            return valuesByRecordId;
        }

        for (List<String> chunkFields : chunk(queryFields, FIELDS_PER_QUERY)) {
            mergeChunk(valuesByRecordId, objectDescribe.getName(), chunkFields, recordIds);
        }

        return valuesByRecordId;
    }

    private static void mergeChunk(
        Map<Id, Map<String, Object>> valuesByRecordId,
        String canonicalObjectName,
        List<String> chunkFields,
        List<Id> recordIds
    ) {
        String soql = 'SELECT ' + String.join(chunkFields, ',') + ' FROM ' + canonicalObjectName + ' WHERE Id IN :recordIds';

        List<SObject> records = Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'recordIds' => recordIds },
            AccessLevel.USER_MODE
        );

        for (SObject record : records) {
            Id recordId = (Id) record.get('Id');
            Map<String, Object> values = valuesByRecordId.get(recordId);
            if (values == null) {
                values = new Map<String, Object>();
                valuesByRecordId.put(recordId, values);
            }

            for (String fieldName : chunkFields) {
                values.put(fieldName, record.get(fieldName));
            }
        }
    }

    private static List<List<String>> chunk(List<String> values, Integer chunkSize) {
        List<List<String>> chunks = new List<List<String>>();

        for (Integer startIndex = 0; startIndex < values.size(); startIndex += chunkSize) {
            Integer endIndex = Math.min(startIndex + chunkSize, values.size());
            List<String> current = new List<String>();
            for (Integer index = startIndex; index < endIndex; index++) {
                current.add(values[index]);
            }
            chunks.add(current);
        }

        return chunks;
    }
}
