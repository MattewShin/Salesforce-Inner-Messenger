trigger BreakRequestTrigger on Break_Request__c (
    before insert, before update,
    after insert, after update, after delete, after undelete
) {
    BreakRequestTriggerHandler.handle(Trigger.new, Trigger.oldMap, Trigger.operationType);
}