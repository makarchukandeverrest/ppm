public with sharing class AccountListSendController {
    
    @AuraEnabled
    public static SendEmailResult sendEmails(String recipients, String subject, String body, List<Id> accountIds, List<Id> fileIds) {
        try {
            // Validate inputs
            if (String.isBlank(recipients)) {
                throw new AuraHandledException('At least one recipient is required');
            }
            if (String.isBlank(subject)) {
                throw new AuraHandledException('Email subject is required');
            }
            if (String.isBlank(body)) {
                throw new AuraHandledException('Email body is required');
            }
            
            // Parse and validate email addresses
            List<String> emailAddresses = parseEmailAddresses(recipients);
            validateEmailAddresses(emailAddresses);
            
            // Create email messages
            List<Messaging.SingleEmailMessage> emailMessages = createEmailMessages(emailAddresses, subject, body, fileIds);
            
            // Send emails
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(emailMessages);
            
            // Check results and handle errors
            handleSendResults(results, emailAddresses);
            
            // Create activities on accounts if accountIds are provided
            Integer activitiesCreated = 0;
            if (accountIds != null && !accountIds.isEmpty()) {
                // Create a separate task for each account with its own recipients
                activitiesCreated = createActivitiesForAccounts(accountIds, subject, body, fileIds);
            }
            return new SendEmailResult(true, 'Email sent successfully to ' + emailAddresses.size() + ' recipient(s)', activitiesCreated);
            
        } catch (Exception e) {
            throw new AuraHandledException('Error sending email: ' + e.getMessage());
        }
    }
    
    private static Integer createActivitiesForAccounts(List<Id> accountIds, String subject, String body, List<Id> fileIds) {
        List<Task> tasksToCreate = new List<Task>();
        
        // Convert HTML body to plain text for activity description
        String plainTextBody = String.isNotBlank(body) ? body.stripHtmlTags() : '';
        String truncatedBody = plainTextBody.length() > 32000 ? plainTextBody.substring(0, 32000) : plainTextBody;
        
        // Get current user info for the activity
        Id currentUserId = UserInfo.getUserId();
        
        for (Id accountId : accountIds) {
            // Verify the account ID is valid before creating task
            if (isValidId(accountId, 'Account')) {
                Task emailTask = new Task();
                emailTask.WhatId = accountId; // Link to Account
                emailTask.Subject = 'Email: ' + (String.isNotBlank(subject) ? subject : 'No Subject');
                emailTask.Description ='\n\nEmail Content:\n' + 
                                      truncatedBody;
                emailTask.Status = 'Completed';
                emailTask.Priority = 'Normal';
                emailTask.ActivityDate = Date.today();
                emailTask.Type = 'Email';
                emailTask.TaskSubtype = 'Email'; // Important for email tasks
                emailTask.OwnerId = currentUserId; // Set current user as owner
                
                tasksToCreate.add(emailTask);
            }
        }
        
        if (!tasksToCreate.isEmpty()) {
            try {
                insert tasksToCreate;
                
                // Attach files
                attachFilesToTasks(tasksToCreate, fileIds);
                
                return tasksToCreate.size();
            } catch (DmlException e) {
                System.debug('Error creating activities: ' + e.getMessage());
                // Don't throw error - email was sent successfully, just activity creation failed
                return 0;
            }
        }
        return 0;
    }
    
    private static Boolean isValidId(Id recordId, String objectType) {
        try {
            // Basic validation of the ID format and object type
            if (recordId != null && recordId.getSObjectType().getDescribe().getName() == objectType) {
                return true;
            }
        } catch (Exception e) {
            System.debug('Invalid ID: ' + recordId + ' - ' + e.getMessage());
        }
        return false;
    }
    
    private static List<String> parseEmailAddresses(String recipients) {
        if (String.isBlank(recipients)) {
            return new List<String>();
        }
        
        // Split by semicolon, trim, remove empty strings, and deduplicate
        Set<String> uniqueEmails = new Set<String>();
        List<String> emailList = new List<String>();
        
        for (String email : recipients.split(';')) {
            String trimmedEmail = email.trim();
            if (String.isNotBlank(trimmedEmail)) {
                String lowerEmail = trimmedEmail.toLowerCase();
                if (!uniqueEmails.contains(lowerEmail)) {
                    uniqueEmails.add(lowerEmail);
                    emailList.add(trimmedEmail);
                }
            }
        }
        
        return emailList;
    }
    
    private static void validateEmailAddresses(List<String> emailAddresses) {
        if (emailAddresses.isEmpty()) {
            throw new AuraHandledException('No valid email addresses found');
        }
        
        // Simple email validation pattern
        String emailRegex = '^[a-zA-Z0-9._|\\\\%#~`=?&/$^*!}{+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        
        for (String email : emailAddresses) {
            Matcher emailMatcher = emailPattern.matcher(email);
            if (!emailMatcher.matches()) {
                throw new AuraHandledException('Invalid email address: ' + email);
            }
        }
    }
    
    private static List<Messaging.SingleEmailMessage> createEmailMessages(List<String> toAddresses, String subject, String body,List<Id> fileIds) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
        // Use Org Wide Email Address if available, otherwise use current user's email
        String orgWideEmailId = getOrgWideEmailAddress();
        
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(toAddresses);
        message.setSubject(subject);
        message.setHtmlBody(body);

        if (!fileIds.isEmpty()) {
            List<ContentVersion> versions = [
                SELECT Title, VersionData, FileExtension 
                FROM ContentVersion 
                WHERE ContentDocumentId IN :fileIds
                AND IsLatest = true
            ];
            for (ContentVersion v : versions) {
                Messaging.EmailFileAttachment a = new Messaging.EmailFileAttachment();
                a.setFileName(v.Title + '.' + v.FileExtension);
                a.setBody(v.VersionData);
                attachments.add(a);
            }
        }
        
        // Set sender address
        if (String.isNotBlank(orgWideEmailId)) {
            message.setOrgWideEmailAddressId(orgWideEmailId);
        }

        if (!attachments.isEmpty()) {
            message.setFileAttachments(attachments);
        }
        
        // Set save as activity flag (optional)
        message.setSaveAsActivity(true);
        
        messages.add(message);
        return messages;
    }
    
    private static String getOrgWideEmailAddress() {
        try {
            // Query for an active Org Wide Email Address
            List<OrgWideEmailAddress> oweaList = [
                SELECT Id, Address 
                FROM OrgWideEmailAddress 
                WHERE IsAllowAllProfiles = true 
                LIMIT 1
            ];
            
            if (!oweaList.isEmpty()) {
                return oweaList[0].Id;
            }
        } catch (Exception e) {
            System.debug('Error getting Org Wide Email Address: ' + e.getMessage());
        }
        return null;
    }
    
    private static void handleSendResults(List<Messaging.SendEmailResult> results, List<String> emailAddresses) {
        for (Integer i = 0; i < results.size(); i++) {
            Messaging.SendEmailResult result = results[i];
            if (!result.isSuccess()) {
                String errorMessage = 'Failed to send email to: ' + emailAddresses[i] + '. ';
                for (Messaging.SendEmailError error : result.getErrors()) {
                    errorMessage += error.getMessage() + ' ';
                }
                throw new AuraHandledException(errorMessage);
            }
        }
    }
    
    // Inner class for result handling
    public class SendEmailResult {
        @AuraEnabled
        public Boolean isSuccess { get; set; }
        
        @AuraEnabled
        public String message { get; set; }
        
        @AuraEnabled
        public Integer activitiesCreated { get; set; }
        
        public SendEmailResult(Boolean isSuccess, String message) {
            this.isSuccess = isSuccess;
            this.message = message;
        }
        
        public SendEmailResult(Boolean isSuccess, String message, Integer activitiesCreated) {
            this.isSuccess = isSuccess;
            this.message = message;
            this.activitiesCreated = activitiesCreated;
        }
    }

    private static void attachFilesToTasks(List<Task> tasks, List<Id> contentDocumentIds) {
        if(tasks.isEmpty() || contentDocumentIds == null || contentDocumentIds.isEmpty()) return;

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        
        for(Task t : tasks) {
            for(Id docId : contentDocumentIds) {
                links.add(new ContentDocumentLink(
                    ContentDocumentId = docId, // MUST be ContentDocument Id
                    LinkedEntityId = t.Id,
                    ShareType = 'V', // Viewer
                    Visibility = 'AllUsers' // Make sure all users can see
                ));
            }
        }
        
        try {
            insert links;
        } catch(DmlException e) {
            System.debug('Failed to attach files to tasks: ' + e.getMessage());
        }
    }

}