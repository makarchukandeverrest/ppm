trigger FeedItemTrigger on FeedItem (after insert, after delete) {
    TriggerHandler handler = new FeedItemTriggerHandler();
    handler.run();
}
