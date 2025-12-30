public with sharing class ContactTriggerHandler extends TriggerHandler {
  Map<Id, Contact> newMap;
  Map<Id, Contact> oldMap;

  public ContactTriggerHandler() {
    this.newMap = (Map<Id, Contact>) Trigger.newMap;
    this.oldMap = (Map<Id, Contact>) Trigger.oldMap;
  }

  protected override void afterUpdate() {
    List<Contact> contactsWithBouncedEmail = handleEmailBounced();
    if (!contactsWithBouncedEmail.isEmpty()) {
      BounceEmailController.handleBouncedContractBidPackage(
        contactsWithBouncedEmail
      );
    }
  }

  private List<Contact> handleEmailBounced() {
    List<Contact> contactsWithNewBounce = new List<Contact>();

    for (Contact c : this.newMap.values()) {
      Contact oldContact = this.oldMap.get(c.Id);
      if (
        c.EmailBouncedDate != oldContact.EmailBouncedDate &&
        c.EmailBouncedDate != null
      ) {
        contactsWithNewBounce.add(c);
      }
    }
    return contactsWithNewBounce;
  }
}