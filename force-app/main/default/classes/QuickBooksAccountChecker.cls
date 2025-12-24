public with sharing class QuickBooksAccountChecker {

    private static final List<String> EXCLUDED_YEARS = new List<String>{
        '2009','2010','2011','2012','2013','2014','2015',
        '2016','2017','2018','2019','2020','2021','2022',
        '2023','2024','2025','24-25'
    };

    public static void filterAccounts(List<Account> accounts) {
        for (Account acc : accounts) {
            if (acc == null) continue;
            if(acc.QuickBooks_Id__c != null){
                String name = acc.Name != null ? acc.Name.toLowerCase() : '';
                String company = acc.AccountNumber != null ? acc.AccountNumber.toLowerCase() : '';

                if (containsExcludedYear(name) || containsExcludedYear(company)) {
                    acc.addError('Account is rejected: contains excluded year reference.');
                    continue;
                }

                if (isNumericOnly(acc.Name) || isNumericOnly(company)) {
                    acc.addError('Account is rejected: Name/CompanyName cannot be numeric only.');
                    continue;
                }
            }
            if(acc.BillingStreet != null){
                List<String> streetParts = acc.BillingStreet.split(' ');
                List<String> newStreet = new List<String>();

                if(streetParts.size() > 0 && streetParts[streetParts.size()-1].isNumeric()){
                    String numericPart = streetParts[streetParts.size()-1];

                    streetParts.remove(streetParts.size()-1);

                    newStreet.add(numericPart);
                    newStreet.addAll(streetParts);

                    acc.BillingStreet = String.join(newStreet, ' ');
                }
            }
        }
    }

    private static Boolean containsExcludedYear(String value) {
        if (String.isBlank(value)) return false;
        for (String year : EXCLUDED_YEARS) {
            if (value.contains(year.toLowerCase())) return true;
        }
        return false;
    }

    private static Boolean isNumericOnly(String value) {
        if (String.isBlank(value)) return false;
        return Pattern.matches('^[0-9]+$', value.trim());
    }
}