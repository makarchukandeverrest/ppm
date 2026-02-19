public with sharing class WorkOrderEmailHandler implements Messaging.InboundEmailHandler {

    private static final Map<String, String> STATUS_MAP = new Map<String, String>{
        'new'                 => 'New',
        'proposal approved'   => 'Proposal Approved / WO Created',
        'wo created'          => 'Proposal Approved / WO Created',
        'sent to rm'          => 'WO Sent to RM / SM',
        'sent to sm'          => 'WO Sent to RM / SM',
        'assigned'            => 'Assigned to Service Team',
        'assigned to service' => 'Assigned to Service Team',
        'in progress'         => 'In Progress',
        'pending'             => 'Pending',
        'on hold'             => 'Pending',
        'completed'           => 'Completed',
        'done'                => 'Completed',
        'canceled'            => 'Canceled',
        'cancelled'           => 'Canceled'
    };

    public Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();

        try {
            String subject = email.subject != null ? email.subject : '';

            List<String> splittedSubject = subject.split(':');
            String woNumber = '';

            if (splittedSubject.size() > 1) {
                woNumber = splittedSubject[splittedSubject.size() - 1].trim();
            }

            if (String.isNotBlank(woNumber)) {
                processEmail(email, envelope, woNumber);
                result.success = true;
                result.message = 'Email processed, WorkOrderNumber: ' + woNumber;
            } else {
                result.success = false;
                result.message = 'WorkOrderNumber not found in subject';
            }

        } catch (Exception e) {
            result.success = false;
            result.message = 'Exception in handleInboundEmail: ' + e.getMessage();
        }

        return result;
    }

    private void processEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope,
        String woNumber
    ) {
        try {
            // 1) Найти WorkOrder
            WorkOrder woToUpdate = [
                SELECT Id, Quick_Books_WO_No__c, Status
                FROM WorkOrder
                WHERE Quick_Books_WO_No__c = :woNumber
                LIMIT 1
            ];

            // 2) Парсинг тела письма
            Map<String, String> tokens = new Map<String, String>();

            for (String line : email.plainTextBody.split('\n')) {
                line = line.trim();

                if (String.isBlank(line)) {
                    continue;
                }

                if (line.contains(':')) {
                    List<String> parts = line.split(':', 2);

                    if (parts.size() >= 2) {
                        String key = parts[0].trim();
                        String value = parts[1].trim();
                        tokens.put(key, value);
                    }
                }
            }

            // 3) Достаём Status и Comment
            String statusRaw = tokens.get('Status');
            String comment   = tokens.get('Comment');

            // 4) Маппим статус
            if (!String.isBlank(statusRaw)) {
                String statusKey = statusRaw.toLowerCase().trim();
                String picklistStatusValue = STATUS_MAP.get(statusKey);

                if (picklistStatusValue != null) {
                    woToUpdate.Status = picklistStatusValue;
                }
            }

            // 5) Создаём FeedItem из Comment
            if (!String.isBlank(comment)) {
                FeedItem fi = new FeedItem();
                fi.ParentId = woToUpdate.Id;
                fi.Body =
                    'Comment from ' + email.fromAddress + ':\n' +
                    comment;
                insert fi;
            }

            // 6) Обрабатываем вложения
            handleAttachments(email.binaryAttachments, email.textAttachments, woToUpdate.Id);

            // 7) Обновляем WorkOrder
            update woToUpdate;

        } catch (Exception e) {
            // при необходимости можно заменить на кастомный логгер/Custom Object
            // чтобы не засорять debug logs в проде [web:1][web:2]
        }
    }

    private void handleAttachments(
        List<Messaging.InboundEmail.BinaryAttachment> binaryAttachments,
        List<Messaging.InboundEmail.TextAttachment> textAttachments,
        Id parentId
    ) {
        if (parentId == null) {
            return;
        }

        List<ContentVersion> contentVersionsToInsert = new List<ContentVersion>();

        // Binary attachments
        if (binaryAttachments != null && !binaryAttachments.isEmpty()) {
            for (Messaging.InboundEmail.BinaryAttachment b : binaryAttachments) {
                if (b == null || b.body == null) {
                    continue;
                }

                ContentVersion cv = new ContentVersion();
                cv.Title        = String.isNotBlank(b.fileName) ? b.fileName : 'binary-attachment';
                cv.PathOnClient = cv.Title;
                cv.VersionData  = b.body;
                contentVersionsToInsert.add(cv);
            }
        }

        // Text attachments
        if (textAttachments != null && !textAttachments.isEmpty()) {
            for (Messaging.InboundEmail.TextAttachment t : textAttachments) {
                if (t == null || String.isBlank(t.body)) {
                    continue;
                }

                ContentVersion cv = new ContentVersion();
                cv.Title        = String.isNotBlank(t.fileName) ? t.fileName : 'text-attachment';
                cv.PathOnClient = cv.Title;
                cv.VersionData  = Blob.valueOf(t.body);
                contentVersionsToInsert.add(cv);
            }
        }

        if (contentVersionsToInsert.isEmpty()) {
            return;
        }

        insert contentVersionsToInsert;

        // перечитать, чтобы получить ContentDocumentId
        List<ContentVersion> insertedVersions = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE Id IN :contentVersionsToInsert
        ];

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();

        for (ContentVersion cv : insertedVersions) {
            if (cv.ContentDocumentId == null) {
                continue;
            }

            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.LinkedEntityId    = parentId;
            cdl.ContentDocumentId = cv.ContentDocumentId;
            cdl.ShareType         = 'V';
            cdl.Visibility        = 'AllUsers';
            links.add(cdl);
        }

        if (!links.isEmpty()) {
            insert links;
        }
    }
}
