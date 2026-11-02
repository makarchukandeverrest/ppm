public with sharing class ContractBidSendCleanupService {
  private static final String STATUS_COMPLETED = 'Completed';
  private static final String SUBJECT_REQUEST_NEW_VERSION = 'Request New Version';
  private static final String SUBJECT_OPENED_UNSIGNED_PREFIX = 'Call about opened unsigned contract';
  private static final String SUBJECT_CALL_PROPERTY_PREFIX = 'Call Property Owner about Contract for ';
  private static final String SUBJECT_ONSITE_VISIT_PREFIX = 'On-site visit to ';
  private static final String SUBJECT_CONTRACT_NOT_SIGNED = 'Contract not signed';

  private static Set<Id> processedBidIds = new Set<Id>();

  public static void completeOpenFollowUpTasks(Set<Id> bidIds) {
    if (bidIds == null || bidIds.isEmpty()) {
      return;
    }

    Set<Id> pendingBidIds = new Set<Id>();
    for (Id bidId : bidIds) {
      if (bidId == null || processedBidIds.contains(bidId)) {
        continue;
      }
      processedBidIds.add(bidId);
      pendingBidIds.add(bidId);
    }
    if (pendingBidIds.isEmpty()) {
      return;
    }

    List<Task> openTasks = [
      SELECT Id, Subject
      FROM Task
      WHERE WhatId IN :pendingBidIds AND IsClosed = FALSE
    ];

    List<Task> toComplete = new List<Task>();
    for (Task taskRecord : openTasks) {
      if (!isFollowUpTask(taskRecord.Subject)) {
        continue;
      }
      toComplete.add(new Task(Id = taskRecord.Id, Status = STATUS_COMPLETED));
    }

    if (!toComplete.isEmpty()) {
      update toComplete;
    }
  }

  @TestVisible
  static Boolean isFollowUpTask(String subject) {
    if (String.isBlank(subject)) {
      return false;
    }
    String value = subject.trim();
    if (value == SUBJECT_REQUEST_NEW_VERSION) {
      return true;
    }
    if (value.startsWith(SUBJECT_OPENED_UNSIGNED_PREFIX)) {
      return true;
    }
    if (value.startsWith(SUBJECT_CALL_PROPERTY_PREFIX)) {
      return true;
    }
    if (
      value.startsWith(SUBJECT_ONSITE_VISIT_PREFIX) &&
      value.contains(SUBJECT_CONTRACT_NOT_SIGNED)
    ) {
      return true;
    }
    return false;
  }
}
