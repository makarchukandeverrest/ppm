public class ContentVersionTriggerHandler extends TriggerHandler {
  private List<ContentVersion> newList;
  private Map<Id, ContentVersion> oldMap;

  private static final String DOCUSIGN_COMPLETED_TOKEN = '_completed';

  private static final Set<String> TASK_TRIGGER_STATUSES = new Set<String>{
    'Sent',
    'Delivered',
    'Completed'
  };

  public ContentVersionTriggerHandler() {
    newList = (List<ContentVersion>) Trigger.new;
    oldMap = (Map<Id, ContentVersion>) Trigger.oldMap;
  }

  protected override void afterInsert() {
    List<ContentVersion> filesToLink = new List<ContentVersion>();
    for (ContentVersion cv : newList) {
      if (
        cv.Title.contains('Contract') ||
        cv.Title.contains('Bid') ||
        cv.Title.contains('Winterization')
      ) {
        filesToLink.add(cv);
      }
    }
    SharePointContentVersionAccountLinker.linkToAccounts(filesToLink);

    List<ContentVersion> completedVersions = new List<ContentVersion>();
    for (ContentVersion version : newList) {
      if (
        version.Title != null &&
        version.Title.contains(DOCUSIGN_COMPLETED_TOKEN)
      ) {
        completedVersions.add(version);
      }
    }
    if (completedVersions.isEmpty()) {
      return;
    }

    List<Id> completedIds = new List<Id>();
    for (ContentVersion version : completedVersions) {
      completedIds.add(version.Id);
    }

    try {
      if (Test.isRunningTest()) {
        DocuSignCompletedContractEmailService.sendForContentVersionIds(
          completedIds
        );
      } else {
        System.enqueueJob(new DocuSignCompletedEmailJob(completedIds), 1);
      }
    } catch (Exception e) {
    }
  }

  protected override void afterUpdate() {
    if (newList == null || newList.isEmpty()) {
      return;
    }

    List<ContentVersion> docusignChangedVersions = new List<ContentVersion>();

    for (ContentVersion newCV : newList) {
      ContentVersion oldCV = oldMap != null ? oldMap.get(newCV.Id) : null;

      String newStatus = newCV.DocuSign_Envelope_Status__c != null
        ? newCV.DocuSign_Envelope_Status__c.trim()
        : null;

      String oldStatus = oldCV != null &&
        oldCV.DocuSign_Envelope_Status__c != null
        ? oldCV.DocuSign_Envelope_Status__c.trim()
        : null;

      Boolean newToSent = newCV.To_Sent__c == true;
      Boolean oldToSent = oldCV != null && oldCV.To_Sent__c == true;

      Boolean shouldCreateTask = false;

      if (
        newStatus != null &&
        newStatus != oldStatus &&
        TASK_TRIGGER_STATUSES.contains(newStatus)
      ) {
        shouldCreateTask = true;
      }

      if (newToSent && !oldToSent) {
        shouldCreateTask = true;
      }

      if (shouldCreateTask) {
        docusignChangedVersions.add(newCV);
      }
    }

    if (docusignChangedVersions.isEmpty()) {
      return;
    }

    try {
      DocuSignNotificationService.handleEnvelopeStatusChange(
        docusignChangedVersions
      );
    } catch (Exception e) {
    }
  }
}
