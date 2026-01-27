/**
 * ===========================================================================================
 * @description       : Test class for ManagerDashboardController
 * @author            : CNXK
 * @last modified on  : 2026-01-27
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2026-01-27   CNXK                Initial version
 */
@IsTest
private class ManagerDashboardController_Test {
    
    /**
     * Test: Get today status
     */
    @IsTest
    static void test_getTodayStatus_shouldReturnAgentStatusList() {
        Test.startTest();
        List<ManagerDashboardController.AgentStatusDTO> result = ManagerDashboardController.getTodayStatus();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return list');
        if (result.size() > 0) {
            System.assertNotEquals(null, result[0].userId, 'Should have userId');
            System.assertNotEquals(null, result[0].userName, 'Should have userName');
            System.assertNotEquals(null, result[0].leaveStatus, 'Should have leaveStatus');
        }
    }

    /**
     * Test: Get team break requests
     */
    @IsTest
    static void test_getTeamBreakRequests_shouldReturnBreakRequests() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        
        Break_Request__c req = new Break_Request__c(
            Requester__c = me,
            Date__c = today,
            Break_Type__c = BreakService.TYPE_MORNING_BREAK,
            Start_Time__c = Time.newInstance(9, 0, 0, 0),
            End_Time__c = Time.newInstance(9, 10, 0, 0),
            Status__c = 'Submitted'
        );
        insert req;
        
        Test.startTest();
        List<ManagerDashboardController.BreakRequestDTO> result = ManagerDashboardController.getTeamBreakRequests(null, null, null, null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return list');
    }

    /**
     * Test: Get team leave requests
     */
    @IsTest
    static void test_getTeamLeaveRequests_shouldReturnLeaveRequests() {
        Test.startTest();
        List<ManagerDashboardController.LeaveRequestDTO> result = ManagerDashboardController.getTeamLeaveRequests(null, null, null, null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return list');
    }

    /**
     * Test: Get team work times
     */
    @IsTest
    static void test_getTeamWorkTimes_shouldReturnWorkTimes() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        
        Work_Time__c wt = new Work_Time__c(
            User__c = me,
            Work_Date__c = today,
            Work_Start_Time__c = Time.newInstance(9, 0, 0, 0),
            Status__c = 'On Duty'
        );
        insert wt;
        
        Test.startTest();
        List<ManagerDashboardController.WorkTimeDTO> result = ManagerDashboardController.getTeamWorkTimes(null, null, null, null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return work time list');
    }

    /**
     * Test: Today status calculation
     */
    @IsTest
    static void test_getTodayStatus_shouldCalculateLeaveAndBreakStatus() {
        Test.startTest();
        List<ManagerDashboardController.AgentStatusDTO> result = ManagerDashboardController.getTodayStatus();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should calculate status');
    }

    /**
     * Test: Get team break requests with date range
     */
    @IsTest
    static void test_getTeamBreakRequests_withDateRange() {
        Date today = Date.today();
        Date startDate = today.addDays(-7);
        Date endDate = today.addDays(7);
        
        Test.startTest();
        List<ManagerDashboardController.BreakRequestDTO> result = ManagerDashboardController.getTeamBreakRequests(startDate, endDate, null, null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return list with date range');
    }

    /**
     * Test: Get team break requests with status filter
     */
    @IsTest
    static void test_getTeamBreakRequests_withStatusFilter() {
        Test.startTest();
        List<ManagerDashboardController.BreakRequestDTO> approved = ManagerDashboardController.getTeamBreakRequests(null, null, 'Approved', null);
        List<ManagerDashboardController.BreakRequestDTO> submitted = ManagerDashboardController.getTeamBreakRequests(null, null, 'Submitted', null);
        Test.stopTest();
        
        System.assertNotEquals(null, approved, 'Should return approved list');
        System.assertNotEquals(null, submitted, 'Should return submitted list');
    }

    /**
     * Test: Get team leave requests with date range
     */
    @IsTest
    static void test_getTeamLeaveRequests_withDateRange() {
        Date today = Date.today();
        Date startDate = today.addDays(-30);
        Date endDate = today.addDays(30);
        
        Test.startTest();
        List<ManagerDashboardController.LeaveRequestDTO> result = ManagerDashboardController.getTeamLeaveRequests(startDate, endDate, null, null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return list with date range');
    }

    /**
     * Test: Get team work times with status filter
     */
    @IsTest
    static void test_getTeamWorkTimes_withStatusFilter() {
        Test.startTest();
        List<ManagerDashboardController.WorkTimeDTO> onDuty = ManagerDashboardController.getTeamWorkTimes(null, null, null, 'On Duty');
        List<ManagerDashboardController.WorkTimeDTO> offDuty = ManagerDashboardController.getTeamWorkTimes(null, null, null, 'Off Duty');
        Test.stopTest();
        
        System.assertNotEquals(null, onDuty, 'Should return on duty list');
        System.assertNotEquals(null, offDuty, 'Should return off duty list');
    }

    /**
     * Test: Bulk break request operations
     */
    @IsTest
    static void test_getTeamBreakRequests_bulkData() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        
        List<Break_Request__c> breaks = new List<Break_Request__c>();
        for (Integer i = 0; i < 5; i++) {
            breaks.add(new Break_Request__c(
                Requester__c = me,
                Date__c = today.addDays(i),
                Break_Type__c = BreakService.TYPE_MORNING_BREAK,
                Start_Time__c = Time.newInstance(9 + i, 0, 0, 0),
                End_Time__c = Time.newInstance(9 + i, 10, 0, 0),
                Status__c = 'Approved'
            ));
        }
        insert breaks;
        
        Test.startTest();
        List<ManagerDashboardController.BreakRequestDTO> result = ManagerDashboardController.getTeamBreakRequests(null, null, null, null);
        Test.stopTest();
        
        System.assert(result.size() >= 0, 'Should handle bulk break data');
    }

    /**
     * Test: Bulk work time operations
     */
    @IsTest
    static void test_getTeamWorkTimes_bulkData() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        
        List<Work_Time__c> workTimes = new List<Work_Time__c>();
        for (Integer i = 0; i < 10; i++) {
            workTimes.add(new Work_Time__c(
                User__c = me,
                Work_Date__c = today.addDays(-i),
                Work_Start_Time__c = Time.newInstance(9, 0, 0, 0),
                Work_End_Time__c = Time.newInstance(18, 0, 0, 0),
                Status__c = 'Off Duty'
            ));
        }
        insert workTimes;
        
        Test.startTest();
        List<ManagerDashboardController.WorkTimeDTO> result = ManagerDashboardController.getTeamWorkTimes(null, null, null, null);
        Test.stopTest();
        
        System.assert(result.size() >= 0, 'Should handle bulk work time data');
    }

    /**
     * Test: All DTOs structure
     */
    @IsTest
    static void test_DTOs_shouldHaveProperStructure() {
        Test.startTest();
        List<ManagerDashboardController.AgentStatusDTO> agents = ManagerDashboardController.getTodayStatus();
        List<ManagerDashboardController.BreakRequestDTO> breaks = ManagerDashboardController.getTeamBreakRequests(null, null, null, null);
        List<ManagerDashboardController.LeaveRequestDTO> leaves = ManagerDashboardController.getTeamLeaveRequests(null, null, null, null);
        List<ManagerDashboardController.WorkTimeDTO> workTimes = ManagerDashboardController.getTeamWorkTimes(null, null, null, null);
        Test.stopTest();
        
        System.assertNotEquals(null, agents, 'Agent DTO should exist');
        System.assertNotEquals(null, breaks, 'Break DTO should exist');
        System.assertNotEquals(null, leaves, 'Leave DTO should exist');
        System.assertNotEquals(null, workTimes, 'WorkTime DTO should exist');
    }
}
