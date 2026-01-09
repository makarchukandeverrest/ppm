@isTest
public class AccountListSendControllerTest {

    @testSetup
    static void setupData() {
        // Создаём тестовый аккаунт
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Создаём тестовый файл (ContentVersion -> ContentDocument)
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'TestFile.txt',
            VersionData = Blob.valueOf('Hello World')
        );
        insert cv;
    }

    @isTest
    static void testSendEmails_Success() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentDocument doc = [
            SELECT Id FROM ContentDocument LIMIT 1
        ];

        List<Id> accountIds = new List<Id>{ acc.Id };
        List<Id> fileIds = new List<Id>{ doc.Id };

        Test.startTest();
        AccountListSendController.SendEmailResult result =
            AccountListSendController.sendEmails(
                'someone@example.com',
                'Test Subject',
                'Test Body',
                accountIds,
                fileIds
            );
        Test.stopTest();

        System.assert(result.isSuccess, 'Expected email send to succeed');
        System.assertEquals(1, result.activitiesCreated, 'One activity should be created');

        // Проверим, что Task реально создался
        List<Task> tasks = [SELECT Id, WhatId, Subject FROM Task WHERE WhatId = :acc.Id];
        System.assertEquals(1, tasks.size(), 'Expected 1 task linked to Account');
        System.assert(tasks[0].Subject.contains('Test Subject'));
    }
}