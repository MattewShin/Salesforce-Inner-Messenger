/**
 * ===========================================================================================
 * @description       : Test class for LeaveRequestController
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Test coverage for LeaveRequestController methods (CRUD, approval process)
 */
@IsTest
private class LeaveRequestController_Test {
    @TestSetup
    static void setup() {
        Profile p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];
        User employee = new User(
            ProfileId = p.Id,
            Username = 'leave.emp+' + String.valueOf(DateTime.now().getTime()) + '@example.com',
            Email = 'leave.emp+' + String.valueOf(DateTime.now().getTime()) + '@example.com',
            LastName = 'LeaveEmp',
            Alias = 'lemp',
            TimeZoneSidKey = 'Asia/Seoul',
            LocaleSidKey = 'ko_KR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'ko'
        );
        User manager = new User(
            ProfileId = p.Id,
            Username = 'leave.mgr+' + String.valueOf(DateTime.now().getTime()) + '@example.com',
            Email = 'leave.mgr+' + String.valueOf(DateTime.now().getTime()) + '@example.com',
            LastName = 'LeaveMgr',
            Alias = 'lmgr',
            TimeZoneSidKey = 'Asia/Seoul',
            LocaleSidKey = 'ko_KR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'ko'
        );
        insert new List<User>{ employee, manager };
        
        // Manager 관계 설정
        employee.ManagerId = manager.Id;
        update employee;
    }

    private static User employee() {
        return [SELECT Id, ManagerId FROM User WHERE LastName = 'LeaveEmp' LIMIT 1];
    }

    private static User manager() {
        return [SELECT Id FROM User WHERE LastName = 'LeaveMgr' LIMIT 1];
    }

    @IsTest
    static void test_upsertDraft() {
        User emp = employee();
        Date start = Date.newInstance(2026, 1, 5);
        Date endDate = Date.newInstance(2026, 1, 5);

        System.runAs(emp) {
            Test.startTest();
            Leave_Request__c draft = LeaveRequestController.upsertDraft(new Leave_Request__c(
                Start_Date__c = start,
                Start_Slot__c = 'AM',
                End_Date__c = endDate,
                End_Slot__c = 'PM',
                Leave_Type__c = '연차',
                Reason__c = 'Test reason'
            ));
            Test.stopTest();

            System.assertNotEquals(null, draft.Id, '초안 생성');
            System.assertEquals('Draft', draft.Status__c, '상태는 Draft');
            System.assertEquals(emp.Id, draft.Requester__c, '요청자는 본인');
            System.assertEquals(1.0, draft.Days__c, '일수 계산');
        }
    }

    @IsTest
    static void test_submit() {
        User emp = employee();
        Leave_Request__c draft = new Leave_Request__c(
            Requester__c = emp.Id,
            Start_Date__c = Date.newInstance(2026, 1, 5),
            Start_Slot__c = 'AM',
            End_Date__c = Date.newInstance(2026, 1, 5),
            End_Slot__c = 'PM',
            Status__c = 'Draft',
            Leave_Type__c = '연차'
        );
        insert draft;

        System.runAs(emp) {
            Test.startTest();
            LeaveRequestController.submit(draft.Id);
            Test.stopTest();
        }

        Leave_Request__c updated = [SELECT Status__c, Approver__c FROM Leave_Request__c WHERE Id = :draft.Id];
        System.assertEquals('Submitted', updated.Status__c, '제출 상태');
        System.assertEquals(manager().Id, updated.Approver__c, '승인자는 매니저');
    }

    @IsTest
    static void test_cancelBeforeApproval() {
        User emp = employee();
        Leave_Request__c draft = new Leave_Request__c(
            Requester__c = emp.Id,
            Start_Date__c = Date.newInstance(2026, 1, 5),
            Start_Slot__c = 'AM',
            End_Date__c = Date.newInstance(2026, 1, 5),
            End_Slot__c = 'PM',
            Status__c = 'Draft',
            Leave_Type__c = '연차'
        );
        insert draft;

        System.runAs(emp) {
            Test.startTest();
            LeaveRequestController.cancelBeforeApproval(draft.Id);
            Test.stopTest();
        }

        Leave_Request__c updated = [SELECT Status__c FROM Leave_Request__c WHERE Id = :draft.Id];
        System.assertEquals('Cancelled', updated.Status__c, '즉시 취소');
    }

    @IsTest
    static void test_requestCancelAfterApproval() {
        User emp = employee();
        User mgr = manager();
        Leave_Request__c approved = new Leave_Request__c(
            Requester__c = emp.Id,
            Approver__c = mgr.Id,
            Start_Date__c = Date.newInstance(2026, 1, 5),
            Start_Slot__c = 'AM',
            End_Date__c = Date.newInstance(2026, 1, 5),
            End_Slot__c = 'PM',
            Status__c = 'Approved',
            Leave_Type__c = '연차'
        );
        insert approved;

        System.runAs(emp) {
            Test.startTest();
            LeaveRequestController.requestCancelAfterApproval(approved.Id);
            Test.stopTest();
        }

        Leave_Request__c updated = [SELECT Status__c FROM Leave_Request__c WHERE Id = :approved.Id];
        System.assertEquals('CancelSubmitted', updated.Status__c, '취소 요청 상태');
    }

    @IsTest
    static void test_approve() {
        User emp = employee();
        User mgr = manager();
        Leave_Request__c submitted = new Leave_Request__c(
            Requester__c = emp.Id,
            Approver__c = mgr.Id,
            Start_Date__c = Date.newInstance(2026, 1, 5),
            Start_Slot__c = 'AM',
            End_Date__c = Date.newInstance(2026, 1, 5),
            End_Slot__c = 'PM',
            Status__c = 'Submitted',
            Leave_Type__c = '연차'
        );
        insert submitted;

        System.runAs(mgr) {
            Test.startTest();
            LeaveRequestController.approve(submitted.Id);
            Test.stopTest();
        }

        Leave_Request__c updated = [SELECT Status__c FROM Leave_Request__c WHERE Id = :submitted.Id];
        System.assertEquals('Approved', updated.Status__c, '승인 상태');
    }

    @IsTest
    static void test_reject() {
        User emp = employee();
        User mgr = manager();
        Leave_Request__c submitted = new Leave_Request__c(
            Requester__c = emp.Id,
            Approver__c = mgr.Id,
            Start_Date__c = Date.newInstance(2026, 1, 5),
            Start_Slot__c = 'AM',
            End_Date__c = Date.newInstance(2026, 1, 5),
            End_Slot__c = 'PM',
            Status__c = 'Submitted',
            Leave_Type__c = '연차'
        );
        insert submitted;

        System.runAs(mgr) {
            Test.startTest();
            LeaveRequestController.reject(submitted.Id);
            Test.stopTest();
        }

        Leave_Request__c updated = [SELECT Status__c FROM Leave_Request__c WHERE Id = :submitted.Id];
        System.assertEquals('Rejected', updated.Status__c, '반려 상태');
    }

    @IsTest
    static void test_approveCancel() {
        User emp = employee();
        User mgr = manager();
        Leave_Request__c cancelReq = new Leave_Request__c(
            Requester__c = emp.Id,
            Approver__c = mgr.Id,
            Start_Date__c = Date.newInstance(2026, 1, 5),
            Start_Slot__c = 'AM',
            End_Date__c = Date.newInstance(2026, 1, 5),
            End_Slot__c = 'PM',
            Status__c = 'CancelSubmitted',
            Leave_Type__c = '연차'
        );
        insert cancelReq;

        System.runAs(mgr) {
            Test.startTest();
            LeaveRequestController.approveCancel(cancelReq.Id);
            Test.stopTest();
        }

        Leave_Request__c updated = [SELECT Status__c FROM Leave_Request__c WHERE Id = :cancelReq.Id];
        System.assertEquals('Cancelled', updated.Status__c, '취소 승인');
    }

    @IsTest
    static void test_rejectCancel() {
        User emp = employee();
        User mgr = manager();
        Leave_Request__c cancelReq = new Leave_Request__c(
            Requester__c = emp.Id,
            Approver__c = mgr.Id,
            Start_Date__c = Date.newInstance(2026, 1, 5),
            Start_Slot__c = 'AM',
            End_Date__c = Date.newInstance(2026, 1, 5),
            End_Slot__c = 'PM',
            Status__c = 'CancelSubmitted',
            Leave_Type__c = '연차'
        );
        insert cancelReq;

        System.runAs(mgr) {
            Test.startTest();
            LeaveRequestController.rejectCancel(cancelReq.Id);
            Test.stopTest();
        }

        Leave_Request__c updated = [SELECT Status__c FROM Leave_Request__c WHERE Id = :cancelReq.Id];
        System.assertEquals('Approved', updated.Status__c, '취소 반려 -> Approved 복귀');
    }
}