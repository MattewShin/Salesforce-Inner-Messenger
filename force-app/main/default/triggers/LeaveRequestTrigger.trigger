trigger LeaveRequestTrigger on Leave_Request__c (before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore) {
        LeaveRequestTriggerHandler.beforeUpsert(Trigger.new, Trigger.isInsert, Trigger.oldMap);
    }
    if (Trigger.isAfter) {
        if (Trigger.isDelete) {
            LeaveRequestTriggerHandler.afterDelete(Trigger.old);
        } else {
            LeaveRequestTriggerHandler.afterUpsert(Trigger.new, Trigger.isInsert, Trigger.oldMap);
        }
    }
}