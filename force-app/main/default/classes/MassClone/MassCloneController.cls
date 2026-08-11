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

        @InvocableVariable(label='Row Results')
        @AuraEnabled
        public List<MassCloneRowResult> rowResults;
    }

    @InvocableMethod(
        label='Create Mass Clone Records'
        description='Inserts records from JSON payloads produced by massCloneBase'
        category='Mass Clone'
    )
    public static List<CreateResult> createRecords(List<CreateRequest> requests) {
        List<CreateResult> results = new List<CreateResult>();

        if (requests == null || requests.isEmpty()) {
            results.add(buildErrorResult('No create request was provided.'));
            return results;
        }

        for (CreateRequest request : requests) {
            results.add(
                toCreateResult(
                    MassCloneService.createRecords(request.objectApiName, request.clonePayloadJson)
                )
            );
        }

        return results;
    }

    @AuraEnabled
    public static CreateResult createCloneRecords(String objectApiName, String clonePayloadJson) {
        return toCreateResult(MassCloneService.createRecords(objectApiName, clonePayloadJson));
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

        try {
            return JSON.serialize(
                RecordFieldSelector.getFieldValues(objectApiName, recordIds, fieldNames)
            );
        } catch (RecordFieldSelector.SelectorException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'MassCloneController.getRecordFieldValuesJson failed: ' + ex + '\n' + ex.getStackTraceString()
            );
            throw new AuraHandledException('Unable to load source records: ' + ex.getMessage());
        }
    }

    private static CreateResult toCreateResult(MassCloneService.Result serviceResult) {
        CreateResult result = new CreateResult();
        result.createdRecordIds = serviceResult.createdRecordIds;
        result.successCount = serviceResult.successCount;
        result.failureCount = serviceResult.failureCount;
        result.errorMessage = serviceResult.errorMessage;
        result.rowResults = serviceResult.rowResults;
        return result;
    }

    private static CreateResult buildErrorResult(String message) {
        CreateResult result = new CreateResult();
        result.createdRecordIds = new List<String>();
        result.successCount = 0;
        result.failureCount = 0;
        result.errorMessage = message;
        result.rowResults = new List<MassCloneRowResult>();
        return result;
    }
}
