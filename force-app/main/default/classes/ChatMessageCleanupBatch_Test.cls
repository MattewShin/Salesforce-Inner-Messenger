/**
 * ===========================================================================================
 * @description       : Test class for ChatMessageCleanupBatch
 * @author            : CNXK
 * @last modified on  : 2025-03-06
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-03-06   CNXK                Initial version - Test coverage for batch cleanup
 */
@isTest
private class ChatMessageCleanupBatch_Test {
    
    @testSetup
    static void setupTestData() {
        // Create test chat session
        Inner_Chat_Session__c session = new Inner_Chat_Session__c(
            Name = 'Test Session'
        );
        insert session;
        
        // Create test participants
        List<Inner_Chat_Participant__c> participants = new List<Inner_Chat_Participant__c>();
        participants.add(new Inner_Chat_Participant__c(
            Inner_Chat_Session__c = session.Id,
            User__c = UserInfo.getUserId()
        ));
        insert participants;
        
        // Create old messages (older than 1 year)
        List<Inner_Chat_Message__c> oldMessages = new List<Inner_Chat_Message__c>();
        DateTime oldDate = DateTime.now().addDays(-400); // 400 days ago
        
        for (Integer i = 0; i < 10; i++) {
            oldMessages.add(new Inner_Chat_Message__c(
                Inner_Chat_Session__c = session.Id,
                Content__c = 'Old message ' + i,
                Sender__c = UserInfo.getUserId()
            ));
        }
        insert oldMessages;
        
        // Update CreatedDate for old messages (using Test.setCreatedDate)
        for (Inner_Chat_Message__c msg : oldMessages) {
            Test.setCreatedDate(msg.Id, oldDate);
        }
        
        // Create recent messages (less than 1 year)
        List<Inner_Chat_Message__c> recentMessages = new List<Inner_Chat_Message__c>();
        DateTime recentDate = DateTime.now().addDays(-100); // 100 days ago
        
        for (Integer i = 0; i < 5; i++) {
            recentMessages.add(new Inner_Chat_Message__c(
                Inner_Chat_Session__c = session.Id,
                Content__c = 'Recent message ' + i,
                Sender__c = UserInfo.getUserId()
            ));
        }
        insert recentMessages;
        
        // Update CreatedDate for recent messages
        for (Inner_Chat_Message__c msg : recentMessages) {
            Test.setCreatedDate(msg.Id, recentDate);
        }
    }
    
    @isTest
    static void testBatchCleanup() {
        // Verify initial message count
        List<Inner_Chat_Message__c> allMessages = [
            SELECT Id, CreatedDate
            FROM Inner_Chat_Message__c
        ];
        System.assertEquals(15, allMessages.size(), 'Should have 15 messages initially');
        
        // Run batch job
        Test.startTest();
        ChatMessageCleanupBatch batch = new ChatMessageCleanupBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify old messages are deleted
        List<Inner_Chat_Message__c> remainingMessages = [
            SELECT Id, CreatedDate
            FROM Inner_Chat_Message__c
        ];
        System.assertEquals(5, remainingMessages.size(), 'Should have 5 recent messages remaining');
        
        // Verify all remaining messages are recent (less than 1 year old)
        Date cutoffDate = Date.today().addDays(-365);
        DateTime cutoffDateTime = DateTime.newInstance(cutoffDate.year(), cutoffDate.month(), cutoffDate.day(), 0, 0, 0);
        
        for (Inner_Chat_Message__c msg : remainingMessages) {
            System.assert(msg.CreatedDate >= cutoffDateTime, 'All remaining messages should be less than 1 year old');
        }
    }
    
    @isTest
    static void testScheduler() {
        Test.startTest();
        String jobId = ChatMessageCleanupScheduler.scheduleDailyCleanup();
        Test.stopTest();
        
        // Verify job is scheduled
        System.assertNotEquals(null, jobId, 'Job should be scheduled');
        
        CronTrigger scheduledJob = [
            SELECT Id, CronJobDetail.Name, CronExpression
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        
        System.assertEquals('Chat Message Cleanup - Daily', scheduledJob.CronJobDetail.Name, 'Job name should match');
        System.assertEquals('0 0 2 * * ?', scheduledJob.CronExpression, 'Cron expression should match');
    }
    
    @isTest
    static void testBatchWithNoMessages() {
        // Delete all messages
        delete [SELECT Id FROM Inner_Chat_Message__c];
        
        Test.startTest();
        ChatMessageCleanupBatch batch = new ChatMessageCleanupBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Should complete without errors
        List<Inner_Chat_Message__c> remainingMessages = [
            SELECT Id
            FROM Inner_Chat_Message__c
        ];
        System.assertEquals(0, remainingMessages.size(), 'No messages should remain');
    }
}
