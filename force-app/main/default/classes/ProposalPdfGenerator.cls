public with sharing class ProposalPdfGenerator {

    /**
     * Generate PDF for an Opportunity (Proposal) by ID
     * @param opportunityId - ID of the Opportunity record
     * @param pdfTitle - Title for the generated PDF file
     * @return ContentDocumentId of the generated PDF file
     */
    @AuraEnabled
    public static Id generatePdfFromOpportunity(Id opportunityId, String pdfTitle) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity ID cannot be null.');
        }

        if (String.isBlank(pdfTitle)) {
            pdfTitle = 'Proposal PDF';
        }

        // Fetch Opportunity data
        Opportunity opp = [
            SELECT Id, Name, CloseDate, StageName, Amount
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        // Build HTML content for PDF
        String htmlContent = buildHtmlForProposal(opp);

        // Convert HTML to PDF (Spring '26 feature)
        Blob pdfBlob = Blob.toPdf(htmlContent);

        // Create ContentVersion (Salesforce File)
        ContentVersion cv = new ContentVersion();
        cv.VersionData = pdfBlob;
        cv.Title = pdfTitle;
        cv.PathOnClient = pdfTitle + '.pdf';
        cv.FirstPublishLocationId = opportunityId; // attach to Opportunity
        insert cv;

        // Query ContentDocumentId
        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        return cv.ContentDocumentId;
    }

    /**
     * Helper: Build HTML for Opportunity / Proposal PDF
     */
    private static String buildHtmlForProposal(Opportunity opp) {
        String html =
            '<!DOCTYPE html>' +
            '<html>' +
            '<head><meta charset="UTF-8">' +
            '<style>' +
            'body { font-family: Arial; font-size: 12pt; padding: 20px; }' +
            'h1 { font-size: 18pt; }' +
            'table { width: 100%; border-collapse: collapse; margin-top: 10px; }' +
            'th, td { border: 1px solid #ddd; padding: 8px; }' +
            'th { background-color: #f2f2f2; }' +
            '</style></head>' +
            '<body>' +
            '<h1>Proposal: ' + opp.Name + '</h1>' +
            '<p><strong>Stage:</strong> ' + opp.StageName + '</p>' +
            '<p><strong>Close Date:</strong> ' + opp.CloseDate + '</p>' +
            '<p><strong>Amount:</strong> $' + opp.Amount + '</p>' +
            '<hr>' +
            '<p>Thank you for considering our proposal. Please contact us if you have questions.</p>' +
            '</body>' +
            '</html>';
        return html;
    }
}