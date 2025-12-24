trigger ItemsSharePointTrigger on Items_SharePoint__ChangeEvent(after insert) {
    // System.debug('🔥 ItemsSharePointTrigger fired!');

    // Set<Id> ids = new Set<Id>();
    // for(Items_SharePoint__ChangeEvent e : Trigger.new){
    //     System.debug('🔄 Processing ChangeEvent: ' + e);
    //     if(e.ChangeEventHeader.getChangeType() != 'DELETE'){
    //         List<Id> recordIds = e.ChangeEventHeader.getRecordIds();
    //         System.debug('📌 RecordIds from ChangeEvent: ' + recordIds);
    //         ids.addAll(recordIds);
    //     }
    // }

    // if (!ids.isEmpty()) {
    //     System.debug('✅ Final list of record Ids to query: ' + ids);

    //     // Query SharePoint items
    //     List<Items_SharePoint__x> objects = [
    //         SELECT Id, IsFolder__c, Name__c, MimeType__c, DownloadUrl__c
    //         FROM Items_SharePoint__x
    //         WHERE Id IN :ids
    //     ];

    //     System.debug('📦 Queried SharePoint Items: ' + objects);

    //     if (!objects.isEmpty()) {
    //         // Extract potential account names from SharePoint items
    //         Set<String> potentialAccountNames = new Set<String>();
    //         for (Items_SharePoint__x item : objects) {
    //             // Remove file extension if present to get clean name
    //             String cleanName = item.Name__c.substringBeforeLast('.');
    //             potentialAccountNames.add(cleanName);
    //         }

    //         // Find matching accounts by name
    //         Map<String, List<Account>> accountsByName = new Map<String, List<Account>>();
    //         for (Account acc : [
    //             SELECT Id, Name
    //             FROM Account
    //             WHERE Name IN :potentialAccountNames
    //         ]) {
    //             if (!accountsByName.containsKey(acc.Name)) {
    //                 accountsByName.put(acc.Name, new List<Account>());
    //             }
    //             accountsByName.get(acc.Name).add(acc);
    //         }

    //         // Build our map of Account IDs to SharePoint items
    //         Map<Id, List<Items_SharePoint__x>> recordsToItemsMap = new Map<Id, List<Items_SharePoint__x>>();

    //         for (Items_SharePoint__x item : objects) {
    //             String cleanName = item.Name__c.substringBeforeLast('.');

    //             if (accountsByName.containsKey(cleanName)) {
    //                 for (Account acc : accountsByName.get(cleanName)) {
    //                     if (!recordsToItemsMap.containsKey(acc.Id)) {
    //                         recordsToItemsMap.put(acc.Id, new List<Items_SharePoint__x>());
    //                     }
    //                     recordsToItemsMap.get(acc.Id).add(item);
    //                 }
    //             }
    //         }

    //         System.debug('🗺️ Account to SharePoint Items Map: ' + recordsToItemsMap);

    //         if (!recordsToItemsMap.isEmpty()) {
    //             ContentVersionFromItemsSharePoint share = new ContentVersionFromItemsSharePoint(recordsToItemsMap);
    //         } else {
    //             System.debug('⚠️ No matching accounts found for SharePoint items');
    //         }
    //     }
    // } else {
    //     System.debug('⚠️ No non-deleted change events found. Nothing to process.');
    // }
}
