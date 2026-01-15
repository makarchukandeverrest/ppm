public with sharing class BidWorksheetController {
    
    private static final String LOG = '🟦 [BidWorksheet] ';
    
    /* =========================================================
       DTOs
    ========================================================= */
    
    public class FileDto {
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public Integer fileSize;
        @AuraEnabled public DateTime lastModified;
        @AuraEnabled public String uploadedBy;
    }
    
    /* =========================================================
       GET BID WORKSHEETS
    ========================================================= */
    
    @AuraEnabled(cacheable=true)
    public static List<FileDto> getBidWorksheets(Id customerId) {
        System.debug(LOG + 'getBidWorksheets START for customerId: ' + customerId);
        
        if (customerId == null) {
            return new List<FileDto>();
        }
        
        // Get ContentDocumentLinks for this Customer
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :customerId
        ];
        
        if (links.isEmpty()) {
            System.debug(LOG + 'No files found for customer');
            return new List<FileDto>();
        }
        
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            docIds.add(link.ContentDocumentId);
        }
        
        // Get current year for filtering
        Integer currentYear = Date.today().year();
        
        // Get latest versions of files that match "Bid" or "BW" pattern AND modified in current year
        // Supports both PDF/DOCX contracts and Excel worksheets
        List<ContentVersion> versions = [
            SELECT Id, Title, ContentDocumentId, FileExtension,
                   ContentSize, LastModifiedDate, CreatedBy.Name
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
            AND IsLatest = true
            AND FileExtension = 'docx'
            AND (
                Title LIKE '%Bid%' 
                OR Title LIKE '%bid%'
                OR Title LIKE '%BW%'
                OR Title LIKE '%bw%'
            )
            AND CALENDAR_YEAR(LastModifiedDate) = :currentYear
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];


        
        System.debug(LOG + 'Found ' + versions.size() + ' Bid files');
        
        List<FileDto> result = new List<FileDto>();
        for (ContentVersion cv : versions) {
            FileDto dto = new FileDto();
            dto.contentVersionId = cv.Id;
            dto.contentDocumentId = cv.ContentDocumentId;
            dto.title = cv.Title;
            dto.fileExtension = cv.FileExtension;
            dto.fileSize = Integer.valueOf(cv.ContentSize);
            dto.lastModified = cv.LastModifiedDate;
            dto.uploadedBy = cv.CreatedBy.Name;
            result.add(dto);
        }
        
        return result;
    }
    
    /* =========================================================
       HELPER: Format file size
    ========================================================= */
    
    @AuraEnabled(cacheable=true)
    public static String formatFileSize(Integer bytes) {
        if (bytes == null || bytes == 0) return '0 B';
        
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1048576) return (bytes / 1024) + ' KB';
        return (bytes / 1048576) + ' MB';
    }
}