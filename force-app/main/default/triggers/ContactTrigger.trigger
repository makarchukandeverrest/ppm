trigger ContactTrigger on Contact(after update) {
  TriggerHandler handler = new ContactTriggerHandler();
  handler.run();
}