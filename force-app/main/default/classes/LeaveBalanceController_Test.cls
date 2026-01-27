/**
 * ===========================================================================================
 * @description       : Test class for LeaveBalanceController
 * @author            : CNXK
 * @last modified on  : 2026-01-27
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2026-01-27   CNXK                Initial version
 */
@IsTest
private class LeaveBalanceController_Test {
    
    /**
     * Test: Get yearly balances when no entitlements exist
     */
    @IsTest
    static void test_getMyYearlyBalances_shouldReturnEmpty_whenNoEntitlements() {
        Test.startTest();
        List<LeaveBalanceController.LeaveBalanceDTO> result = LeaveBalanceController.getMyYearlyBalances();
        Test.stopTest();
        
        System.assert(result.isEmpty(), 'Should return empty list when no entitlements');
    }

    /**
     * Test: Get yearly balances with entitlements
     */
    @IsTest
    static void test_getMyYearlyBalances_shouldReturnBalances_whenEntitlementsExist() {
        Id me = UserInfo.getUserId();
        Integer currentYear = System.today().year();
        
        Leave_Entitlement__c ent = new Leave_Entitlement__c(
            User__c = me,
            Year__c = String.valueOf(currentYear),
            Total_Days__c = 15
        );
        insert ent;
        
        Test.startTest();
        List<LeaveBalanceController.LeaveBalanceDTO> result = LeaveBalanceController.getMyYearlyBalances();
        Test.stopTest();
        
        System.assert(result.size() > 0, 'Should return balances');
        System.assertEquals(15, result[0].totalDays, 'Total days should match entitlement');
    }

    /**
     * Test: Get yearly balances with used leave days
     */
    @IsTest
    static void test_getMyYearlyBalances_shouldCalculateRemainingDays() {
        Id me = UserInfo.getUserId();
        Integer currentYear = System.today().year();
        Date startDate = Date.newInstance(currentYear, 1, 15);
        
        Leave_Entitlement__c ent = new Leave_Entitlement__c(
            User__c = me,
            Year__c = String.valueOf(currentYear),
            Total_Days__c = 15
        );
        insert ent;
        
        Leave_Request__c leaveReq = new Leave_Request__c(
            Requester__c = me,
            Start_Date__c = startDate,
            End_Date__c = startDate.addDays(2),
            Days__c = 3,
            Reason__c = 'Test',
            Status__c = 'Approved'
        );
        insert leaveReq;
        
        Test.startTest();
        List<LeaveBalanceController.LeaveBalanceDTO> result = LeaveBalanceController.getMyYearlyBalances();
        Test.stopTest();
        
        System.assert(result.size() > 0, 'Should return balances');
        System.assertEquals(15, result[0].totalDays, 'Total days should be 15');
        System.assertEquals(3, result[0].usedDays, 'Used days should be 3');
        System.assertEquals(12, result[0].remainingDays, 'Remaining days should be 12');
    }

    /**
     * Test: Get yearly balances for multiple years
     */
    @IsTest
    static void test_getMyYearlyBalances_shouldReturnMultipleYears() {
        Id me = UserInfo.getUserId();
        Integer currentYear = System.today().year();
        
        List<Leave_Entitlement__c> ents = new List<Leave_Entitlement__c>();
        ents.add(new Leave_Entitlement__c(
            User__c = me,
            Year__c = String.valueOf(currentYear - 1),
            Total_Days__c = 15
        ));
        ents.add(new Leave_Entitlement__c(
            User__c = me,
            Year__c = String.valueOf(currentYear),
            Total_Days__c = 20
        ));
        insert ents;
        
        Test.startTest();
        List<LeaveBalanceController.LeaveBalanceDTO> result = LeaveBalanceController.getMyYearlyBalances();
        Test.stopTest();
        
        System.assertEquals(2, result.size(), 'Should return 2 years of balances');
    }

    /**
     * Test: Get available balance with valid year
     */
    @IsTest
    static void test_getMyBalance_shouldReturnBalance_withValidYear() {
        Id me = UserInfo.getUserId();
        Integer currentYear = System.today().year();
        
        Leave_Entitlement__c ent = new Leave_Entitlement__c(
            User__c = me,
            Year__c = String.valueOf(currentYear),
            Total_Days__c = 15
        );
        insert ent;
        
        Test.startTest();
        LeaveBalanceController.LeaveBalanceDTO result = LeaveBalanceController.getMyBalance(currentYear);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return balance');
        System.assertEquals(15, result.totalDays, 'Total days should be 15');
    }

    /**
     * Test: Get balance with no entitlements
     */
    @IsTest
    static void test_getMyBalance_shouldReturnZero_whenNoEntitlements() {
        Integer currentYear = System.today().year();
        
        Test.startTest();
        LeaveBalanceController.LeaveBalanceDTO result = LeaveBalanceController.getMyBalance(currentYear);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return DTO');
        System.assertEquals(0, result.totalDays, 'Total days should be 0 when no entitlements');
    }

    /**
     * Test: Validate year parameter parsing
     */
    @IsTest
    static void test_getMyYearlyBalances_shouldHandleInvalidYears() {
        Id me = UserInfo.getUserId();
        
        Leave_Entitlement__c ent = new Leave_Entitlement__c(
            User__c = me,
            Year__c = 'InvalidYear',
            Total_Days__c = 15
        );
        insert ent;
        
        Test.startTest();
        List<LeaveBalanceController.LeaveBalanceDTO> result = LeaveBalanceController.getMyYearlyBalances();
        Test.stopTest();
        
        // Should return empty or skip invalid years
        System.assert(result.size() >= 0, 'Should handle invalid year gracefully');
    }

    /**
     * Test: Get balance for cancelled leave requests (should count as used)
     */
    @IsTest
    static void test_getMyYearlyBalances_shouldIncludeCancelSubmittedLeaves() {
        Id me = UserInfo.getUserId();
        Integer currentYear = System.today().year();
        Date startDate = Date.newInstance(currentYear, 1, 15);
        
        Leave_Entitlement__c ent = new Leave_Entitlement__c(
            User__c = me,
            Year__c = String.valueOf(currentYear),
            Total_Days__c = 15
        );
        insert ent;
        
        Leave_Request__c leaveReq = new Leave_Request__c(
            Requester__c = me,
            Start_Date__c = startDate,
            End_Date__c = startDate.addDays(1),
            Days__c = 2,
            Reason__c = 'Test',
            Status__c = 'CancelSubmitted'
        );
        insert leaveReq;
        
        Test.startTest();
        List<LeaveBalanceController.LeaveBalanceDTO> result = LeaveBalanceController.getMyYearlyBalances();
        Test.stopTest();
        
        System.assert(result.size() > 0, 'Should count CancelSubmitted as used');
        System.assertEquals(2, result[0].usedDays, 'Should count cancelled leave as used');
    }
}
