public with sharing class CaseTriggerHandler extends TriggerHandler {
    List<Case> newList;
    Map<Id, Case> oldMap;

    public CaseTriggerHandler() {
        this.newList = (List<Case>) Trigger.new;
        this.oldMap = (Map<Id, Case>) Trigger.oldMap;
    }

    protected override void beforeInsert() {
        List<Case> emptyContactCases = new List<Case>();
        for (Case c : newList) {
            if (c.ContactId == null) {
                emptyContactCases.add(c);
            }
        }
        if (!emptyContactCases.isEmpty()) {
            CaseEmptyContactFiller.fillEmptyContactByCustomer(emptyContactCases);
        }
    }
}
