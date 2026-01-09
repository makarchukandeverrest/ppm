public with sharing class ProposalFileSharer {
    List<ContentVersion> newList;

    public ProposalFileSharer(List<ContentVersion> newList){
        this.newList = newList;

        shareFiles();
    }

    private void shareFiles(){
        String filter = '';
        String query = 'SELECT Id, Name FROM Account WHERE';
        List<String> conditions = new List<String>();
        
        for(ContentVersion v : newList) {
            conditions.add('Name LIKE \'%' + String.escapeSingleQuotes(v.Title) + '%\'');
        }
        
        if(!conditions.isEmpty()) {
            query += ' ' + String.join(conditions, ' OR ');
        }

        List<Account> accounts = Database.query(query);

        Map<String, Id> oppMap = new Map<String, Id>();
        for(Account a : accounts)
        {
             oppMap.put(a.Name, a.Id);
        }
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();

        for(ContentVersion v : newList){
            for(String s : oppMap.keySet()){
			System.debug(s);
                System.debug(s.containsIgnoreCase(v.Title));
                if(s.containsIgnoreCase(v.Title)){
                    ContentDocumentLink l = new ContentDocumentLink();
                    l.ContentDocumentId = v.ContentDocumentId;
                    l.LinkedEntityId = oppMap.get(s);
                    l.ShareType = 'V';
                    links.add(l);
                }
            }
        }

        insert links;
    }
}