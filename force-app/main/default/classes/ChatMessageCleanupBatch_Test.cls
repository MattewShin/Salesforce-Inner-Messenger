/**
 * ===========================================================================================
 * @description       : Test class for ChatMessageCleanupBatch
 * @author            : CNXK
 * @last modified on  : 2025-03-13
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-03-06   CNXK                Initial version - Test coverage for batch cleanup
 * 2.0   2025-03-13   CNXK                Updated to test archive chunk deletion
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
    
    @isTest
    static void testArchiveChunkDeletion() {
        // Get session
        Inner_Chat_Session__c session = [SELECT Id FROM Inner_Chat_Session__c LIMIT 1];
        
        // Create old archive chunks (older than 1 year)
        List<Inner_Chat_Message_Archive__c> oldArchives = new List<Inner_Chat_Message_Archive__c>();
        DateTime oldDate = DateTime.now().addDays(-400); // 400 days ago
        
        for (Integer i = 0; i < 3; i++) {
            oldArchives.add(new Inner_Chat_Message_Archive__c(
                Inner_Chat_Session__c = session.Id,
                Chunk_Index__c = i,
                Messages_JSON__c = '[{"id":"test","content":"test","createdDate":"' + oldDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '"}]',
                Message_Count__c = 10,
                First_Message_Date__c = oldDate,
                Last_Message_Date__c = oldDate.addDays(1)
            ));
        }
        insert oldArchives;
        
        // Create recent archive chunks (less than 1 year)
        List<Inner_Chat_Message_Archive__c> recentArchives = new List<Inner_Chat_Message_Archive__c>();
        DateTime recentDate = DateTime.now().addDays(-100); // 100 days ago
        
        for (Integer i = 3; i < 5; i++) {
            recentArchives.add(new Inner_Chat_Message_Archive__c(
                Inner_Chat_Session__c = session.Id,
                Chunk_Index__c = i,
                Messages_JSON__c = '[{"id":"test","content":"test","createdDate":"' + recentDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '"}]',
                Message_Count__c = 10,
                First_Message_Date__c = recentDate,
                Last_Message_Date__c = recentDate.addDays(1)
            ));
        }
        insert recentArchives;
        
        // Update session metadata
        session.Archived_Message_Count__c = 50; // 5 chunks * 10 messages
        update session;
        
        // Verify initial archive count
        List<Inner_Chat_Message_Archive__c> allArchives = [
            SELECT Id, Last_Message_Date__c
            FROM Inner_Chat_Message_Archive__c
            WHERE Inner_Chat_Session__c = :session.Id
        ];
        System.assertEquals(5, allArchives.size(), 'Should have 5 archive chunks initially');
        
        // Run batch job
        Test.startTest();
        ChatMessageCleanupBatch batch = new ChatMessageCleanupBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify old archive chunks are deleted
        List<Inner_Chat_Message_Archive__c> remainingArchives = [
            SELECT Id, Last_Message_Date__c
            FROM Inner_Chat_Message_Archive__c
            WHERE Inner_Chat_Session__c = :session.Id
        ];
        System.assertEquals(2, remainingArchives.size(), 'Should have 2 recent archive chunks remaining');
        
        // Verify session metadata is updated
        Inner_Chat_Session__c updatedSession = [
            SELECT Archived_Message_Count__c
            FROM Inner_Chat_Session__c
            WHERE Id = :session.Id
        ];
        System.assertEquals(20, updatedSession.Archived_Message_Count__c, 'Archived count should be updated to 20 (2 chunks * 10 messages)');
    }
    
    @isTest
    static void testCleanupWithBothActiveAndArchived() {
        // Get session
        Inner_Chat_Session__c session = [SELECT Id FROM Inner_Chat_Session__c LIMIT 1];
        
        // Create old archive chunks
        DateTime oldDate = DateTime.now().addDays(-400);
        Inner_Chat_Message_Archive__c oldArchive = new Inner_Chat_Message_Archive__c(
            Inner_Chat_Session__c = session.Id,
            Chunk_Index__c = 0,
            Messages_JSON__c = '[{"id":"test","content":"test","createdDate":"' + oldDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '"}]',
            Message_Count__c = 5,
            First_Message_Date__c = oldDate,
            Last_Message_Date__c = oldDate.addDays(1)
        );
        insert oldArchive;
        
        session.Archived_Message_Count__c = 5;
        update session;
        
        // Verify initial state
        List<Inner_Chat_Message__c> oldMessages = [
            SELECT Id FROM Inner_Chat_Message__c WHERE CreatedDate < :DateTime.now().addDays(-365)
        ];
        System.assert(oldMessages.size() > 0, 'Should have old active messages');
        
        List<Inner_Chat_Message_Archive__c> oldArchives = [
            SELECT Id FROM Inner_Chat_Message_Archive__c WHERE Last_Message_Date__c < :DateTime.now().addDays(-365)
        ];
        System.assertEquals(1, oldArchives.size(), 'Should have old archive chunk');
        
        // Run batch job
        Test.startTest();
        ChatMessageCleanupBatch batch = new ChatMessageCleanupBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify both are deleted
        List<Inner_Chat_Message__c> remainingMessages = [
            SELECT Id FROM Inner_Chat_Message__c WHERE CreatedDate < :DateTime.now().addDays(-365)
        ];
        System.assertEquals(0, remainingMessages.size(), 'Old active messages should be deleted');
        
        List<Inner_Chat_Message_Archive__c> remainingArchives = [
            SELECT Id FROM Inner_Chat_Message_Archive__c WHERE Last_Message_Date__c < :DateTime.now().addDays(-365)
        ];
        System.assertEquals(0, remainingArchives.size(), 'Old archive chunks should be deleted');
    }
}