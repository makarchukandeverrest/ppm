global class MultiSelectPicklistToCollectionConverter { 

   @InvocableMethod
   public static List<List<String>> CheckValues(List<String> values) {
      if(values != null){
          
          String tempStr = values[0];
          List<String> lstnew = tempStr.split(';');
          List<List<String>> finalLst = new List<List<String>>();
          finalLst.add(lstnew);
          return finalLst;
      } else return null;

   }

}