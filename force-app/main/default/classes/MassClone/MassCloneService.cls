public with sharing class MassCloneService {
    public class Result {
        public List<String> createdRecordIds = new List<String>();
        public Integer successCount = 0;
        public Integer failureCount = 0;
        public String errorMessage;
        public List<MassCloneRowResult> rowResults = new List<MassCloneRowResult>();
    }

    public static Result createRecords(String objectApiName, String clonePayloadJson) {
        Result result = new Result();

        try {
            if (String.isBlank(objectApiName) || String.isBlank(clonePayloadJson)) {
                result.errorMessage = 'Object API name and clone payload JSON are required.';
                return result;
            }

            if (SchemaService.getSObjectType(objectApiName) == null) {
                result.errorMessage = 'Unknown object: ' + objectApiName;
                return result;
            }

            if (!SchemaService.isCreateable(objectApiName)) {
                result.errorMessage = 'You do not have permission to create ' + objectApiName + ' records.';
                return result;
            }

            List<MassClonePayload.Item> items;
            try {
                items = MassClonePayload.parse(clonePayloadJson);
            } catch (MassClonePayload.ParseException ex) {
                result.errorMessage = ex.getMessage();
                return result;
            }

            if (items.isEmpty()) {
                result.errorMessage = 'No records were found in the clone payload.';
                return result;
            }

            MassCloneRecordBuilder.BuildOutcome outcome = MassCloneRecordBuilder.build(objectApiName, items);

            if (outcome.records.isEmpty()) {
                result.failureCount = items.size();
                result.errorMessage = outcome.failures.isEmpty()
                    ? 'No createable field values were found.'
                    : summarize(outcome.failures);
            } else {
                insertRecords(outcome, result);
                result.failureCount += outcome.failures.size();
                result.errorMessage = summarize(collectFailedRows(outcome));
            }

            result.rowResults = orderRows(outcome, items.size());
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'MassCloneService.createRecords failed: ' + ex + '\n' + ex.getStackTraceString());
            result.errorMessage = ex.getMessage();
        }

        return result;
    }

    private static void insertRecords(MassCloneRecordBuilder.BuildOutcome outcome, Result result) {
        List<Database.SaveResult> saveResults = Database.insert(outcome.records, false, AccessLevel.USER_MODE);

        for (Integer index = 0; index < saveResults.size(); index++) {
            Database.SaveResult saveResult = saveResults[index];
            MassCloneRowResult row = outcome.pendingRows[index];

            if (saveResult.isSuccess()) {
                row.isSuccess = true;
                row.recordId = saveResult.getId();
                result.createdRecordIds.add(saveResult.getId());
                result.successCount++;
            } else {
                row.errorMessage = joinErrors(saveResult.getErrors());
                result.failureCount++;
            }
        }
    }

    private static List<MassCloneRowResult> collectFailedRows(MassCloneRecordBuilder.BuildOutcome outcome) {
        List<MassCloneRowResult> failedRows = new List<MassCloneRowResult>(outcome.failures);

        for (MassCloneRowResult row : outcome.pendingRows) {
            if (!row.isSuccess) {
                failedRows.add(row);
            }
        }

        return failedRows;
    }

    private static List<MassCloneRowResult> orderRows(
        MassCloneRecordBuilder.BuildOutcome outcome,
        Integer rowCount
    ) {
        Map<Integer, MassCloneRowResult> rowsByIndex = new Map<Integer, MassCloneRowResult>();
        for (MassCloneRowResult row : outcome.pendingRows) {
            rowsByIndex.put(row.rowIndex, row);
        }
        for (MassCloneRowResult row : outcome.failures) {
            rowsByIndex.put(row.rowIndex, row);
        }

        List<MassCloneRowResult> orderedRows = new List<MassCloneRowResult>();
        for (Integer index = 0; index < rowCount; index++) {
            if (rowsByIndex.containsKey(index)) {
                orderedRows.add(rowsByIndex.get(index));
            }
        }

        return orderedRows;
    }

    private static String summarize(List<MassCloneRowResult> failedRows) {
        if (failedRows.isEmpty()) {
            return null;
        }

        List<String> messages = new List<String>();
        for (MassCloneRowResult row : failedRows) {
            messages.add(row.getLabelledMessage());
        }

        return String.join(messages, ' ');
    }

    private static String joinErrors(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getMessage());
        }

        return String.join(messages, ' ');
    }
}
