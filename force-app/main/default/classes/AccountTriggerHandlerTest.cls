@IsTest
private class AccountTriggerHandlerTest {

    @IsTest
    static void testBeforeInsertAccounts() {
        // Arrange
        List<Account> accounts = new List<Account>{
            new Account(
                Name = 'Test Account 1'
            ),
            new Account(
                Name = 'Test Account 2'
            )
        };

        Test.startTest();
        insert accounts; // запускає before insert trigger + handler
        Test.stopTest();

        // Assert
        // Перевіряємо, що акаунти були вставлені
        List<Account> insertedAccounts = [
            SELECT Id, Name
            FROM Account
            WHERE Name LIKE 'Test Account%'
        ];

        System.assertEquals(
            2,
            insertedAccounts.size(),
            'Must be inserted 2 accounts'
        );
    }
}
