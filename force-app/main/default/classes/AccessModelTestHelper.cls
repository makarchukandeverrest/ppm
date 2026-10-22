/**
 * Assigns access-model custom permission sets so unit tests can perform Stage /
 * Regional Manager DML that production automation covers via Bypass.
 */
@IsTest
public with sharing class AccessModelTestHelper {
  public static final String BYPASS_BID_STAGE = 'Bypass_Bid_Stage_Validation';
  public static final String CHANGE_CUSTOMER_RM = 'Change_Customer_Regional_Manager';
  public static final String AUTOMATION_ALIAS = 'accauto';

  public static void ensureAutomationPerms() {
    assignPermissionSets(
      UserInfo.getUserId(),
      new Set<String>{ BYPASS_BID_STAGE, CHANGE_CUSTOMER_RM }
    );
  }

  public static void ensureBypassBidStage() {
    assignPermissionSets(
      UserInfo.getUserId(),
      new Set<String>{ BYPASS_BID_STAGE }
    );
  }

  /**
   * Creates (or returns) an admin user with Bypass + Change RM.
   * Prefer System.runAs(this user) for DML that hits those VRs.
   */
  public static User ensureAutomationUser() {
    List<User> existing = [
      SELECT Id, Alias
      FROM User
      WHERE Alias = :AUTOMATION_ALIAS
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      assignPermissionSets(
        existing[0].Id,
        new Set<String>{ BYPASS_BID_STAGE, CHANGE_CUSTOMER_RM }
      );
      return existing[0];
    }

    Profile adminProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    String unique = String.valueOf(Datetime.now().getTime());
    User automationUser = new User(
      Alias = AUTOMATION_ALIAS,
      Email = 'access.auto.' + unique + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'AccessAuto',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = adminProfile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'access.auto.' + unique + '@ppm.test'
    );
    insert automationUser;
    assignPermissionSets(
      automationUser.Id,
      new Set<String>{ BYPASS_BID_STAGE, CHANGE_CUSTOMER_RM }
    );
    return automationUser;
  }

  public static void assignPermissionSets(
    Id userId,
    Set<String> permissionSetNames
  ) {
    if (
      userId == null ||
      permissionSetNames == null ||
      permissionSetNames.isEmpty()
    ) {
      return;
    }

    Map<String, Id> psIdByName = new Map<String, Id>();
    for (PermissionSet ps : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE Name IN :permissionSetNames
    ]) {
      psIdByName.put(ps.Name, ps.Id);
    }

    Set<Id> alreadyAssigned = new Set<Id>();
    for (PermissionSetAssignment psa : [
      SELECT PermissionSetId
      FROM PermissionSetAssignment
      WHERE AssigneeId = :userId AND PermissionSet.Name IN :permissionSetNames
    ]) {
      alreadyAssigned.add(psa.PermissionSetId);
    }

    List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
    for (String psName : permissionSetNames) {
      Id psId = psIdByName.get(psName);
      if (psId == null || alreadyAssigned.contains(psId)) {
        continue;
      }
      toInsert.add(
        new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = psId)
      );
    }
    if (toInsert.isEmpty()) {
      return;
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert toInsert;
    }
  }
}
