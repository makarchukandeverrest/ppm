@isTest
private class BidWorksheetControllerTest {
    
    @TestSetup
    static void makeData() {
        // Create a test Account (Customer)
        Account testCustomer = new Account(
            Name = 'Test Customer'
        );
        insert testCustomer;
        
        // Create a ContentVersion (file) with "Bid" in the title
        ContentVersion cv = new ContentVersion(
            Title = 'Bid Worksheet Test',
            PathOnClient = 'BidWorksheet.docx',
            VersionData = Blob.valueOf('Test file content'),
            IsMajorVersion = true
        );
        insert cv;
        
        // Get the ContentDocumentId
        ContentVersion insertedCV = [
            SELECT ContentDocumentId 
            FROM ContentVersion 
            WHERE Id = :cv.Id
        ];
        
        // Link the file to the Customer (Account)
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = insertedCV.ContentDocumentId,
            LinkedEntityId = testCustomer.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
    }
    
    @isTest
    static void testGetBidWorksheetsWithFiles() {
        // Get test account
        Account testCustomer = [SELECT Id FROM Account WHERE Name = 'Test Customer' LIMIT 1];
        
        Test.startTest();
        List<BidWorksheetController.FileDto> result = BidWorksheetController.getBidWorksheets(testCustomer.Id);
        Test.stopTest();
        
        // Verify results - we should find the Bid file
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Should find 1 Bid file');
        
        BidWorksheetController.FileDto dto = result[0];
        System.assertEquals('Bid Worksheet Test', dto.title, 'Title should match');
        System.assertEquals('docx', dto.fileExtension, 'Extension should be docx');
        System.assertNotEquals(null, dto.contentVersionId, 'ContentVersionId should not be null');
        System.assertNotEquals(null, dto.contentDocumentId, 'ContentDocumentId should not be null');
        System.assertNotEquals(null, dto.fileSize, 'FileSize should not be null');
        System.assertNotEquals(null, dto.lastModified, 'LastModified should not be null');
        System.assertNotEquals(null, dto.uploadedBy, 'UploadedBy should not be null');
    }
    
    @isTest
    static void testGetBidWorksheetsWithNullId() {
        Test.startTest();
        List<BidWorksheetController.FileDto> result = BidWorksheetController.getBidWorksheets(null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Should return empty list for null ID');
    }
    
    @isTest
    static void testGetBidWorksheetsNoFiles() {
        // Create a customer with no files
        Account customerNoFiles = new Account(Name = 'Customer No Files');
        insert customerNoFiles;
        
        Test.startTest();
        List<BidWorksheetController.FileDto> result = BidWorksheetController.getBidWorksheets(customerNoFiles.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Should return empty list when no files exist');
    }
    
    @isTest
    static void testFormatFileSizeBytes() {
        Test.startTest();
        String result = BidWorksheetController.formatFileSize(500);
        Test.stopTest();
        
        System.assertEquals('500 B', result, 'Should format bytes correctly');
    }
    
    @isTest
    static void testFormatFileSizeKilobytes() {
        Test.startTest();
        String result = BidWorksheetController.formatFileSize(2048);
        Test.stopTest();
        
        System.assertEquals('2 KB', result, 'Should format kilobytes correctly');
    }
    
    @isTest
    static void testFormatFileSizeMegabytes() {
        Test.startTest();
        String result = BidWorksheetController.formatFileSize(2097152);
        Test.stopTest();
        
        System.assertEquals('2 MB', result, 'Should format megabytes correctly');
    }
    
    @isTest
    static void testFormatFileSizeNull() {
        Test.startTest();
        String result = BidWorksheetController.formatFileSize(null);
        Test.stopTest();
        
        System.assertEquals('0 B', result, 'Should return 0 B for null');
    }
    
    @isTest
    static void testFormatFileSizeZero() {
        Test.startTest();
        String result = BidWorksheetController.formatFileSize(0);
        Test.stopTest();
        
        System.assertEquals('0 B', result, 'Should return 0 B for zero');
    }
    
    @isTest
    static void testFileDtoClass() {
        // Test FileDto inner class
        BidWorksheetController.FileDto dto = new BidWorksheetController.FileDto();
        dto.contentVersionId = null;
        dto.contentDocumentId = null;
        dto.title = 'Test';
        dto.fileExtension = 'docx';
        dto.fileSize = 100;
        dto.lastModified = DateTime.now();
        dto.uploadedBy = 'Test User';
        
        System.assertEquals('Test', dto.title, 'Title should be set');
        System.assertEquals('docx', dto.fileExtension, 'Extension should be set');
        System.assertEquals(100, dto.fileSize, 'FileSize should be set');
    }
}
