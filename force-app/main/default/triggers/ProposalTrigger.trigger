trigger ProposalTrigger on Opportunity (before insert, after insert, before update, after update) {
    TriggerHandler handler = new ProposalTriggerHandler();
    handler.run();
}