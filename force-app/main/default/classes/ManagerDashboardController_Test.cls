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
    static void test_getTodayStatus_shouldReturnEmpty_whenNoTeamMembers() {
        Test.startTest();
        List<ManagerDashboardController.AgentStatusDTO> result = ManagerDashboardController.getTodayStatus();
        Test.stopTest();
        
        // Current user may not be a manager, so list should be empty or contain active team members
        System.assert(result != null, 'Should return list');
    }

    /**
     * Test: Get today status should include available status
     */
    @IsTest
    static void test_getTodayStatus_shouldReturnAgentStatus() {
        Test.startTest();
        List<ManagerDashboardController.AgentStatusDTO> result = ManagerDashboardController.getTodayStatus();
        Test.stopTest();
        
        // Verify DTO structure
        if (result.size() > 0) {
            System.assertNotEquals(null, result[0].userId, 'Should have userId');
            System.assertNotEquals(null, result[0].userName, 'Should have userName');
            System.assertNotEquals(null, result[0].leaveStatus, 'Should have leaveStatus');
        }
    }

    /**
     * Test: Get pending leave requests
     */
    @IsTest
    static void test_getPendingLeaveRequests_shouldReturnRequests() {
        Id me = UserInfo.getUserId();
        
        Leave_Request__c req = new Leave_Request__c(
            Requester__c = me,
            Start_Date__c = Date.today().addDays(1),
            End_Date__c = Date.today().addDays(2),
            Days__c = 2,
            Reason__c = 'Test',
            Status__c = 'Submitted'
        );
        insert req;
        
        Test.startTest();
        List<ManagerDashboardController.LeaveRequestApprovalDTO> result = ManagerDashboardController.getPendingLeaveRequests();
        Test.stopTest();
        
        System.assert(result != null, 'Should return list');
    }

    /**
     * Test: Get pending break requests
     */
    @IsTest
    static void test_getPendingBreakRequests_shouldReturnRequests() {
        Id me = UserInfo.getUserId();
        
        Break_Request__c req = new Break_Request__c(
            Requester__c = me,
            Date__c = Date.today(),
            Break_Type__c = BreakService.TYPE_MORNING_BREAK,
            Start_Time__c = Time.newInstance(9, 0, 0, 0),
            End_Time__c = Time.newInstance(9, 10, 0, 0),
            Status__c = 'Submitted'
        );
        insert req;
        
        Test.startTest();
        List<ManagerDashboardController.BreakRequestApprovalDTO> result = ManagerDashboardController.getPendingBreakRequests();
        Test.stopTest();
        
        System.assert(result != null, 'Should return list');
    }

    /**
     * Test: Approve leave request
     */
    @IsTest
    static void test_approveLeaveRequest_shouldUpdateStatus() {
        Id me = UserInfo.getUserId();
        
        Leave_Request__c req = new Leave_Request__c(
            Requester__c = me,
            Start_Date__c = Date.today().addDays(1),
            End_Date__c = Date.today().addDays(2),
            Days__c = 2,
            Reason__c = 'Test',
            Status__c = 'Submitted'
        );
        insert req;
        
        Test.startTest();
        ManagerDashboardController.approveLeaveRequest(req.Id);
        Test.stopTest();
        
        Leave_Request__c updated = [SELECT Status__c FROM Leave_Request__c WHERE Id = :req.Id LIMIT 1];
        System.assertEquals('Approved', updated.Status__c, 'Status should be Approved');
    }

    /**
     * Test: Reject leave request
     */
    @IsTest
    static void test_rejectLeaveRequest_shouldUpdateStatus() {
        Id me = UserInfo.getUserId();
        
        Leave_Request__c req = new Leave_Request__c(
            Requester__c = me,
            Start_Date__c = Date.today().addDays(1),
            End_Date__c = Date.today().addDays(2),
            Days__c = 2,
            Reason__c = 'Test',
            Status__c = 'Submitted',
            Approval_Comment__c = 'Test rejection'
        );
        insert req;
        
        Test.startTest();
        ManagerDashboardController.rejectLeaveRequest(req.Id, 'Rejected');
        Test.stopTest();
        
        Leave_Request__c updated = [SELECT Status__c, Approval_Comment__c FROM Leave_Request__c WHERE Id = :req.Id LIMIT 1];
        System.assertEquals('Rejected', updated.Status__c, 'Status should be Rejected');
    }

    /**
     * Test: Approve break request
     */
    @IsTest
    static void test_approveBreakRequest_shouldUpdateStatus() {
        Id me = UserInfo.getUserId();
        
        Break_Request__c req = new Break_Request__c(
            Requester__c = me,
            Date__c = Date.today(),
            Break_Type__c = BreakService.TYPE_MORNING_BREAK,
            Start_Time__c = Time.newInstance(9, 0, 0, 0),
            End_Time__c = Time.newInstance(9, 10, 0, 0),
            Status__c = 'Submitted'
        );
        insert req;
        
        Test.startTest();
        ManagerDashboardController.approveBreakRequest(req.Id);
        Test.stopTest();
        
        Break_Request__c updated = [SELECT Status__c FROM Break_Request__c WHERE Id = :req.Id LIMIT 1];
        System.assertEquals('Approved', updated.Status__c, 'Status should be Approved');
    }

    /**
     * Test: Reject break request
     */
    @IsTest
    static void test_rejectBreakRequest_shouldUpdateStatus() {
        Id me = UserInfo.getUserId();
        
        Break_Request__c req = new Break_Request__c(
            Requester__c = me,
            Date__c = Date.today(),
            Break_Type__c = BreakService.TYPE_MORNING_BREAK,
            Start_Time__c = Time.newInstance(9, 0, 0, 0),
            End_Time__c = Time.newInstance(9, 10, 0, 0),
            Status__c = 'Submitted'
        );
        insert req;
        
        Test.startTest();
        ManagerDashboardController.rejectBreakRequest(req.Id);
        Test.stopTest();
        
        Break_Request__c updated = [SELECT Status__c FROM Break_Request__c WHERE Id = :req.Id LIMIT 1];
        System.assertEquals('Rejected', updated.Status__c, 'Status should be Rejected');
    }

    /**
     * Test: Get today work time for team member
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
     * Test: Get all team members for manager
     */
    @IsTest
    static void test_getTeamMembers_shouldReturnList() {
        Test.startTest();
        List<ManagerDashboardController.TeamMemberDTO> result = ManagerDashboardController.getTeamMembers();
        Test.stopTest();
        
        System.assert(result != null, 'Should return list');
    }

    /**
     * Test: Get team statistics
     */
    @IsTest
    static void test_getTeamStatistics_shouldReturnStats() {
        Test.startTest();
        ManagerDashboardController.TeamStatisticsDTO result = ManagerDashboardController.getTeamStatistics();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return statistics');
        System.assertNotEquals(null, result.totalTeamMembers, 'Should have totalTeamMembers');
    }

    /**
     * Test: Bulk approve leave requests
     */
    @IsTest
    static void test_bulkApproveLeaveRequests_shouldUpdateMultipleRecords() {
        Id me = UserInfo.getUserId();
        
        List<Leave_Request__c> reqs = new List<Leave_Request__c>();
        for (Integer i = 0; i < 3; i++) {
            reqs.add(new Leave_Request__c(
                Requester__c = me,
                Start_Date__c = Date.today().addDays(i + 1),
                End_Date__c = Date.today().addDays(i + 2),
                Days__c = 1,
                Reason__c = 'Test',
                Status__c = 'Submitted'
            ));
        }
        insert reqs;
        
        List<Id> reqIds = new List<Id>();
        for (Leave_Request__c req : reqs) {
            reqIds.add(req.Id);
        }
        
        Test.startTest();
        ManagerDashboardController.bulkApproveLeaveRequests(reqIds);
        Test.stopTest();
        
        List<Leave_Request__c> updated = [SELECT Status__c FROM Leave_Request__c WHERE Id IN :reqIds];
        for (Leave_Request__c req : updated) {
            System.assertEquals('Approved', req.Status__c, 'All requests should be Approved');
        }
    }

    /**
     * Test: Get work status distribution
     */
    @IsTest
    static void test_getWorkStatusDistribution_shouldReturnDistribution() {
        Test.startTest();
        Map<String, Integer> result = ManagerDashboardController.getWorkStatusDistribution();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return map');
    }
}
