public with sharing class ContractBidLabelsFiller {
  private static final String NEW_RECORD_CREATED = 'New record created';
  private static final String NEED_VERIFICATION_LABEL = 'Need Verification';
  private static final String INFO_VERIFIED_LABEL = 'info verified';
  private static final String VERIFY_CONTACT_INFO_SUBJECT = 'Verify contact info';
  private static final String TASK_STATUS_COMPLETED = 'Completed';
  private static final List<String> DEFAULT_LABELS = new List<String>{
    'Contract Created'
  };

  public static void applyNeedVerificationLabelOnTaskCreate(
    List<Task> newTasks
  ) {
    Set<Id> bidIds = collectVerifyContactBidIds(newTasks, null, false);
    addLabel(bidIds, NEED_VERIFICATION_LABEL);
  }

  public static void applyInfoVerifiedLabelOnTaskComplete(
    List<Task> newTasks,
    Map<Id, Task> oldMap
  ) {
    Set<Id> bidIds = collectVerifyContactBidIds(newTasks, oldMap, true);
    mutateLabels(
      bidIds,
      new Set<String>{ INFO_VERIFIED_LABEL },
      new Set<String>{ NEED_VERIFICATION_LABEL }
    );
  }

  public static void addLabel(Set<Id> bidIds, String labelValue) {
    if (String.isBlank(labelValue)) {
      return;
    }
    mutateLabels(bidIds, new Set<String>{ labelValue.trim() }, null);
  }

  public static void fillLabels(List<Contract_Bid__c> bids) {
    for (Contract_Bid__c bid : bids) {
      Set<String> labels = splitLabels(bid.Label__c);
      labels.addAll(DEFAULT_LABELS);
      bid.Label__c = joinLabels(labels);
    }
  }

  public static void replacePreviousYearLabels(List<Contract_Bid__c> newBids) {
    Set<Id> customerIds = new Set<Id>();
    for (Contract_Bid__c bid : newBids) {
      if (bid.Customer__c != null) {
        customerIds.add(bid.Customer__c);
      }
    }
    if (customerIds.isEmpty()) {
      return;
    }

    List<Contract_Bid__c> oldBids = [
      SELECT Id, Name, Customer__c, Contract_Year__c, Label__c
      FROM Contract_Bid__c
      WHERE Customer__c IN :customerIds AND Id NOT IN :newBids
    ];

    List<Contract_Bid__c> bidsToUpdate = new List<Contract_Bid__c>();
    for (Contract_Bid__c newBid : newBids) {
      String prevYear = previousYear(yearOf(newBid));
      if (prevYear == null) {
        continue;
      }
      for (Contract_Bid__c oldBid : oldBids) {
        if (
          oldBid.Customer__c == newBid.Customer__c &&
          yearOf(oldBid) == prevYear
        ) {
          oldBid.Label__c = NEW_RECORD_CREATED;
          bidsToUpdate.add(oldBid);
        }
      }
    }
    if (!bidsToUpdate.isEmpty()) {
      update bidsToUpdate;
    }
  }

  private static void mutateLabels(
    Set<Id> bidIds,
    Set<String> labelsToAdd,
    Set<String> labelsToRemove
  ) {
    if (bidIds == null || bidIds.isEmpty()) {
      return;
    }
    if (
      (labelsToAdd == null || labelsToAdd.isEmpty()) &&
      (labelsToRemove == null || labelsToRemove.isEmpty())
    ) {
      return;
    }

    List<Contract_Bid__c> bids = [
      SELECT Id, Label__c
      FROM Contract_Bid__c
      WHERE Id IN :bidIds
    ];
    List<Contract_Bid__c> bidsToUpdate = new List<Contract_Bid__c>();
    for (Contract_Bid__c bid : bids) {
      Set<String> labels = splitLabels(bid.Label__c);
      Boolean changed = false;

      if (labelsToRemove != null) {
        for (String labelToRemove : labelsToRemove) {
          if (labels.remove(labelToRemove)) {
            changed = true;
          }
        }
      }
      if (labelsToAdd != null) {
        for (String labelToAdd : labelsToAdd) {
          if (String.isBlank(labelToAdd)) {
            continue;
          }
          if (labels.add(labelToAdd)) {
            changed = true;
          }
        }
      }

      if (!changed) {
        continue;
      }
      bid.Label__c = joinLabels(labels);
      bidsToUpdate.add(bid);
    }
    if (!bidsToUpdate.isEmpty()) {
      update bidsToUpdate;
    }
  }

  private static Set<Id> collectVerifyContactBidIds(
    List<Task> newTasks,
    Map<Id, Task> oldMap,
    Boolean requireNewlyCompleted
  ) {
    Set<Id> bidIds = new Set<Id>();
    if (newTasks == null || newTasks.isEmpty()) {
      return bidIds;
    }

    for (Task taskRecord : newTasks) {
      if (requireNewlyCompleted) {
        if (oldMap == null) {
          continue;
        }
        Task oldTask = oldMap.get(taskRecord.Id);
        if (oldTask == null) {
          continue;
        }
        if (
          taskRecord.Status != TASK_STATUS_COMPLETED ||
          oldTask.Status == TASK_STATUS_COMPLETED
        ) {
          continue;
        }
      }
      if (taskRecord.Subject != VERIFY_CONTACT_INFO_SUBJECT) {
        continue;
      }
      if (
        taskRecord.WhatId == null ||
        taskRecord.WhatId.getSObjectType() != Contract_Bid__c.SObjectType
      ) {
        continue;
      }
      bidIds.add(taskRecord.WhatId);
    }
    return bidIds;
  }

  private static Set<String> splitLabels(String labelValue) {
    Set<String> labels = new Set<String>();
    if (String.isNotBlank(labelValue)) {
      labels.addAll(labelValue.split(';'));
    }
    return labels;
  }

  private static String joinLabels(Set<String> labels) {
    return String.join(new List<String>(labels), ';');
  }

  private static String yearOf(Contract_Bid__c bid) {
    if (String.isNotBlank(bid.Name)) {
      Matcher matcher = Pattern.compile('(\\d{4})\\s*-\\s*(\\d{4})$')
        .matcher(bid.Name.trim());
      if (matcher.find()) {
        return matcher.group(1) + '-' + matcher.group(2);
      }
    }
    return bid.Contract_Year__c;
  }

  private static String previousYear(String year) {
    if (
      String.isBlank(year) ||
      year.length() < 4 ||
      !year.substring(0, 4).isNumeric()
    ) {
      return null;
    }
    Integer startYear = Integer.valueOf(year.substring(0, 4));
    return (startYear - 1) + '-' + startYear;
  }
}
