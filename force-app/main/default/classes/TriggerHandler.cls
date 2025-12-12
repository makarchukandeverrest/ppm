public virtual with sharing class TriggerHandler {
    TriggerOperation context;

    public TriggerHandler(){
	this.context = Trigger.operationType;
	}

    public void run(){
        switch on this.context {
            when AFTER_INSERT {
                afterInsert();
            }when AFTER_UPDATE {
                afterUpdate();
            }when BEFORE_INSERT {
                beforeInsert();
            }when BEFORE_UPDATE {
                beforeUpdate();
            }
        }
	}

    protected virtual void afterInsert(){}

    protected virtual void afterUpdate(){}

    protected virtual void beforeInsert(){}

    protected virtual void beforeUpdate(){}
}