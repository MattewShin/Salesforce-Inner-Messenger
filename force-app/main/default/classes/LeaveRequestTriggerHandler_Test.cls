/**
 * ===========================================================================================
 * @description       : Test class for LeaveRequestTriggerHandler
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Test coverage for LeaveRequestTriggerHandler (calendar sync, approver sharing, approval process cancellation)
 */
@IsTest
private class LeaveRequestTriggerHandler_Test {
    @TestSetup
    static void setup() {
        Profile p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];
        User employee = new User(
            ProfileId = p.Id,
            Username = 'leave.trigger.emp+' + String.valueOf(DateTime.now().getTime()) + '@example.com',
            Email = 'leave.trigger.emp+' + String.valueOf(DateTime.now().getTime()) + '@example.com',
            LastName = 'LeaveTriggerEmp',
            Alias = 'ltemp',
            TimeZoneSidKey = 'Asia/Seoul',
            LocaleSidKey = 'ko_KR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'ko'
        );
        User manager = new User(
            ProfileId = p.Id,
            Username = 'leave.trigger.mgr+' + String.valueOf(DateTime.now().getTime()) + '@example.com',
            Email = 'leave.trigger.mgr+' + String.valueOf(DateTime.now().getTime()) + '@example.com',
            LastName = 'LeaveTriggerMgr',
            Alias = 'ltmgr',
            TimeZoneSidKey = 'Asia/Seoul',
            LocaleSidKey = 'ko_KR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'ko'
        );
        insert new List<User>{ employee, manager };
        
        employee.ManagerId = manager.Id;
        update employee;
    }

    private static User employee() {
        return [SELECT Id, ManagerId FROM User WHERE LastName = 'LeaveTriggerEmp' LIMIT 1];
    }

    private static User manager() {
        return [SELECT Id FROM User WHERE LastName = 'LeaveTriggerMgr' LIMIT 1];
    }

    @IsTest
    static void test_daysAutoCalculation() {
        User emp = employee();
        Date start = Date.newInstance(2026, 1, 5); // 월요일
        Date endDate = Date.newInstance(2026, 1, 5);

        System.runAs(emp) {
            Test.startTest();
            Leave_Request__c req = new Leave_Request__c(
                Requester__c = emp.Id,
                Start_Date__c = start,
                Start_Slot__c = 'AM',
                End_Date__c = endDate,
                End_Slot__c = 'PM',
                Status__c = 'Draft',
                Leave_Type__c = '연차'
            );
            insert req;
            Test.stopTest();
        }

        Leave_Request__c updated = [SELECT Days__c FROM Leave_Request__c WHERE Requester__c = :emp.Id LIMIT 1];
        System.assertEquals(1.0, updated.Days__c, '일수 자동 계산');
    }

    @IsTest
    static void test_approverSharing() {
        User emp = employee();
        User mgr = manager();

        System.runAs(emp) {
            Test.startTest();
            Leave_Request__c req = new Leave_Request__c(
                Requester__c = emp.Id,
                Approver__c = mgr.Id,
                Start_Date__c = Date.newInstance(2026, 1, 5),
                Start_Slot__c = 'AM',
                End_Date__c = Date.newInstance(2026, 1, 5),
                End_Slot__c = 'PM',
                Status__c = 'Submitted',
                Leave_Type__c = '연차'
            );
            insert req;
            Test.stopTest();
        }

        // 매니저가 공유 레코드를 조회할 수 있는지 확인
        System.runAs(mgr) {
            List<Leave_Request__c> shared = [SELECT Id FROM Leave_Request__c WHERE Requester__c = :emp.Id];
            System.assertEquals(1, shared.size(), '매니저 Read 공유 확인');
        }
    }

    @IsTest
    static void test_calendarEventSync_approved() {
        User emp = employee();
        User mgr = manager();

        System.runAs(emp) {
            Leave_Request__c req = new Leave_Request__c(
                Requester__c = emp.Id,
                Approver__c = mgr.Id,
                Start_Date__c = Date.newInstance(2026, 1, 5),
                Start_Slot__c = 'AM',
                End_Date__c = Date.newInstance(2026, 1, 5),
                End_Slot__c = 'PM',
                Status__c = 'Submitted',
                Leave_Type__c = '연차'
            );
            insert req;

            Test.startTest();
            req.Status__c = 'Approved';
            update req;
            Test.stopTest();
        }

        Leave_Request__c updated = [SELECT CalendarEventId__c FROM Leave_Request__c WHERE Requester__c = :emp.Id LIMIT 1];
        System.assertNotEquals(null, updated.CalendarEventId__c, 'Event 생성 확인');

        List<Event> events = [SELECT Id FROM Event WHERE WhatId = :updated.Id];
        System.assertEquals(1, events.size(), 'Event 존재 확인');
    }

    @IsTest
    static void test_calendarEventSync_cancelSubmitted() {
        User emp = employee();
        User mgr = manager();

        System.runAs(emp) {
            Leave_Request__c req = new Leave_Request__c(
                Requester__c = emp.Id,
                Approver__c = mgr.Id,
                Start_Date__c = Date.newInstance(2026, 1, 5),
                Start_Slot__c = 'AM',
                End_Date__c = Date.newInstance(2026, 1, 5),
                End_Slot__c = 'PM',
                Status__c = 'Approved',
                Leave_Type__c = '연차'
            );
            insert req;
            req.Status__c = 'Approved';
            update req; // Event 생성

            Test.startTest();
            req.Status__c = 'CancelSubmitted';
            update req; // Event 삭제(숨김)
            Test.stopTest();
        }

        Leave_Request__c updated = [SELECT CalendarEventId__c FROM Leave_Request__c WHERE Requester__c = :emp.Id LIMIT 1];
        System.assertEquals(null, updated.CalendarEventId__c, 'Event 삭제 확인');

        List<Event> events = [SELECT Id FROM Event WHERE WhatId = :updated.Id];
        System.assertEquals(0, events.size(), 'Event 삭제 확인');
    }
}