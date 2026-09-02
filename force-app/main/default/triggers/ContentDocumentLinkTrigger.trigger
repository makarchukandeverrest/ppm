trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert) {
    TriggerHandler handler = new ContentDocumentLinkTriggerHandler();
    handler.run();
}
