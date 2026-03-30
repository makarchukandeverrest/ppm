public inherited sharing class EmailThreadSharingService {
  private static final String DBG = 'EmailThreadSharingService.grantAccessToEmailThread';

  private static void dbg(String message) {
    System.debug(LoggingLevel.ERROR, '[' + DBG + '] ' + message);
  }

  public static void grantAccessToEmailThread(
    List<Email_Platform__Email_Thread__c> newList
  ) {
    dbg('START newList.size=' + (newList == null ? 'null' : String.valueOf(newList.size())));

    if (newList == null || newList.isEmpty()) {
      dbg('EXIT early: nothing to process');
      return;
    }

    Set<String> profileNames = new Set<String>{
      'System Administrator',
      'Standard User'
    };
    dbg('Profile filter=' + profileNames);

    Map<String, Id> userEmailToId = new Map<String, Id>();
    for (User u : [
      SELECT Id, Email, Profile.Name
      FROM User
      WHERE IsActive = TRUE AND Profile.Name IN :profileNames
    ]) {
      userEmailToId.put(u.Email, u.Id);
    }
    dbg('Active users matched (email->Id) count=' + userEmailToId.size());

    List<Email_Platform__Email_Thread__Share> sharesToInsert = new List<Email_Platform__Email_Thread__Share>();

    List<String> thredIdentifiers = new List<String>();
    for (Email_Platform__Email_Thread__c t : newList) {
      thredIdentifiers.add(t.Email_Platform__Thread_Identifier__c);
    }
    dbg('Thread identifiers collected count=' + thredIdentifiers.size());

    List<EmailMessage> emailMessages = [
      SELECT Id, FromAddress, ToAddress, CcAddress, BccAddress, ThreadIdentifier
      FROM EmailMessage
      WHERE ThreadIdentifier IN :thredIdentifiers
    ];
    dbg('EmailMessage query rows=' + emailMessages.size());

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
      dbg(
        'EmailMessage id=' +
          e.Id +
          ' ThreadIdentifier=' +
          e.ThreadIdentifier +
          ' From=' +
          e.FromAddress +
          ' To=' +
          e.ToAddress
      );
    }

    for (Email_Platform__Email_Thread__c t : newList) {
      String tid = t.Email_Platform__Thread_Identifier__c;
      List<String> adresses = emailAddresses.get(tid);

      if (adresses == null) {
        dbg(
          'Thread row id=' +
            t.Id +
            ' identifier=' +
            tid +
            ' -> NO EmailMessage in map; skip address loop'
        );
        continue;
      }

      dbg(
        'Thread row id=' +
          t.Id +
          ' identifier=' +
          tid +
          ' raw address slots=' +
          adresses.size()
      );

      for (String a : adresses) {
        if (String.isBlank(a)) {
          dbg('  skip blank address slot');
          continue;
        }
        Id targetUserId = userEmailToId.get(a);
        if (targetUserId != null) {
          dbg(
            '  SHARE candidate email=' +
              a +
              ' -> userId=' +
              targetUserId +
              ' (matched System Admin / Standard User profile list)'
          );
          Email_Platform__Email_Thread__Share sh = new Email_Platform__Email_Thread__Share();
          sh.ParentId = t.Id;
          sh.UserOrGroupId = targetUserId;
          sh.AccessLevel = 'Read';
          sh.RowCause = Schema.Email_Platform__Email_Thread__Share.RowCause.Email_Access__c;
          sharesToInsert.add(sh);
        } else {
          dbg(
            '  NO share for email=' +
              a +
              ' (no active user with that email in profile set)'
          );
        }
      }
    }

    dbg('sharesToInsert.size=' + sharesToInsert.size());
    if (!sharesToInsert.isEmpty()) {
      insert sharesToInsert;
      dbg('insert OK count=' + sharesToInsert.size());
    } else {
      dbg('no shares inserted');
    }
    dbg('END');
  }
}