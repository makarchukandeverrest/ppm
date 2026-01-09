public with sharing class QuickBooksWOLineIntem {
    public String Id;
    public Boolean IsItemGroup;
    public String ItemId;
    public String ItemName;
    public String Description;
    public Decimal Quantity;
    public Decimal Rate;
    public Decimal Amount;
    public String SalesTaxCodeId;
    public String SalesTaxCodeName;
    public Decimal Invoiced;
    public Boolean IsManuallyClosed;

    /**
     * Factory method to parse JSON into a list of QuickBooksWOLineIntem
     * Handles reserved keywords like "Desc" and missing fields safely
     */
    public static List<QuickBooksWOLineIntem> fromJson(String jsonString) {
        List<QuickBooksWOLineIntem> items = new List<QuickBooksWOLineIntem>();
        if (String.isBlank(jsonString)) return items;

        try {
            List<Object> rawList = (List<Object>) JSON.deserializeUntyped(jsonString);

            for (Object obj : rawList) {
                Map<String, Object> mapItem = (Map<String, Object>) obj;
                QuickBooksWOLineIntem item = new QuickBooksWOLineIntem();

                item.Id = (String) mapItem.get('Id');
                item.IsItemGroup = mapItem.containsKey('IsItemGroup') ? (Boolean) mapItem.get('IsItemGroup') : false;
                item.ItemId = mapItem.containsKey('ItemId') ? (String) mapItem.get('ItemId') : null;
                item.ItemName = mapItem.containsKey('ItemName') ? (String) mapItem.get('ItemName') : null;
                item.Description = mapItem.containsKey('Desc') ? (String) mapItem.get('Desc') : null;
                item.Quantity = mapItem.containsKey('Quantity') ? (Decimal) mapItem.get('Quantity') : 0;
                item.Rate     = mapItem.containsKey('Rate')     ? (Decimal) mapItem.get('Rate')     : 0;
                item.Amount   = mapItem.containsKey('Amount')   ? (Decimal) mapItem.get('Amount')   : 0;
                item.SalesTaxCodeId = mapItem.containsKey('SalesTaxCodeId') ? (String) mapItem.get('SalesTaxCodeId') : null;
                item.SalesTaxCodeName = mapItem.containsKey('SalesTaxCodeName') ? (String) mapItem.get('SalesTaxCodeName') : null;
                item.Invoiced = mapItem.containsKey('Invoiced') ? (Decimal) mapItem.get('Invoiced') : 0;
                item.IsManuallyClosed = mapItem.containsKey('IsManuallyClosed') ? (Boolean) mapItem.get('IsManuallyClosed') : false;

                items.add(item);
            }
        } catch (Exception ex) {
            System.debug('Error parsing QuickBooks line items JSON: ' + ex.getMessage());
        }

        return items;
    }
}