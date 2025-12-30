@isTest
public class MultiSelectPicklistConverterTest {

    @isTest
    private static void checkValuesTest(){
        
        List<String> tempLst = new list<String>();
        tempLst.add('Test1');
        tempLst.add('Test2');
        MultiSelectPicklistToCollectionConverter.CheckValues(tempLst);
        
        List<String> tempNullLst = null;
        MultiSelectPicklistToCollectionConverter.CheckValues(tempNullLst);
    }

}