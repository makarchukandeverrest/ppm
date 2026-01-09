public with sharing class InvoiceTriggerHandler extends TriggerHandler{
    List<Invoice__c> newList;

    public InvoiceTriggerHandler(){
		this.newList = (List<Invoice__c>)Trigger.new;
	}

    protected override void beforeInsert(){
        InvoiceQuickBooksProposalLinker linker = new InvoiceQuickBooksProposalLinker(this.newList);
	}

    protected override void afterInsert(){
        ProposalStatusDefiner.updateStatus(this.newList);
	}

    protected override void beforeUpdate(){
        InvoiceQuickBooksProposalLinker linker = new InvoiceQuickBooksProposalLinker(this.newList);
    }
}