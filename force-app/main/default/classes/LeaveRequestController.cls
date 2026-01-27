/**
 * ===========================================================================================
 * @description       : Controller for Leave Request operations (CRUD, approval process integration)
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Leave request CRUD operations and Approval Process integration
 */
public without sharing class LeaveRequestController {
    public class LeaveRequestException extends Exception {}

    private static void ensureApprover(Leave_Request__c r) {
        if (r.Approver__c != null) return;
        if (r.Requester__c == null) throw new LeaveRequestException('Requester is required.');
        User u = [SELECT Id, ManagerId FROM User WHERE Id = :r.Requester__c LIMIT 1];
        if (u.ManagerId == null) throw new LeaveRequestException('Requester has no Manager. Cannot submit for approval.');
        r.Approver__c = u.ManagerId;
    }

    @AuraEnabled
    public static Leave_Request__c upsertDraft(Leave_Request__c draft) {
        if (draft == null) throw new LeaveRequestException('Draft is required.');
        Id me = UserInfo.getUserId();
        if (draft.Requester__c == null) draft.Requester__c = me;
        if (draft.Status__c == null) draft.Status__c = 'Draft';
        if (draft.Requester__c != me) throw new LeaveRequestException('You can only create/edit your own leave request.');

        // 초안은 1건만 유지: 새 초안을 만들 때 기존 초안이 있으면 삭제
        if (draft.Id == null) {
            // 새 초안 생성 시 기존 초안 삭제
            List<Leave_Request__c> existingDrafts = [
                SELECT Id FROM Leave_Request__c 
                WHERE Requester__c = :me AND Status__c = 'Draft'
            ];
            if (!existingDrafts.isEmpty()) {
                delete existingDrafts;
            }
        }

        // Validate + compute days (weekends excluded)
        LeaveService.Range r = new LeaveService.Range(
            draft.Start_Date__c,
            LeaveService.parseSlot(draft.Start_Slot__c),
            draft.End_Date__c,
            LeaveService.parseSlot(draft.End_Slot__c)
        );
        draft.Days__c = LeaveService.calculateBusinessDays(r);
        LeaveService.validateNoConflict(draft);

        upsert draft;
        return draft;
    }

    @AuraEnabled
    public static void submit(Id requestId) {
        if (requestId == null) return;
        Leave_Request__c r = [
            SELECT Id, Requester__c, Approver__c, Status__c, Start_Date__c, Start_Slot__c, End_Date__c, End_Slot__c
            FROM Leave_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];
        Id me = UserInfo.getUserId();
        if (r.Requester__c != me) throw new LeaveRequestException('Only requester can submit.');
        if (r.Status__c != 'Draft' && r.Status__c != 'Rejected') throw new LeaveRequestException('Only Draft/Rejected can be submitted.');

        ensureApprover(r);

        LeaveService.Range range = new LeaveService.Range(
            r.Start_Date__c, LeaveService.parseSlot(r.Start_Slot__c),
            r.End_Date__c, LeaveService.parseSlot(r.End_Slot__c)
        );
        r.Days__c = LeaveService.calculateBusinessDays(range);
        LeaveService.validateNoConflict(r);

        r.Status__c = 'Submitted';
        update r;
        
        // Approval Process 시작
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(r.Id);
        req.setComments('Leave request submitted for approval');
        Approval.ProcessResult result = Approval.process(req);
        if (!result.isSuccess()) {
            String msg = 'Approval process could not be started.';
            if (!result.getErrors().isEmpty()) {
                msg += ' ' + result.getErrors()[0].getMessage();
            }
            throw new LeaveRequestException(msg);
        }
    }

    @AuraEnabled
    public static void cancelBeforeApproval(Id requestId) {
        if (requestId == null) return;
        Leave_Request__c r = [SELECT Id, Requester__c, Status__c FROM Leave_Request__c WHERE Id = :requestId LIMIT 1];
        Id me = UserInfo.getUserId();
        if (r.Requester__c != me) throw new LeaveRequestException('Only requester can cancel.');
        if (r.Status__c != 'Draft' && r.Status__c != 'Submitted') throw new LeaveRequestException('Only Draft/Submitted can be cancelled immediately.');
        r.Status__c = 'Cancelled';
        update r;
    }

    @AuraEnabled
    public static void requestCancelAfterApproval(Id requestId) {
        if (requestId == null) return;
        Leave_Request__c r = [SELECT Id, Requester__c, Status__c FROM Leave_Request__c WHERE Id = :requestId LIMIT 1];
        Id me = UserInfo.getUserId();
        if (r.Requester__c != me) throw new LeaveRequestException('Only requester can request cancellation.');
        if (r.Status__c != 'Approved') throw new LeaveRequestException('Only Approved can request cancellation.');
        
        // Approval Process 시작 (취소 승인) - 상태가 Approved일 때 시작해야 Entry Criteria를 만족함
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(r.Id);
        req.setComments('Leave cancellation requested');
        Approval.ProcessResult result = Approval.process(req);
        if (!result.isSuccess()) {
            String msg = 'Cancel approval process could not be started.';
            if (!result.getErrors().isEmpty()) {
                msg += ' ' + result.getErrors()[0].getMessage();
            }
            throw new LeaveRequestException(msg);
        }
        
        // Approval Process가 성공적으로 시작된 후 상태 변경
        // (프로세스의 Initial Submission Actions나 Field Update에서 상태를 변경할 수도 있음)
        // 하지만 명시적으로 상태를 변경하여 확실히 함
        r.Status__c = 'CancelSubmitted';
        update r;
    }

    private static void ensureIsApprover(Leave_Request__c r) {
        Id me = UserInfo.getUserId();
        if (r.Approver__c == null || r.Approver__c != me) {
            throw new LeaveRequestException('Only approver can perform this action.');
        }
    }

    @AuraEnabled
    public static void approve(Id requestId) {
        if (requestId == null) return;
        Leave_Request__c r = [SELECT Id, Status__c, Approver__c FROM Leave_Request__c WHERE Id = :requestId LIMIT 1];
        ensureIsApprover(r);
        // Cancelled 상태는 승인할 수 없음
        if (r.Status__c == 'Cancelled') {
            throw new LeaveRequestException('Cancelled leave requests cannot be approved.');
        }
        if (r.Status__c != 'Submitted') {
            throw new LeaveRequestException('Only Submitted can be approved.');
        }
        r.Status__c = 'Approved';
        update r;
    }

    @AuraEnabled
    public static void reject(Id requestId) {
        if (requestId == null) return;
        Leave_Request__c r = [SELECT Id, Status__c, Approver__c FROM Leave_Request__c WHERE Id = :requestId LIMIT 1];
        ensureIsApprover(r);
        if (r.Status__c != 'Submitted') throw new LeaveRequestException('Only Submitted can be rejected.');
        r.Status__c = 'Rejected';
        update r;
    }

    @AuraEnabled
    public static void approveCancel(Id requestId) {
        if (requestId == null) return;
        Leave_Request__c r = [SELECT Id, Status__c, Approver__c FROM Leave_Request__c WHERE Id = :requestId LIMIT 1];
        ensureIsApprover(r);
        if (r.Status__c != 'CancelSubmitted') throw new LeaveRequestException('Only CancelSubmitted can be approved.');
        r.Status__c = 'Cancelled';
        update r;
    }

    @AuraEnabled
    public static void rejectCancel(Id requestId) {
        if (requestId == null) return;
        Leave_Request__c r = [SELECT Id, Status__c, Approver__c FROM Leave_Request__c WHERE Id = :requestId LIMIT 1];
        ensureIsApprover(r);
        if (r.Status__c != 'CancelSubmitted') throw new LeaveRequestException('Only CancelSubmitted can be rejected.');
        r.Status__c = 'Approved';
        update r;
    }

    /**
     * 휴가 일수 계산 (UI에서 실시간 계산용)
     */
    @AuraEnabled
    public static Decimal calculateDays(Date startDate, String startSlot, Date endDate, String endSlot) {
        if (startDate == null || endDate == null || startSlot == null || endSlot == null) {
            return 0;
        }
        try {
            LeaveService.Range r = new LeaveService.Range(
                startDate,
                LeaveService.parseSlot(startSlot),
                endDate,
                LeaveService.parseSlot(endSlot)
            );
            return LeaveService.calculateBusinessDays(r);
        } catch (Exception e) {
            throw new LeaveRequestException('일수 계산 오류: ' + e.getMessage());
        }
    }

    /**
     * 내 휴가 목록 조회
     */
    @AuraEnabled(cacheable=true)
    public static List<Leave_Request__c> getMyLeaves(Date startDate, Date endDate) {
        if (startDate == null) startDate = Date.today();
        if (endDate == null) endDate = startDate.addDays(90);
        Id me = UserInfo.getUserId();
        return [
            SELECT Id, Name, Start_Date__c, End_Date__c, Start_Slot__c, End_Slot__c,
                   Days__c, Status__c, Leave_Type__c, Reason__c, CalendarEventId__c
            FROM Leave_Request__c
            WHERE Requester__c = :me
              AND Start_Date__c >= :startDate
              AND End_Date__c <= :endDate
            ORDER BY CreatedDate DESC, Start_Date__c DESC
        ];
    }
}