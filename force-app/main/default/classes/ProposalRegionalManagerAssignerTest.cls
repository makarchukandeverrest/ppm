@IsTest(seeAllData=false)
private class ProposalRegionalManagerAssignerTest {

    private static User createUserWithAlias(String aliasValue) {
        // Берём любой профиль с типом Standard
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE UserType = 'Standard'
            LIMIT 1
        ];

        String trimmedAlias = aliasValue.left(8);

        User u = new User(
            FirstName         = 'Test',
            LastName          = 'RegionalManager',
            Alias             = trimmedAlias,
            Email             = trimmedAlias + '@test.com',
            Username          = trimmedAlias + Datetime.now().getTime() + '@test.com',
            CommunityNickname = trimmedAlias + Datetime.now().getTime(),
            TimeZoneSidKey    = 'Europe/London',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = p.Id
        );
        insert u;
        return u;
    }

    /**
     * Позитивный сценарий с динамической привязкой к существующей CMT‑записи.
     * Берём любую запись Alias_To_OrderCode__mdt, создаём пользователя с таким же alias,
     * берём первый код из Order_Code__c и проверяем, что он мапится на этого пользователя. [web:9][web:12][web:16]
     */
    @IsTest
    static void testAssignManagers_Positive_Bulk() {
        // Берём любую запись CMT
        Map<String, Alias_To_OrderCode__mdt> allMeta = Alias_To_OrderCode__mdt.getAll();
        System.assert(!allMeta.isEmpty(), 'Должна существовать хотя бы одна запись Alias_To_OrderCode__mdt для теста');

        Alias_To_OrderCode__mdt anyRec = allMeta.values()[0];

        // alias для пользователя = Label из метадаты (ты в основном классе именно Label используешь как ключ)
        String aliasFromMeta = anyRec.Label;

        // Берём первый код из Order_Code__c
        System.assertNotEquals(null, anyRec.Order_Code__c, 'Order_Code__c не должен быть пустым в тестовой CMT‑записи');
        List<String> codes = anyRec.Order_Code__c.split(',');
        String firstCode = codes[0].trim();
        System.assertNotEquals('', firstCode, 'Код из Order_Code__c не должен быть пустым');

        // ARRANGE
        User rm = createUserWithAlias(aliasFromMeta);

        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name = 'Opp Match',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(10),
                Order_Taken_By__c = firstCode
            ),
            new Opportunity(
                Name = 'Opp NoMatch',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(11),
                Order_Taken_By__c = 'SOME_UNMAPPED_CODE'
            ),
            new Opportunity(
                Name = 'Opp NullCode',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(12),
                Order_Taken_By__c = null
            )
        };

        // ACT
        Test.startTest();
        ProposalRegionalManagerAssigner.assignManagers(opps);
        Test.stopTest();

        // ASSERT
        System.assertEquals(
            rm.Id,
            opps[0].Regional_Manager__c,
            'Opp с кодом из метадаты должен быть назначен на пользователя с соответствующим alias'
        );
        System.assertEquals(
            null,
            opps[1].Regional_Manager__c,
            'Opp с неизвестным кодом не должен получить менеджера'
        );
        System.assertEquals(
            null,
            opps[2].Regional_Manager__c,
            'Opp с null Order_Taken_By__c не должен получить менеджера'
        );
    }

    /**
     * Сценарий: нет пересечения кодов в Opportunity с кодами из Custom Metadata.
     * Метод должен отработать без ошибок и не менять поле Regional_Manager__c. [web:7][web:9]
     */
    @IsTest
    static void testAssignManagers_NoMatchingCodes() {
        // Берём любую запись CMT, чтобы гарантировать наличие конфигурации
        Map<String, Alias_To_OrderCode__mdt> allMeta = Alias_To_OrderCode__mdt.getAll();
        System.assert(!allMeta.isEmpty(), 'Alias_To_OrderCode__mdt должен быть сконфигурирован');

        Alias_To_OrderCode__mdt anyRec = allMeta.values()[0];

        // Создаём пользователя с alias из метадаты (чтобы не было влияния alias‑фильтра)
        User rm = createUserWithAlias(anyRec.Label);

        // Но коды в Opp делаем такими, которых нет в Order_Code__c
        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name = 'Opp NoMatch1',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(5),
                Order_Taken_By__c = '___NO_MATCH_1___'
            ),
            new Opportunity(
                Name = 'Opp NoMatch2',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(6),
                Order_Taken_By__c = '___NO_MATCH_2___'
            )
        };

        Test.startTest();
        ProposalRegionalManagerAssigner.assignManagers(opps);
        Test.stopTest();

        for (Opportunity o : opps) {
            System.assertEquals(
                null,
                o.Regional_Manager__c,
                'При отсутствии соответствий кодов менеджер не должен назначаться'
            );
        }
    }

    /**
     * Сценарий: alias пользователя не совпадает ни с одним Label в Custom Metadata.
     * Метод не должен назначать менеджера. [web:9][web:12]
     */
    @IsTest
    static void testAssignManagers_UserAliasNotInMetadata() {
        // Убедимся, что какая‑то метадата есть
        Map<String, Alias_To_OrderCode__mdt> allMeta = Alias_To_OrderCode__mdt.getAll();
        System.assert(!allMeta.isEmpty(), 'Alias_To_OrderCode__mdt должен быть сконфигурирован');

        // Создаём пользователя с alias, которого точно нет среди Label метадаты
        User rmX = createUserWithAlias('alias_not_in_metadata');

        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name = 'Opp with code from metadata',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(7),
                Order_Taken_By__c = 'SOME_CODE' // даже если совпадёт с кодом, alias не совпадёт
            )
        };

        Test.startTest();
        ProposalRegionalManagerAssigner.assignManagers(opps);
        Test.stopTest();

        System.assertEquals(
            null,
            opps[0].Regional_Manager__c,
            'Если alias пользователя не найден среди ключей в мапе, назначение не происходит'
        );
    }
}
