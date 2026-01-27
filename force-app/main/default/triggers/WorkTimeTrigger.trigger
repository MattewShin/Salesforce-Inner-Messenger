trigger WorkTimeTrigger on Work_Time__c (before insert, before update) {
    WorkTimeTriggerHandler.beforeInsertOrUpdate(Trigger.new);
}

