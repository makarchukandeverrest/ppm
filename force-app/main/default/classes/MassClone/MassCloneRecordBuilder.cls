public with sharing class MassCloneRecordBuilder {
    public class BuildOutcome {
        public List<SObject> records = new List<SObject>();
        public List<MassCloneRowResult> pendingRows = new List<MassCloneRowResult>();
        public List<MassCloneRowResult> failures = new List<MassCloneRowResult>();
    }

    public static BuildOutcome build(String objectApiName, List<MassClonePayload.Item> items) {
        BuildOutcome outcome = new BuildOutcome();
        Schema.SObjectType objectType = SchemaService.getSObjectType(objectApiName);
        Map<String, String> requiredFields = SchemaService.getRequiredCreatableFields(objectApiName);

        for (Integer index = 0; index < items.size(); index++) {
            MassClonePayload.Item item = items[index];

            if (!item.hasFields()) {
                outcome.failures.add(MassCloneRowResult.failure(item, index, 'no field values to create.'));
                continue;
            }

            List<String> conversionErrors = new List<String>();
            SObject record = buildRecord(objectApiName, objectType, item, conversionErrors);

            if (!conversionErrors.isEmpty()) {
                outcome.failures.add(MassCloneRowResult.failure(item, index, String.join(conversionErrors, ' ')));
                continue;
            }

            List<String> missingRequiredFields = findMissingRequiredFields(record, requiredFields);
            if (!missingRequiredFields.isEmpty()) {
                outcome.failures.add(
                    MassCloneRowResult.failure(
                        item,
                        index,
                        'missing required field(s): ' + String.join(missingRequiredFields, ', ')
                    )
                );
                continue;
            }

            outcome.records.add(record);
            outcome.pendingRows.add(new MassCloneRowResult(item, index));
        }

        return outcome;
    }

    private static SObject buildRecord(
        String objectApiName,
        Schema.SObjectType objectType,
        MassClonePayload.Item item,
        List<String> conversionErrors
    ) {
        SObject record = objectType.newSObject();

        for (String fieldName : item.fields.keySet()) {
            Schema.DescribeFieldResult describe = SchemaService.getFieldDescribe(objectApiName, fieldName);

            if (describe == null || !describe.isCreateable()) {
                continue;
            }

            try {
                Object convertedValue = SObjectFieldConverter.convert(item.fields.get(fieldName), describe);

                if (convertedValue != null) {
                    record.put(describe.getName(), convertedValue);
                }
            } catch (SObjectFieldConverter.ConversionException ex) {
                conversionErrors.add(ex.getMessage());
            }
        }

        return record;
    }

    private static List<String> findMissingRequiredFields(SObject record, Map<String, String> requiredFields) {
        Set<String> populatedFields = record.getPopulatedFieldsAsMap().keySet();
        List<String> missingLabels = new List<String>();

        for (String fieldName : requiredFields.keySet()) {
            if (!populatedFields.contains(fieldName)) {
                missingLabels.add(requiredFields.get(fieldName));
            }
        }

        missingLabels.sort();
        return missingLabels;
    }
}
