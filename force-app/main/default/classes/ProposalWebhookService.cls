public without sharing class ProposalWebhookService {
    // TODO: replace on normal implementation
    private static final String WEBHOOK_URL =
        'https://webhooks.skyvia.com/webhooks/qp2dd4n4/salesforce_proposal_update';

    public static void sendProposalUpdates(Set<Id> proposalIds) {
        if (proposalIds == null || proposalIds.isEmpty()) {
            return;
        }

        List<Opportunity> proposals = [
            SELECT
                Id,
                Name,
                Description,
                StageName,
                CloseDate,
                Contact__c,
                Date_Ordered__c,
                Line_Items__c,
                Order_Taken_By__c,
                Project_Order_No__c,
                Sales_Tax__c,
                Start_Date__c,
                Subtotal__c,
                Account_QuickBooks_Id__c,
                FOB__c,
                QuickBooks_Id__c,
                Reference_Number__c,
                Sales_Tax_Percentage__c,
                Terms__c,
                Is_Active__c
            FROM Opportunity
            WHERE Id IN :proposalIds
        ];


        Map<Id, List<Deal_Line_Item__c>> itemsByProposalId = new Map<Id, List<Deal_Line_Item__c>>();
        for (Deal_Line_Item__c lineItem : [
            SELECT
                Id,
                Name,
                Description__c,
                Quantity__c,
                Total__c,
                Unit_Cost__c,
                Deal_QuickBooks_Id__c,
                QuickBooks_Id__c,
                Deal__c
            FROM Deal_Line_Item__c
            WHERE Deal__c IN :proposalIds
            ORDER BY CreatedDate ASC
        ]) {
            if (!itemsByProposalId.containsKey(lineItem.Deal__c)) {
                itemsByProposalId.put(lineItem.Deal__c, new List<Deal_Line_Item__c>());
            }
            itemsByProposalId.get(lineItem.Deal__c).add(lineItem);
        }

        List<ProposalWebhookPayload> payloads = new List<ProposalWebhookPayload>();
        for (Opportunity proposal : proposals) {
            List<Deal_Line_Item__c> items = itemsByProposalId.containsKey(proposal.Id)
                ? itemsByProposalId.get(proposal.Id)
                : new List<Deal_Line_Item__c>();
            payloads.add(buildPayload(proposal, items));
        }

        ProposalWebhookRequest body = new ProposalWebhookRequest();
        body.proposals = payloads;

        System.enqueueJob(new ProposalWebhookQueueable(JSON.serialize(body)));
    }

    @TestVisible
    private static ProposalWebhookPayload buildPayload(
        Opportunity proposal,
        List<Deal_Line_Item__c> lineItems
    ) {
        ProposalWebhookPayload payload = new ProposalWebhookPayload();
        payload.id = proposal.Id;
        payload.name = proposal.Name;
        payload.description = proposal.Description;
        payload.stageName = proposal.StageName;
        payload.closeDate = proposal.CloseDate;
        payload.contact = proposal.Contact__c == null ? null : String.valueOf(proposal.Contact__c);
        payload.dateOrdered = proposal.Date_Ordered__c;
        payload.lineItems = proposal.Line_Items__c;
        payload.orderTakenBy = proposal.Order_Taken_By__c;
        payload.projectOrderNo = proposal.Project_Order_No__c;
        payload.salesTax = proposal.Sales_Tax__c;
        payload.startDate = proposal.Start_Date__c;
        payload.subtotal = proposal.Subtotal__c;
        payload.accountQuickBooksId = proposal.Account_QuickBooks_Id__c;
        payload.fob = proposal.FOB__c;
        payload.quickBooksId = proposal.QuickBooks_Id__c;
        payload.referenceNumber = proposal.Reference_Number__c;
        payload.salesTaxPercentage = proposal.Sales_Tax_Percentage__c;
        payload.terms = proposal.Terms__c;
        payload.isActive = proposal.Is_Active__c;
        payload.items = new List<ProposalWebhookItem>();

        if (lineItems != null) {
            for (Deal_Line_Item__c lineItem : lineItems) {
                payload.items.add(buildItem(lineItem));
            }
        }
        return payload;
    }

    @TestVisible
    private static ProposalWebhookItem buildItem(Deal_Line_Item__c lineItem) {
        ProposalWebhookItem item = new ProposalWebhookItem();
        item.id = lineItem.Id;
        item.name = lineItem.Name;
        item.description = lineItem.Description__c;
        item.quantity = lineItem.Quantity__c;
        item.total = lineItem.Total__c;
        item.unitCost = lineItem.Unit_Cost__c;
        item.dealQuickBooksId = lineItem.Deal_QuickBooks_Id__c;
        item.quickBooksId = lineItem.QuickBooks_Id__c;
        return item;
    }

    private static void sendProposalWebhook(String jsonBody) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(WEBHOOK_URL);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setTimeout(120000);
        request.setBody(jsonBody);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            System.debug(
                LoggingLevel.ERROR,
                'Proposal webhook failed. Status=' +
                    response.getStatusCode() +
                    ' Body=' +
                    response.getBody()
            );
        }
    }

    private class ProposalWebhookQueueable implements Queueable, Database.AllowsCallouts {
        private final String jsonBody;

        private ProposalWebhookQueueable(String jsonBody) {
            this.jsonBody = jsonBody;
        }

        public void execute(QueueableContext context) {
            sendProposalWebhook(jsonBody);
        }
    }

    public class ProposalWebhookRequest {
        public List<ProposalWebhookPayload> proposals;
    }

    public class ProposalWebhookPayload {
        public Id id;
        public String name;
        public String description;
        public String stageName;
        public Date closeDate;
        public String contact;
        public Date dateOrdered;
        public String lineItems;
        public String orderTakenBy;
        public String projectOrderNo;
        public Decimal salesTax;
        public Date startDate;
        public Decimal subtotal;
        public String accountQuickBooksId;
        public String fob;
        public String quickBooksId;
        public String referenceNumber;
        public Decimal salesTaxPercentage;
        public String terms;
        public Boolean isActive;
        public List<ProposalWebhookItem> items;
    }

    public class ProposalWebhookItem {
        public Id id;
        public String name;
        public String description;
        public Decimal quantity;
        public Decimal total;
        public Decimal unitCost;
        public String dealQuickBooksId;
        public String quickBooksId;
    }
}
