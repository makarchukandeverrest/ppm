public with sharing class EmailMessageTriggerHandler extends TriggerHandler {
  Map<Id, EmailMessage> newMap;
  Map<Id, EmailMessage> oldMap;

  public EmailMessageTriggerHandler() {
    this.newMap = (Map<Id, EmailMessage>) Trigger.newMap;
    this.oldMap = (Map<Id, EmailMessage>) Trigger.oldMap;
  }

  protected override void afterUpdate() {
    System.debug('=== EmailMessageTriggerHandler.afterUpdate START ===');

    List<EmailMessage> bouncedEmails = new List<EmailMessage>();

    for (EmailMessage em : newMap.values()) {
        EmailMessage oldEm = oldMap.get(em.Id);

        System.debug(
            'EmailMessage ' + em.Id +
            ' IsBounced old=' + (oldEm != null ? oldEm.IsBounced : null) +
            ' new=' + em.IsBounced +
            ' ToAddress=' + em.ToAddress
        );

        if (em.IsBounced == true && (oldEm == null || oldEm.IsBounced != true)) {
            System.debug('>>> BOUNCE DETECTED for EmailMessage ' + em.Id);
            bouncedEmails.add(em);
        }
    }

    if (!bouncedEmails.isEmpty()) {
        BounceEmailFromEmailMessageHandler.handle(bouncedEmails);
    }

    System.debug(
        '=== EmailMessageTriggerHandler.afterUpdate END. Bounced=' +
        bouncedEmails.size() +
        ' ==='
    );
}

protected override void afterInsert() {
    List<EmailMessage> docuSignContractEmails = new List<EmailMessage>();
    List<EmailMessage> docuSignProposalEmails = new List<EmailMessage>();

    for (EmailMessage em : newMap.values()) {
        if (em == null) continue;

        String fromAddress = em.FromAddress;
        String subject     = em.Subject;

        if (fromAddress != null && subject != null
            && fromAddress.contains('@docusign.net')
            && subject.contains('Completed:')
            && em.HasAttachment == true) {
                if(!em.Subject.contains('Premier Swim Proposal')){
                    docuSignContractEmails.add(em);
                }else{
                    docuSignProposalEmails.add(em);
                }
        }
    }

    if (!docuSignContractEmails.isEmpty()) {
        DocuSignSignedFileAssigner.assignContractDocuments(docuSignContractEmails);
    }
}


}