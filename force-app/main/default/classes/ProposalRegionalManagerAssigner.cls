public inherited sharing class ProposalRegionalManagerAssigner {
    
    public static void assignManagers(List<Opportunity> newOppList) {
        // Collect unique order codes from opportunities
        Set<String> orderCodes = new Set<String>();
        for (Opportunity opp : newOppList) {
            if (opp.Order_Taken_By__c != null) {
                orderCodes.add(opp.Order_Taken_By__c);
            }
        }
        if (orderCodes.isEmpty()) return;
        
        // Load map from Custom Metadata instead of hardcoded values
        Map<String, List<String>> aliasToOrderCodesMap = getAliasToOrderCodesMap();
        
        // Build code -> User Id map
        Map<String, Id> codeToUserIdMap = new Map<String, Id>();
        Set<String> aliasesNeeded = new Set<String>();
        
        // Collect aliases that have mapped codes among order codes
        for (String alias : aliasToOrderCodesMap.keySet()) {
            List<String> codes = aliasToOrderCodesMap.get(alias);
            for (String code : codes) {
                if (orderCodes.contains(code)) {
                    aliasesNeeded.add(alias);
                    break;
                }
            }
        }
        if (aliasesNeeded.isEmpty()) return;
        
        // Query active Users by needed aliases and populate map for all their codes
        for (User u : [SELECT Id, Alias FROM User 
                       WHERE Alias IN :aliasesNeeded AND IsActive = true]) {
            List<String> codes = aliasToOrderCodesMap.get(u.Alias);
            if (codes != null) {
                for (String code : codes) {
                    codeToUserIdMap.put(code, u.Id);  // One User Id for multiple codes
                }
            }
        }
        
        // Assign Regional_Manager__c based on order code
        for (Opportunity opp : newOppList) {
            String code = opp.Order_Taken_By__c;
            if (code != null && codeToUserIdMap.containsKey(code)) {
                opp.Regional_Manager__c = codeToUserIdMap.get(code);
            }
        }
    }

    public static Map<String, List<String>> getAliasToOrderCodesMap() {
        Map<String, List<String>> result = new Map<String, List<String>>();
        Map<String, Alias_To_OrderCode__mdt> allMeta = Alias_To_OrderCode__mdt.getAll();

        for (Alias_To_OrderCode__mdt rec : allMeta.values()) {
            String aliasKey = rec.Label;  // Use Name/DeveloperName as alias key
            String orderCodesStr = rec.Order_Code__c;
            
            if (String.isBlank(aliasKey) || String.isBlank(orderCodesStr)) continue;
            
            // Split comma-separated codes and trim whitespace
            List<String> codes = orderCodesStr.split(',');
            for (String code : codes) {
                code = code.trim();
                if (String.isNotBlank(code)) {
                    if (!result.containsKey(aliasKey)) {
                        result.put(aliasKey, new List<String>());
                    }
                    result.get(aliasKey).add(code);
                }
            }
        }
        return result;
    }
}