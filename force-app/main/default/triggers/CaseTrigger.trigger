trigger CaseTrigger on Case (before insert) {
    TriggerHandler handler = new CaseTriggerHandler();
    handler.run();
}
