public with sharing class UnifiedActivityController {
    @AuraEnabled
    public static UnifiedActivityModels.ActivityPageResult getUnifiedActivities(
        Id recordId,
        String sortDirection,
        Integer pageSize,
        Integer offset,
        String activityType,
        String searchTerm,
        String relatedRecordConfig,
        String currentRecordLabel
    ) {
        return new UnifiedActivityService().getUnifiedActivities(
            recordId,
            sortDirection,
            pageSize,
            offset,
            activityType,
            searchTerm,
            relatedRecordConfig,
            currentRecordLabel
        );
    }

    @AuraEnabled
    public static void createChatterPost(Id recordId, String body, List<String> imageContentVersionIds) {
        new UnifiedActivityChatterService().createChatterPost(recordId, body, imageContentVersionIds);
    }
}
