public with sharing class WorkOrderEmailHandler implements Messaging.InboundEmailHandler {

    private static final Map<String, String> STATUS_MAP = new Map<String, String>{
        'new'                   => 'New',
        'proposal approved'     => 'Proposal Approved / WO Created',
        'wo created'            => 'Proposal Approved / WO Created',
        'sent to rm'            => 'WO Sent to RM / SM',
        'sent to sm'            => 'WO Sent to RM / SM',
        'assigned'              => 'Assigned to Service Team',
        'assigned to service'   => 'Assigned to Service Team',
        'in progress'           => 'In Progress',
        'pending'               => 'Pending',
        'on hold'               => 'Pending',
        'completed'             => 'Completed',
        'done'                  => 'Completed',
        'canceled'              => 'Canceled',
        'cancelled'             => 'Canceled'
    };

    public Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        System.debug('=== WorkOrderEmailHandler.handleInboundEmail START ===');
        System.debug('Email subject: ' + email.subject);
        System.debug('Email fromAddress: ' + email.fromAddress);
        System.debug('Email toAddresses: ' + String.valueOf(email.toAddresses));
        System.debug('Email CCAddresses: ' + String.valueOf(email.ccAddresses));

        try {
            String subject = email.subject != null ? email.subject : '';
            System.debug('Normalized subject: ' + subject);

            List<String> splittedSubject = subject.split(':');
            System.debug('splittedSubject size: ' + splittedSubject.size());
            System.debug('splittedSubject values: ' + String.valueOf(splittedSubject));

            String woNumber = '';
            if (splittedSubject.size() > 1) {
                woNumber = splittedSubject[splittedSubject.size() - 1].trim();
            }
            System.debug('Extracted woNumber from subject: "' + woNumber + '"');

            if (String.isNotBlank(woNumber)) {
                System.debug('woNumber is not blank, calling processEmail');
                processEmail(email, envelope, woNumber);
                result.success = true;
                result.message = 'Email processed, WorkOrderNumber: ' + woNumber;
            } else {
                System.debug('woNumber is blank, nothing to process');
                result.success = false;
                result.message = 'WorkOrderNumber not found in subject';
            }

        } catch (Exception e) {
            System.debug('ERROR in handleInboundEmail: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            result.success = false;
            result.message = 'Exception in handleInboundEmail: ' + e.getMessage();
        }

        System.debug('=== WorkOrderEmailHandler.handleInboundEmail END ===');
        return result;
    }

    private void processEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope,
        String woNumber
    ) {
        System.debug('=== processEmail START ===');
        System.debug('Incoming woNumber: "' + woNumber + '"');

        try {
            // 1) Найти WorkOrder
            WorkOrder woToUpdate = [
                SELECT Id, Quick_Books_WO_No__c, Status
                FROM WorkOrder
                WHERE Quick_Books_WO_No__c = :woNumber
                LIMIT 1
            ];
            System.debug('Found WorkOrder Id: ' + woToUpdate.Id +
                         ', Quick_Books_WO_No__c: ' + woToUpdate.Quick_Books_WO_No__c +
                         ', Status: ' + woToUpdate.Status);

            // 2) Логируем тело письма
            System.debug('email.plainTextBody: ' + email.plainTextBody);

            Map<String, String> tokens = new Map<String, String>();

            // 3) Парсим тело письма
            for (String line : email.plainTextBody.split('\n')) {
                System.debug('Raw line: "' + line + '"');
                line = line.trim();
                System.debug('Trimmed line: "' + line + '"');

                if (String.isBlank(line)) {
                    System.debug('Line is blank, skipping');
                    continue;
                }

                if (line.contains(':')) {
                    List<String> parts = line.split(':', 2);
                    System.debug('parts size: ' + parts.size() + ', parts: ' + String.valueOf(parts));

                    if (parts.size() >= 2) {
                        String key = parts[0].trim();
                        String value = parts[1].trim();
                        System.debug('Parsed key: "' + key + '", value: "' + value + '"');
                        tokens.put(key, value);
                    } else {
                        System.debug('Line contains ":" but split returned less than 2 parts, skipping');
                    }
                } else {
                    System.debug('Line does not contain ":", skipping');
                }
            }

            System.debug('Final tokens map: ' + String.valueOf(tokens));

            // 4) Достаём Status и Comment
            String statusRaw   = tokens.get('Status');
            String comment     = tokens.get('Comment');

            System.debug('Raw Status from tokens: "' + statusRaw + '"');
            System.debug('Raw Comment from tokens: "' + comment + '"');

            // 5) Маппим человеческий статус -> picklist
            if (!String.isBlank(statusRaw)) {
                String statusKey = statusRaw.toLowerCase().trim();
                System.debug('Status key (lowercase): "' + statusKey + '"');

                String picklistStatusValue = STATUS_MAP.get(statusKey);
                System.debug('Mapped picklistStatusValue: "' + picklistStatusValue + '"');

                if (picklistStatusValue != null) {
                    System.debug('Updating WorkOrder.Status from "' + woToUpdate.Status + '" to "' + picklistStatusValue + '"');
                    woToUpdate.Status = picklistStatusValue;
                } else {
                    System.debug('No mapping for status "' + statusRaw + '", WorkOrder.Status will NOT be updated');
                }
            } else {
                System.debug('Status is blank or not provided, WorkOrder.Status will NOT be updated');
            }

            // 6) Создаём FeedItem из Comment
            if (!String.isBlank(comment)) {
                System.debug('Creating FeedItem with comment');
                FeedItem fi = new FeedItem();
                fi.ParentId = woToUpdate.Id;
                fi.Body =
                    'Comment from ' + email.fromAddress + ':\n' +
                    comment;
                System.debug('FeedItem.Body: ' + fi.Body);
                insert fi;
                System.debug('FeedItem inserted, Id: ' + fi.Id);
            } else {
                System.debug('Comment is blank or not provided, FeedItem will NOT be created');
            }

            // 7) Обрабатываем вложения
            System.debug('Calling handleAttachments for WorkOrder Id: ' + woToUpdate.Id);
            System.debug('email.binaryAttachments size: ' +
                         (email.binaryAttachments == null ? 'null' : String.valueOf(email.binaryAttachments.size())));
            System.debug('email.textAttachments size: ' +
                         (email.textAttachments == null ? 'null' : String.valueOf(email.textAttachments.size())));

            handleAttachments(email.binaryAttachments, email.textAttachments, woToUpdate.Id);

            // 8) Обновляем WorkOrder
            System.debug('Updating WorkOrder: ' + woToUpdate.Id);
            update woToUpdate;
            System.debug('WorkOrder updated successfully');

        } catch (QueryException qe) {
            System.debug('QueryException in processEmail: ' + qe.getMessage());
            System.debug('Stack trace: ' + qe.getStackTraceString());
        } catch (DmlException de) {
            System.debug('DmlException in processEmail: ' + de.getMessage());
            System.debug('Stack trace: ' + de.getStackTraceString());
        } catch (Exception e) {
            System.debug('Exception in processEmail: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }

        System.debug('=== processEmail END ===');
    }

    private void handleAttachments(
        List<Messaging.InboundEmail.BinaryAttachment> binaryAttachments,
        List<Messaging.InboundEmail.TextAttachment> textAttachments,
        Id parentId
    ) {
        System.debug('=== handleAttachments START, parentId = ' + parentId);

        if (parentId == null) {
            System.debug('parentId is null, skipping attachments handling');
            System.debug('=== handleAttachments END (no parent) ===');
            return;
        }

        System.debug('Incoming binaryAttachments is ' +
                     (binaryAttachments == null ? 'null' : 'size = ' + binaryAttachments.size()));
        System.debug('Incoming textAttachments is ' +
                     (textAttachments == null ? 'null' : 'size = ' + textAttachments.size()));

        List<ContentVersion> contentVersionsToInsert = new List<ContentVersion>();

        // Binary attachments
        if (binaryAttachments != null && !binaryAttachments.isEmpty()) {
            Integer idx = 0;
            for (Messaging.InboundEmail.BinaryAttachment b : binaryAttachments) {
                System.debug('Processing BinaryAttachment index ' + idx + ': ' + b);
                idx++;
                if (b == null) {
                    System.debug('BinaryAttachment is null, skipping');
                    continue;
                }
                System.debug('BinaryAttachment.fileName = ' + b.fileName +
                             ', body is ' + (b.body == null ? 'null' : 'not null') +
                             ', mimeTypeSubType = ' + b.mimeTypeSubType);

                if (b.body == null) {
                    System.debug('BinaryAttachment.body is null, skipping');
                    continue;
                }

                ContentVersion cv = new ContentVersion();
                cv.Title        = String.isNotBlank(b.fileName) ? b.fileName : 'binary-attachment';
                cv.PathOnClient = cv.Title;
                cv.VersionData  = b.body; // Blob
                System.debug('Prepared ContentVersion (binary), Title=' + cv.Title);
                contentVersionsToInsert.add(cv);
            }
        }

        // Text attachments
        if (textAttachments != null && !textAttachments.isEmpty()) {
            Integer idx2 = 0;
            for (Messaging.InboundEmail.TextAttachment t : textAttachments) {
                System.debug('Processing TextAttachment index ' + idx2 + ': ' + t);
                idx2++;
                if (t == null) {
                    System.debug('TextAttachment is null, skipping');
                    continue;
                }
                System.debug('TextAttachment.fileName = ' + t.fileName +
                             ', body length = ' + (t.body == null ? 'null' : String.valueOf(t.body.length())) +
                             ', mimeTypeSubType = ' + t.mimeTypeSubType);

                if (String.isBlank(t.body)) {
                    System.debug('TextAttachment.body is blank, skipping');
                    continue;
                }

                ContentVersion cv = new ContentVersion();
                cv.Title        = String.isNotBlank(t.fileName) ? t.fileName : 'text-attachment';
                cv.PathOnClient = cv.Title;
                cv.VersionData  = Blob.valueOf(t.body); // String -> Blob
                System.debug('Prepared ContentVersion (text), Title=' + cv.Title);
                contentVersionsToInsert.add(cv);
            }
        }

        if (contentVersionsToInsert.isEmpty()) {
            System.debug('No attachments to convert into ContentVersion');
            System.debug('=== handleAttachments END (nothing to insert) ===');
            return;
        }

        System.debug('Inserting ' + contentVersionsToInsert.size() + ' ContentVersion records');
        insert contentVersionsToInsert;
        System.debug('ContentVersion insert completed');

        // Перечитать, чтобы получить ContentDocumentId
        List<ContentVersion> insertedVersions = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE Id IN :contentVersionsToInsert
        ];
        System.debug('Queried back ' + insertedVersions.size() + ' ContentVersion records with ContentDocumentId');

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentVersion cv : insertedVersions) {
            System.debug('Processing inserted ContentVersion Id=' + cv.Id +
                         ', Title=' + cv.Title +
                         ', ContentDocumentId=' + cv.ContentDocumentId);

            if (cv.ContentDocumentId == null) {
                System.debug('ContentDocumentId is null, skipping link creation');
                continue;
            }

            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.LinkedEntityId    = parentId;
            cdl.ContentDocumentId = cv.ContentDocumentId;
            cdl.ShareType         = 'V';          // Viewer
            cdl.Visibility        = 'AllUsers';
            links.add(cdl);
        }

        if (!links.isEmpty()) {
            System.debug('Inserting ' + links.size() + ' ContentDocumentLink records');
            insert links;
            System.debug('ContentDocumentLink insert completed');
        } else {
            System.debug('No ContentDocumentLink records to insert');
        }

        System.debug('=== handleAttachments END ===');
    }

}