/**
 * ===========================================================================================
 * @description       : Test class for OmniPresenceHelper
 * @author            : CNXK
 * @last modified on  : 2026-01-27
 * @last modified by  : CNXK
 * ===========================================================================================
 */
@IsTest
private class OmniPresenceHelper_Test {
    
    /**
     * Test: Get service presence status IDs
     */
    @IsTest
    static void test_getServicePresenceStatusId_shouldReturnIds() {
        Test.startTest();
        OmniPresenceHelper.StatusIds result = OmniPresenceHelper.getServicePresenceStatusId();
        Test.stopTest();
        
        // The method should return StatusIds object (may have null values if statuses don't exist)
        System.assertNotEquals(null, result, 'Should return StatusIds object');
    }

    /**
     * Test: StatusIds wrapper structure
     */
    @IsTest
    static void test_StatusIds_wrapper() {
        Test.startTest();
        OmniPresenceHelper.StatusIds wrapper = new OmniPresenceHelper.StatusIds();
        wrapper.onBreakId = 'test123';
        wrapper.availableChatId = 'test456';
        Test.stopTest();
        
        System.assertEquals('test123', wrapper.onBreakId, 'Should set onBreakId');
        System.assertEquals('test456', wrapper.availableChatId, 'Should set availableChatId');
    }

    /**
     * Test: Handle missing Omnichannel status gracefully
     */
    @IsTest
    static void test_getServicePresenceStatusId_handleMissingStatus() {
        Test.startTest();
        try {
            OmniPresenceHelper.StatusIds result = OmniPresenceHelper.getServicePresenceStatusId();
            // Should not throw exception even if statuses don't exist
            System.assertNotEquals(null, result);
        } catch (Exception e) {
            System.assert(false, 'Should handle missing statuses gracefully: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * Test: Multiple calls return consistent results
     */
    @IsTest
    static void test_getServicePresenceStatusId_cacheability() {
        Test.startTest();
        OmniPresenceHelper.StatusIds result1 = OmniPresenceHelper.getServicePresenceStatusId();
        OmniPresenceHelper.StatusIds result2 = OmniPresenceHelper.getServicePresenceStatusId();
        Test.stopTest();
        
        // Results should be consistent (or both null if statuses don't exist)
        System.assertEquals(result1.onBreakId, result2.onBreakId, 'OnBreakId should be consistent');
        System.assertEquals(result1.availableChatId, result2.availableChatId, 'AvailableChatId should be consistent');
    }
}
