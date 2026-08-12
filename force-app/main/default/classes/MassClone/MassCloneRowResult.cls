public with sharing class MassCloneRowResult {
    @AuraEnabled
    public Integer rowIndex;

    @AuraEnabled
    public String sourceId;

    @AuraEnabled
    public String sourceName;

    @AuraEnabled
    public String recordId;

    @AuraEnabled
    public Boolean isSuccess;

    @AuraEnabled
    public String errorMessage;

    public MassCloneRowResult(MassClonePayload.Item item, Integer index) {
        this.rowIndex = index;
        this.sourceId = item.sourceId;
        this.sourceName = item.getLabel(index);
        this.isSuccess = false;
    }

    public static MassCloneRowResult failure(MassClonePayload.Item item, Integer index, String errorMessage) {
        MassCloneRowResult row = new MassCloneRowResult(item, index);
        row.errorMessage = errorMessage;
        return row;
    }

    public String getLabelledMessage() {
        return sourceName + ': ' + errorMessage;
    }
}
