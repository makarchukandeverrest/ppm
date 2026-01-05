public with sharing class FileWrapper {
    @AuraEnabled public Id Id;
    @AuraEnabled public Id ContentDocumentId;
    @AuraEnabled public String Title;
    @AuraEnabled public Boolean ToSent;
    @AuraEnabled public String FileExtension;

    public FileWrapper(ContentVersion cv) {
        this.Id = cv.Id;
        this.ContentDocumentId = cv.ContentDocumentId;
        this.Title = cv.Title;
        this.ToSent = cv.To_Sent__c;
        this.FileExtension = cv.FileExtension;
    }
}