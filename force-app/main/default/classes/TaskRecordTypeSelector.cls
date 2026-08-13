public with sharing class TaskRecordTypeSelector {
    private static final String REGIONAL_MANAGER_REQUEST_DEVELOPER_NAME = 'Regional_Manager_Request';

    private static Id recordTypeId;

    public static Id getRegionalManagerRequestRecordTypeId() {
        if (recordTypeId != null) {
            return recordTypeId;
        }

        Schema.RecordTypeInfo rtInfo = Schema.SObjectType.Task
            .getRecordTypeInfosByDeveloperName()
            .get(REGIONAL_MANAGER_REQUEST_DEVELOPER_NAME);

        recordTypeId = (rtInfo != null) ? rtInfo.getRecordTypeId() : null;
        return recordTypeId;
    }
}
