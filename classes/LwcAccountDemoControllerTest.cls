#apextesting
@IsTest
private class LwcAccountDemoControllerTest {
    @IsTest
    static void testGetRecentAccounts() {
        List<Account> accs = new List<Account>{
            new Account(Name = 'Demo Account 1', Industry = 'Technology'),
            new Account(Name = 'Demo Account 2', Industry = 'Finance')
        };
        insert accs;

        Test.startTest();
        List<Account> results = LwcAccountDemoController.getRecentAccounts();
        Test.stopTest();

        System.assert(results.size() > 0, 'Accounts should be returned');
        System.assertNotEquals(null, results[0].Name, 'Account name should exist');
    }
}
