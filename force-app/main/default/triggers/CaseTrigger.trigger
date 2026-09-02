trigger CaseTrigger on Case (before insert, before update) {
    TriggerHandler handler = new CaseTriggerHandler();
    handler.run();
}
