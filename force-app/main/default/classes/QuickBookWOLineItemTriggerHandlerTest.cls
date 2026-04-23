@isTest
private class QuickBookWOLineItemTriggerHandlerTest {
    @TestSetup
    static void makeData(){
        Service_Team_Member__c stm = new Service_Team_Member__c(
            Name = 'Test Member 1'
        );
        insert stm;

        Service_Team_Member__c stm2 = new Service_Team_Member__c(
            Name = 'Test Member 2'
        );
        insert stm2;

        String qbLineItemsJson =
            '[{"Id":"1CCBC8-1767722633","IsItemGroup":false,"ItemId":"20001-1147183646","ItemName":"SERVICE WORK","Desc":"Supply and Install social pool motor","Quantity":1.0,"Rate":1875.00,"Amount":1875.00,"SalesTaxCodeId":"2000-1147094116","SalesTaxCodeName":"Non","Invoiced":0.0,"IsManuallyClosed":false},'
            + '{"Id":"1CCBC9-1767722633","IsItemGroup":false,"IsManuallyClosed":false},'
            + '{"Id":"1CCBCA-1767722633","IsItemGroup":false,"ItemId":"20001-1147183646","ItemName":"SERVICE WORK","Desc":"Repla/ce Spa Jet Pump 2\\" Valve","Quantity":1.0,"Rate":680.00,"Amount":680.00,"SalesTaxCodeId":"2000-1147094116","SalesTaxCodeName":"Non","Invoiced":0.0,"IsManuallyClosed":false},'
            + '{"Id":"1CCBCB-1767722633","IsItemGroup":false,"IsManuallyClosed":false},'
            + '{"Id":"1CCBCC-1767722633","IsItemGroup":false,"ItemId":"20001-1147183646","ItemName":"SERVICE WORK","Desc":"Rebuild Spa Filter Pump Effluent Line","Quantity":1.0,"Rate":500.00,"Amount":500.00,"SalesTaxCodeId":"2000-1147094116","SalesTaxCodeName":"Non","Invoiced":0.0,"IsManuallyClosed":false}]';

        WorkOrder testWorkOrder = new WorkOrder(
            Subject = 'Test Work Order',
            Quick_Books_Customer_Name__c = '1CCBC6-1767722633',
            Quick_Books_Id__c = '1CCBC8-1767722633',
            Quick_Books_Line_Items__c = qbLineItemsJson,
            Quick_Books_WO_No__c = 'Estimate 14557: Service Work',
            Quickbooks_Memo__c = '3055',
            Issue_Date__c = DateTime.newInstanceGMT(2026, 1, 6, 18, 3, 53),
            Age_Color__c = 'Green',
            Date_Issued__c = Date.newInstance(2026, 1, 9),
            Property_Name__c = 'Motor, valve replacement, plumbing',
            Job_Description__c = 'Florin, Yury',
            Technician__c = '55',
            Tech_Hourly_Rate__c = 4,
            Tech_Work_Time_hrs__c = 2,
            Tech_Drive_Time_hrs__c = 344,
            Contractor_Labor_Cost__c = 876,
            Material_Cost__c = 1260,
            Total_Sales__c = 40,
            Uncounted_Loss__c = 1260,
            Gas__c = 343.75
        );
        insert testWorkOrder;

        Quick_Book_Work_Order_Line_Item__c qbLineItem = [SELECT Id,Service_Team_Member__c FROM Quick_Book_Work_Order_Line_Item__c LIMIT 1];
        qbLineItem.Service_Team_Member__c = stm.Id;
        update qbLineItem;
    }

    @isTest
    static void newServiceTeamMemberTest() {
        Quick_Book_Work_Order_Line_Item__c qbLineItem = [SELECT Id,Service_Team_Member__c,Work_Order__c FROM Quick_Book_Work_Order_Line_Item__c LIMIT 1];
        Service_Team_Member__c stm2 = [SELECT Id,Name FROM Service_Team_Member__c WHERE Name = 'Test Member 2' LIMIT 1];
        qbLineItem.Service_Team_Member__c = stm2.Id;
        Test.startTest();
        update qbLineItem;
        Test.stopTest();

        WorkOrder wo = [SELECT Id, Technician__c FROM WorkOrder WHERE Id = :qbLineItem.Work_Order__c LIMIT 1];
        System.assertEquals(true, wo.Technician__c.contains(stm2.Name), 'Technician__c should be the new service team member');
    }

    @isTest
    static void removeServiceTeamMemberTest () {
        Quick_Book_Work_Order_Line_Item__c qbLineItem = [SELECT Id,Service_Team_Member__c,Work_Order__c FROM Quick_Book_Work_Order_Line_Item__c WHERE Service_Team_Member__c != null LIMIT 1];
        Test.startTest();
        qbLineItem.Service_Team_Member__c = null;
        update qbLineItem;
        Test.stopTest();
        WorkOrder wo = [SELECT Id, Technician__c FROM WorkOrder WHERE Id = :qbLineItem.Work_Order__c LIMIT 1];
        System.assertEquals(null, wo.Technician__c, 'Technician__c should be null');
    }

    @isTest
    static void bulkChangeAllLineItemsToSingleMemberTest() {
        Service_Team_Member__c targetMember = [
            SELECT Id, Name
            FROM Service_Team_Member__c
            LIMIT 1
        ];

        List<Quick_Book_Work_Order_Line_Item__c> items = [
            SELECT Id, Work_Order__c, Service_Team_Member__c
            FROM Quick_Book_Work_Order_Line_Item__c
        ];

        Set<Id> workOrderIds = new Set<Id>();
        for (Quick_Book_Work_Order_Line_Item__c row : items) {
            row.Service_Team_Member__c = targetMember.Id;
            workOrderIds.add(row.Work_Order__c);
        }

        Test.startTest();
        update items;
        Test.stopTest();

        for (Quick_Book_Work_Order_Line_Item__c row : [
            SELECT Id, Service_Team_Member__c
            FROM Quick_Book_Work_Order_Line_Item__c
        ]) {
            System.assertEquals(
                targetMember.Id,
                row.Service_Team_Member__c,
                'All line items should reference the single target member'
            );
        }

        for (WorkOrder wo : [
            SELECT Id, Technician__c
            FROM WorkOrder
            WHERE Id IN :workOrderIds
        ]) {
            System.assertNotEquals(null, wo.Technician__c, 'Technician__c should be populated after bulk update');
            System.assertEquals(
                true,
                wo.Technician__c.contains(targetMember.Name),
                'Technician__c should contain target member name. Actual: ' + wo.Technician__c
            );
            Integer occurrences = 0;
            for (String namePart : wo.Technician__c.split(',\\s*')) {
                if (namePart != null && namePart.trim() == targetMember.Name) {
                    occurrences++;
                }
            }
            System.assertEquals(
                1,
                occurrences,
                'Technician__c should contain target member name only once. Actual: ' + wo.Technician__c
            );
        }
    }
}