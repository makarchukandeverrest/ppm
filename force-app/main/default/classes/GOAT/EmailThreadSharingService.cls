public inherited sharing class EmailThreadSharingService {
  public static void grantAccessToEmailThread(
    List<Email_Platform__Email_Thread__c> newList
  ) {
    Set<String> profileNames = new Set<String>{
      'System Administrator',
      'Standard User'
    };

    Map<String, Id> userEmailToId = new Map<String, Id>();
    for (User u : [
      SELECT Id, Email, Profile.Name
      FROM User
      WHERE IsActive = TRUE AND Profile.Name IN :profileNames
    ]) {
      userEmailToId.put(u.Email, u.Id);
    }

    List<Email_Platform__Email_Thread__Share> sharesToInsert = new List<Email_Platform__Email_Thread__Share>();

    List<String> thredIdentifiers = new List<String>();
    for (Email_Platform__Email_Thread__c t : newList) {
      thredIdentifiers.add(t.Email_Platform__Thread_Identifier__c);
    }

    List<EmailMessage> emailMessages = [
      SELECT Id, FromAddress, ToAddress, CcAddress, BccAddress, ThreadIdentifier
      FROM EmailMessage
      WHERE ThreadIdentifier IN :thredIdentifiers
    ];

    Map<String, List<String>> emailAddresses = new Map<String, List<String>>();

    for (EmailMessage e : emailMessages) {
      emailAddresses.put(
        e.ThreadIdentifier,
        new List<String>{
          e.FromAddress,
          e.ToAddress,
          e.CcAddress,
          e.BccAddress
        }
      );
    }

    for (Email_Platform__Email_Thread__c t : newList) {
      List<String> adresses = emailAddresses.get(
        t.Email_Platform__Thread_Identifier__c
      );
      for (String a : adresses) {
        Id targetUserId = userEmailToId.get(a);
        if (targetUserId != null) {
          Email_Platform__Email_Thread__Share sh = new Email_Platform__Email_Thread__Share();
          sh.ParentId = t.Id;
          sh.UserOrGroupId = targetUserId;
          sh.AccessLevel = 'Read';
          sh.RowCause = Schema.Email_Platform__Email_Thread__Share.RowCause.Email_Access__c;
          sharesToInsert.add(sh);
        }
      }
    }

    if (!sharesToInsert.isEmpty()) {
      insert sharesToInsert;
    }
  }
}
