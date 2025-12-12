public class ItemsSharePointMockProvider extends SoqlStubProvider {
    public override List<SObject> handleSoqlQuery(
        SObjectType sobjectType, 
        String rawQuery, 
        Map<String, Object> binds
    ) {
        if (sobjectType == Items_SharePoint__x.SObjectType) {

            Map<String, Object> row = new Map<String, Object>{
                'Id'        => 'x02WB00000BcKrBYAV',
                'Name__c'   => 'Test Account - TestFile.pdf',
                'UniqueId__c' => '{da2c3ea5-3954-44ee-a81e-9f2c31dfbfb8}',
                'Path__c' => 'https://premierswim.sharepoint.com/sites/Salesforce/Commercial Bids/2025-2026 Bids/Customer A/Customer A-2025-2026 Bids-Customer A 9835 A--Welcome Letter.pdf',
                'MimeType__c' => 'application/pdf',
                'CreationDate__c' => DateTime.now(),
                'IsFolder__c' => false,
                'ExternalId' => 'ext-test-001'
            };

            Items_SharePoint__x rec = (Items_SharePoint__x) Test.createStubQueryRow(sobjectType, row);
            return new List<SObject>{ rec };
        }
        return null;
    }
}