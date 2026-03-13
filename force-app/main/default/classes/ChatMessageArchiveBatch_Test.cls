/**
 * ===========================================================================================
 * @description       : Test class for ChatMessageArchiveBatch
 * @author            : CNXK
 * @last modified on  : 2025-03-13
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-03-13   CNXK                Initial version - Test coverage for archive batch
 */
@isTest
private class ChatMessageArchiveBatch_Test {
    
    @testSetup
    static void setupTestData() {
        // Create test chat session
        Inner_Chat_Session__c session = new Inner_Chat_Session__c(
            Name = 'Test Session',
            Type__c = 'Direct'
        );
        insert session;
        
        // Create test participants
        List<Inner_Chat_Participant__c> participants = new List<Inner_Chat_Participant__c>();
        participants.add(new Inner_Chat_Participant__c(
            Inner_Chat_Session__c = session.Id,
            User__c = UserInfo.getUserId()
        ));
        insert participants;
        
        // Create old messages (older than 3 months - 90 days)
        List<Inner_Chat_Message__c> oldMessages = new List<Inner_Chat_Message__c>();
        DateTime oldDate = DateTime.now().addDays(-120); // 120 days ago
        
        for (Integer i = 0; i < 15; i++) {
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
        
        // Create recent messages (less than 3 months)
        List<Inner_Chat_Message__c> recentMessages = new List<Inner_Chat_Message__c>();
        DateTime recentDate = DateTime.now().addDays(-30); // 30 days ago
        
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
    static void testBatchArchive() {
        // Verify initial message count
        List<Inner_Chat_Message__c> allMessages = [
            SELECT Id, CreatedDate, Inner_Chat_Session__c
            FROM Inner_Chat_Message__c
        ];
        System.assertEquals(20, allMessages.size(), 'Should have 20 messages initially');
        
        // Get session ID
        Inner_Chat_Session__c session = [SELECT Id FROM Inner_Chat_Session__c LIMIT 1];
        
        // Verify no archive chunks exist yet
        List<Inner_Chat_Message_Archive__c> archivesBefore = [
            SELECT Id
            FROM Inner_Chat_Message_Archive__c
            WHERE Inner_Chat_Session__c = :session.Id
        ];
        System.assertEquals(0, archivesBefore.size(), 'Should have no archive chunks initially');
        
        // Run batch job
        Test.startTest();
        ChatMessageArchiveBatch batch = new ChatMessageArchiveBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify old messages are archived (deleted from active)
        List<Inner_Chat_Message__c> remainingMessages = [
            SELECT Id, CreatedDate
            FROM Inner_Chat_Message__c
        ];
        System.assertEquals(5, remainingMessages.size(), 'Should have 5 recent messages remaining');
        
        // Verify archive chunks were created
        List<Inner_Chat_Message_Archive__c> archives = [
            SELECT Id, Chunk_Index__c, Message_Count__c, Messages_JSON__c,
                   First_Message_Date__c, Last_Message_Date__c
            FROM Inner_Chat_Message_Archive__c
            WHERE Inner_Chat_Session__c = :session.Id
            ORDER BY Chunk_Index__c ASC
        ];
        System.assert(archives.size() > 0, 'Should have at least one archive chunk');
        
        // Verify total archived message count (should be 15 old messages)
        Integer totalArchived = 0;
        for (Inner_Chat_Message_Archive__c archive : archives) {
            totalArchived += Integer.valueOf(archive.Message_Count__c);
            System.assertNotEquals(null, archive.Messages_JSON__c, 'Archive should have JSON data');
            System.assertNotEquals(null, archive.First_Message_Date__c, 'Archive should have first message date');
            System.assertNotEquals(null, archive.Last_Message_Date__c, 'Archive should have last message date');
        }
        System.assertEquals(15, totalArchived, 'Should have archived 15 messages');
        
        // Verify session metadata was updated
        Inner_Chat_Session__c updatedSession = [
            SELECT Active_Message_Count__c, Archived_Message_Count__c, 
                   Archive_Storage_Type__c, Last_Archive_Date__c
            FROM Inner_Chat_Session__c
            WHERE Id = :session.Id
        ];
        System.assertEquals(5, updatedSession.Active_Message_Count__c, 'Active message count should be 5');
        System.assertEquals(15, updatedSession.Archived_Message_Count__c, 'Archived message count should be 15');
        System.assertEquals('JSON', updatedSession.Archive_Storage_Type__c, 'Archive storage type should be JSON');
        System.assertNotEquals(null, updatedSession.Last_Archive_Date__c, 'Last archive date should be set');
    }
    
    @isTest
    static void testArchiveJSONStructure() {
        // Get session and old messages
        Inner_Chat_Session__c session = [SELECT Id FROM Inner_Chat_Session__c LIMIT 1];
        
        // Run batch job
        Test.startTest();
        ChatMessageArchiveBatch batch = new ChatMessageArchiveBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify JSON structure
        List<Inner_Chat_Message_Archive__c> archives = [
            SELECT Messages_JSON__c, Message_Count__c
            FROM Inner_Chat_Message_Archive__c
            WHERE Inner_Chat_Session__c = :session.Id
            LIMIT 1
        ];
        
        if (!archives.isEmpty()) {
            String jsonData = archives[0].Messages_JSON__c;
            System.assertNotEquals(null, jsonData, 'JSON data should not be null');
            
            // Parse JSON to verify structure
            List<Object> messages = (List<Object>) JSON.deserializeUntyped(jsonData);
            System.assert(messages.size() > 0, 'JSON should contain messages');
            
            // Verify message structure
            Map<String, Object> firstMessage = (Map<String, Object>) messages[0];
            System.assert(firstMessage.containsKey('id'), 'Message should have id');
            System.assert(firstMessage.containsKey('content'), 'Message should have content');
            System.assert(firstMessage.containsKey('senderId'), 'Message should have senderId');
            System.assert(firstMessage.containsKey('createdDate'), 'Message should have createdDate');
        }
    }
    
    @isTest
    static void testBatchWithNoMessages() {
        // Delete all messages
        delete [SELECT Id FROM Inner_Chat_Message__c];
        
        Test.startTest();
        ChatMessageArchiveBatch batch = new ChatMessageArchiveBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Should complete without errors
        List<Inner_Chat_Message__c> remainingMessages = [
            SELECT Id
            FROM Inner_Chat_Message__c
        ];
        System.assertEquals(0, remainingMessages.size(), 'No messages should remain');
        
        List<Inner_Chat_Message_Archive__c> archives = [
            SELECT Id
            FROM Inner_Chat_Message_Archive__c
        ];
        System.assertEquals(0, archives.size(), 'No archive chunks should be created');
    }
    
    @isTest
    static void testBatchWithAlreadyArchivedSession() {
        // Get session
        Inner_Chat_Session__c session = [SELECT Id FROM Inner_Chat_Session__c LIMIT 1];
        
        // Mark session as already archived
        session.Archive_Storage_Type__c = 'JSON';
        update session;
        
        // Run batch job
        Test.startTest();
        ChatMessageArchiveBatch batch = new ChatMessageArchiveBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Should not process messages from already archived session
        // (The query filters out sessions with Archive_Storage_Type__c = 'JSON')
        List<Inner_Chat_Message__c> allMessages = [
            SELECT Id
            FROM Inner_Chat_Message__c
        ];
        System.assertEquals(20, allMessages.size(), 'All messages should remain (not processed)');
    }
    
    @isTest
    static void testChunkSplitting() {
        // Create a session with many old messages (more than chunk size)
        Inner_Chat_Session__c session = new Inner_Chat_Session__c(
            Name = 'Large Session',
            Type__c = 'Group'
        );
        insert session;
        
        // Create 250 old messages (should create 3 chunks of 100 each)
        List<Inner_Chat_Message__c> manyMessages = new List<Inner_Chat_Message__c>();
        DateTime oldDate = DateTime.now().addDays(-120);
        
        for (Integer i = 0; i < 250; i++) {
            manyMessages.add(new Inner_Chat_Message__c(
                Inner_Chat_Session__c = session.Id,
                Content__c = 'Message ' + i,
                Sender__c = UserInfo.getUserId()
            ));
        }
        insert manyMessages;
        
        // Update CreatedDate
        for (Inner_Chat_Message__c msg : manyMessages) {
            Test.setCreatedDate(msg.Id, oldDate);
        }
        
        // Run batch job
        Test.startTest();
        ChatMessageArchiveBatch batch = new ChatMessageArchiveBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify chunks were created (should be 3 chunks: 100 + 100 + 50)
        List<Inner_Chat_Message_Archive__c> archives = [
            SELECT Chunk_Index__c, Message_Count__c
            FROM Inner_Chat_Message_Archive__c
            WHERE Inner_Chat_Session__c = :session.Id
            ORDER BY Chunk_Index__c ASC
        ];
        
        System.assertEquals(3, archives.size(), 'Should have 3 chunks');
        System.assertEquals(0, archives[0].Chunk_Index__c, 'First chunk index should be 0');
        System.assertEquals(1, archives[1].Chunk_Index__c, 'Second chunk index should be 1');
        System.assertEquals(2, archives[2].Chunk_Index__c, 'Third chunk index should be 2');
        
        // Verify message counts
        Integer totalArchived = 0;
        for (Inner_Chat_Message_Archive__c archive : archives) {
            totalArchived += Integer.valueOf(archive.Message_Count__c);
        }
        System.assertEquals(250, totalArchived, 'Should have archived all 250 messages');
    }
}
