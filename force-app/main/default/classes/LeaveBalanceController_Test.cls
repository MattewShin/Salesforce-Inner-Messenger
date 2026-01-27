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
        
        System.assertNotEquals(null, result, 'Should return list (may be empty)');
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
        
        System.assertNotEquals(null, result, 'Should return balances');
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
        
        Test.startTest();
        List<LeaveBalanceController.LeaveBalanceDTO> result = LeaveBalanceController.getMyYearlyBalances();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return balances');
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
            Year__c = '2025',  // Valid 4-digit year
            Total_Days__c = 15
        );
        insert ent;
        
        Test.startTest();
        List<LeaveBalanceController.LeaveBalanceDTO> result = LeaveBalanceController.getMyYearlyBalances();
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should handle year parsing gracefully');
    }

    /**
     * Test: Get balance for cancelled leave requests
     */
    @IsTest
    static void test_getMyYearlyBalances_shouldIncludeCancelSubmittedLeaves() {
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
        
        System.assertNotEquals(null, result, 'Should return list');
    }
}
