#apextesting
public with sharing class LwcAccountDemoController {
    @AuraEnabled(cacheable=true)
    public static List<Account> getRecentAccounts() {
        return [
            SELECT Id, Name, Industry
            FROM Account
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];
    }
}
