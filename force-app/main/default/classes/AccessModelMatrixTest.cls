@IsTest
private class AccessModelMatrixTest {
  @IsTest
  static void matrix_checks() {
    // TM may exist but be inactive after sandbox refresh — activate for matrix DML.
    List<User> inactiveAccess = [
      SELECT Id, Username
      FROM User
      WHERE Username LIKE 'access.%@premierswim.com.dev' AND IsActive = FALSE
    ];
    for (User u : inactiveAccess) {
      u.IsActive = true;
    }
    if (!inactiveAccess.isEmpty()) {
      update inactiveAccess;
    }

    Map<String, User> users = new Map<String, User>();
    for (User u : [
      SELECT Id, Username, UserRole.DeveloperName
      FROM User
      WHERE Username LIKE 'access.%@premierswim.com.dev' AND IsActive = TRUE
    ]) {
      users.put(u.Username, u);
    }
    System.assertEquals(
      5,
      users.size(),
      'Expected 5 access.* test users (tm/rm/ct/ld/sv). Missing: ' +
      missingAccessUsernames(users.keySet())
    );

    Account acc = new Account(Name = 'Access Model Matrix Customer');
    insert acc;
    Contract_Bid__c bid = new Contract_Bid__c(
      Name = 'Access Model Matrix Bid',
      Customer__c = acc.Id,
      Stage__c = 'Contact Made'
    );
    insert bid;
    bid = [
      SELECT
        Id,
        Stage__c,
        Price_Adjustment__c,
        Version__c,
        How_Many_Peak_Lifeguards__c,
        How_many_school_lifeguards__c
      FROM Contract_Bid__c
      WHERE Id = :bid.Id
    ];
    acc = [SELECT Id, Regional_Manager__c FROM Account WHERE Id = :acc.Id];

    runRole(
      'TM',
      users.get('access.tm@premierswim.com.dev'),
      bid,
      acc,
      true,
      true,
      true,
      true,
      true,
      true
    );
    resetBidStage(bid);
    runRole(
      'RM',
      users.get('access.rm@premierswim.com.dev'),
      bid,
      acc,
      true,
      false,
      true,
      false, // only TM has Change_Customer_Regional_Manager
      false,
      true
    );
    resetBidStage(bid);
    runRole(
      'CT',
      users.get('access.ct@premierswim.com.dev'),
      bid,
      acc,
      true,
      true,
      true, // VR allows Closed Lost for non-Lead/RM (DocuSign/automation path)
      false,
      false,
      true
    );
    resetBidStage(bid);
    runRole(
      'LD',
      users.get('access.ld@premierswim.com.dev'),
      bid,
      acc,
      true,
      false,
      true,
      false,
      false,
      false
    );
    resetBidStage(bid);
    runRole(
      'SV',
      users.get('access.sv@premierswim.com.dev'),
      bid,
      acc,
      false,
      false,
      false,
      false,
      false,
      false
    );
  }

  private static void resetBidStage(Contract_Bid__c bid) {
    User actor = AccessModelTestHelper.ensureAutomationUser();
    System.runAs(actor) {
      update new Contract_Bid__c(
        Id = bid.Id,
        Stage__c = 'Contact Made',
        Lost_Reason__c = null
      );
    }
    bid.Stage__c = 'Contact Made';
  }

  private static String missingAccessUsernames(Set<String> found) {
    List<String> expected = new List<String>{
      'access.tm@premierswim.com.dev',
      'access.rm@premierswim.com.dev',
      'access.ct@premierswim.com.dev',
      'access.ld@premierswim.com.dev',
      'access.sv@premierswim.com.dev'
    };
    List<String> missing = new List<String>();
    for (String username : expected) {
      if (!found.contains(username)) {
        missing.add(username);
      }
    }
    return String.join(missing, ', ');
  }

  private static void runRole(
    String role,
    User u,
    Contract_Bid__c bidBefore,
    Account accBefore,
    Boolean expectBidAccess,
    Boolean expectPricingEdit,
    Boolean expectStageLostOk,
    Boolean expectChangeRm,
    Boolean expectStageAllPerm,
    Boolean expectMassSend
  ) {
    System.assertNotEquals(null, u, role + ' user missing');

    // Own the customer so role DML is not blocked by sharing.
    update new Account(Id = accBefore.Id, OwnerId = u.Id);

    System.runAs(u) {
      Boolean bidAccess = Contract_Bid__c.SObjectType.getDescribe()
        .isAccessible();
      Boolean pricingEdit = Contract_Bid__c.Price_Adjustment__c.getDescribe()
        .isUpdateable();
      Boolean versionEdit = Contract_Bid__c.Version__c.getDescribe()
        .isUpdateable();
      Boolean peakEdit = Contract_Bid__c.How_Many_Peak_Lifeguards__c.getDescribe()
        .isUpdateable();
      Boolean stageAll = FeatureManagement.checkPermission(
        'Change_Bid_Stage_All'
      );
      Boolean changeRmPerm = FeatureManagement.checkPermission(
        'Change_Customer_Regional_Manager'
      );
      Boolean massSend = FeatureManagement.checkPermission(
        'Mass_Contract_Send'
      );
      Boolean bypass = FeatureManagement.checkPermission(
        'Bypass_Bid_Stage_Validation'
      );

      System.assertEquals(
        expectBidAccess,
        bidAccess,
        role + ' Contract Bid accessible'
      );
      System.assertEquals(
        expectPricingEdit,
        pricingEdit,
        role + ' Price_Adjustment editable'
      );
      System.assertEquals(
        expectPricingEdit,
        versionEdit,
        role + ' Version editable'
      );
      System.assertEquals(
        expectPricingEdit,
        peakEdit,
        role + ' Peak guards editable'
      );
      System.assertEquals(
        expectStageAllPerm,
        stageAll,
        role + ' Change_Bid_Stage_All'
      );
      System.assertEquals(
        expectChangeRm,
        changeRmPerm,
        role + ' Change RM perm'
      );
      System.assertEquals(
        expectMassSend,
        massSend,
        role + ' Mass_Contract_Send'
      );
      System.assertEquals(false, bypass, role + ' must not have Bypass');

      if (bidAccess) {
        Boolean pricingDmlOk = tryPricingUpdate(bidBefore);
        System.assertEquals(
          expectPricingEdit,
          pricingDmlOk,
          role + ' pricing DML'
        );

        String stageLostError = tryStageLost(bidBefore);
        Boolean stageLostOk = stageLostError == null;
        System.assertEquals(
          expectStageLostOk,
          stageLostOk,
          role +
            ' stage Closed Lost DML' +
            (stageLostOk ? '' : ': ' + stageLostError)
        );
      }

      String rmDmlError = tryChangeRm(accBefore, u.Id);
      Boolean rmDmlOk = rmDmlError == null;
      System.assertEquals(
        expectChangeRm,
        rmDmlOk,
        role + ' change RM DML' + (rmDmlOk ? '' : ': ' + rmDmlError)
      );
    }
  }

  private static Boolean tryPricingUpdate(Contract_Bid__c bidBefore) {
    try {
      Decimal nextVal = bidBefore.Price_Adjustment__c == null
        ? 1
        : bidBefore.Price_Adjustment__c + 0.01;
      update new Contract_Bid__c(
        Id = bidBefore.Id,
        Price_Adjustment__c = nextVal
      );
      update new Contract_Bid__c(
        Id = bidBefore.Id,
        Price_Adjustment__c = bidBefore.Price_Adjustment__c
      );
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  /** @return null on success; revert is done by resetBidStage between roles */
  private static String tryStageLost(Contract_Bid__c bidBefore) {
    try {
      update new Contract_Bid__c(
        Id = bidBefore.Id,
        Stage__c = 'Closed - LOST',
        Lost_Reason__c = 'QA access test'
      );
      return null;
    } catch (Exception e) {
      return e.getMessage();
    }
  }

  /**
   * Flip Regional Manager between two active users.
   * Never set RM to null — flow "Set Owner from Regional Manager" rejects blank owner.
   * @return null on success, otherwise error message
   */
  private static String tryChangeRm(Account accBefore, Id fallbackRm) {
    try {
      List<User> accessUsers = [
        SELECT Id
        FROM User
        WHERE Username LIKE 'access.%@premierswim.com.dev' AND IsActive = TRUE
        ORDER BY Username
      ];
      Id rmOne = fallbackRm;
      Id rmTwo = fallbackRm;
      for (User accessUser : accessUsers) {
        if (rmOne == fallbackRm) {
          rmOne = accessUser.Id;
        } else if (accessUser.Id != rmOne) {
          rmTwo = accessUser.Id;
          break;
        }
      }
      if (rmOne == rmTwo) {
        return 'need two distinct access users to flip RM';
      }

      Id firstTarget = accBefore.Regional_Manager__c == rmOne ? rmTwo : rmOne;
      Id secondTarget = firstTarget == rmOne ? rmTwo : rmOne;

      update new Account(Id = accBefore.Id, Regional_Manager__c = firstTarget);
      update new Account(Id = accBefore.Id, Regional_Manager__c = secondTarget);
      accBefore.Regional_Manager__c = secondTarget;
      return null;
    } catch (Exception e) {
      return e.getMessage();
    }
  }
}
