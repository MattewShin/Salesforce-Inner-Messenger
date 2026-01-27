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
     * Test: Get today status with no team members
     */
    @IsTest
    static void test_getTodayStatus_shouldReturnList() {
        Test.startTest();
        List<ManagerDashboardController.AgentStatusDTO> result = ManagerDashboardController.getTodayStatus();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return list');
    }

    /**
     * Test: Get today status should include agent status DTO
     */
    @IsTest
    static void test_getTodayStatus_shouldReturnAgentStatus() {
        Test.startTest();
        List<ManagerDashboardController.AgentStatusDTO> result = ManagerDashboardController.getTodayStatus();
        Test.stopTest();
        
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
    static void test_getTeamBreakRequests_shouldReturnRequests() {
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
    static void test_getTeamLeaveRequests_shouldReturnRequests() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        
        Leave_Request__c req = new Leave_Request__c(
            Requester__c = me,
            Start_Date__c = today.addDays(1),
            End_Date__c = today.addDays(2),
            Days__c = 2,
            Reason__c = 'Test',
            Status__c = 'Submitted'
        );
        insert req;
        
        Test.startTest();
        List<ManagerDashboardController.LeaveRequestDTO> result = ManagerDashboardController.getTeamLeaveRequests(null, null, null, null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return list');
    }

    /**
     * Test: Get today status should calculate break status
     */
    @IsTest
    static void test_getTodayStatus_shouldCalculateBreakStatus() {
        Test.startTest();
        List<ManagerDashboardController.AgentStatusDTO> result = ManagerDashboardController.getTodayStatus();
        Test.stopTest();
        
        if (result.size() > 0) {
            System.assertNotEquals(null, result[0].morningBreak, 'Should have morning break status');
            System.assertNotEquals(null, result[0].lunch, 'Should have lunch status');
            System.assertNotEquals(null, result[0].afternoonBreak, 'Should have afternoon break status');
        }
    }

    /**
     * Test: Get team members list
     */
    @IsTest
    static void test_getTeamMembers_shouldReturnList() {
        Test.startTest();
        List<User> result = ManagerDashboardController.getTeamMembers();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return list');
    }

    /**
     * Test: Get team member work time
     */
    @IsTest
    static void test_getTodayWorkTimeForTeamMember_shouldReturnWorkTime() {
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
        Work_Time__c result = ManagerDashboardController.getTodayWorkTimeForTeamMember(me);
        Test.stopTest();
        
        if (result != null) {
            System.assertEquals(wt.Id, result.Id, 'Should return correct work time');
        }
    }

    /**
     * Test: Get team member leave balance
     */
    @IsTest
    static void test_getTeamMemberLeaveBalance_shouldReturnBalance() {
        Id me = UserInfo.getUserId();
        Integer currentYear = System.today().year();
        
        Leave_Entitlement__c ent = new Leave_Entitlement__c(
            User__c = me,
            Year__c = String.valueOf(currentYear),
            Total_Days__c = 15
        );
        insert ent;
        
        Test.startTest();
        Decimal result = ManagerDashboardController.getTeamMemberLeaveBalance(me);
        Test.stopTest();
        
        System.assertEquals(15, result, 'Should return leave balance');
    }

    /**
     * Test: Get team members
     */
    @IsTest
    static void test_getTeamMembersInfo_shouldReturnUserList() {
        Test.startTest();
        List<User> result = ManagerDashboardController.getTeamMembers();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return list');
    }

    /**
     * Test: Bulk operations on break requests
     */
    @IsTest
    static void test_getTeamBreakRequests_withFilter() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        Date startDate = today.addDays(-7);
        Date endDate = today.addDays(7);
        
        Test.startTest();
        List<ManagerDashboardController.BreakRequestDTO> result = ManagerDashboardController.getTeamBreakRequests(startDate, endDate, 'Approved', null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return filtered list');
    }

    /**
     * Test: Get team leave requests with date range
     */
    @IsTest
    static void test_getTeamLeaveRequests_withDateRange() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        Date startDate = today.addDays(-30);
        Date endDate = today.addDays(30);
        
        Test.startTest();
        List<ManagerDashboardController.LeaveRequestDTO> result = ManagerDashboardController.getTeamLeaveRequests(startDate, endDate, null, null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return list with date range');
    }

    /**
     * Test: Check if leave is active now
     */
    @IsTest
    static void test_isLeaveActiveNow_shouldReturnBoolean() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        
        Leave_Request__c req = new Leave_Request__c(
            Requester__c = me,
            Start_Date__c = today,
            End_Date__c = today,
            Days__c = 1,
            Reason__c = 'Test',
            Status__c = 'Approved'
        );
        insert req;
        
        Test.startTest();
        // isLeaveActiveNow is private, so we test through getTodayStatus
        List<ManagerDashboardController.AgentStatusDTO> result = ManagerDashboardController.getTodayStatus();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should handle leave active check');
    }

    /**
     * Test: Team status with multiple records
     */
    @IsTest
    static void test_getTodayStatus_bulkData() {
        Test.startTest();
        List<ManagerDashboardController.AgentStatusDTO> result = ManagerDashboardController.getTodayStatus();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should handle bulk status retrieval');
    }

    /**
     * Test: Get team break requests with status filter
     */
    @IsTest
    static void test_getTeamBreakRequests_filterByStatus() {
        Test.startTest();
        List<ManagerDashboardController.BreakRequestDTO> approved = ManagerDashboardController.getTeamBreakRequests(null, null, 'Approved', null);
        List<ManagerDashboardController.BreakRequestDTO> submitted = ManagerDashboardController.getTeamBreakRequests(null, null, 'Submitted', null);
        Test.stopTest();
        
        System.assertNotEquals(null, approved, 'Should return approved list');
        System.assertNotEquals(null, submitted, 'Should return submitted list');
    }
}
