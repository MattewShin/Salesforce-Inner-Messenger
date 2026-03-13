/**
 * ===========================================================================================
 * @description       : Test class for NoteController
 * @author            : CNXK
 * @last modified on  : 2025-03-06
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-03-06   CNXK                Initial version - Test coverage for Note CRUD operations
 */
@isTest
private class NoteController_Test {
    
    @testSetup
    static void setupTestData() {
        // Create test users
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User sender = new User(
            FirstName = 'Test',
            LastName = 'Sender',
            Email = 'testsender@test.com',
            Username = 'testsender@test.com.test',
            Alias = 'tsender',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'Asia/Seoul',
            LocaleSidKey = 'ko_KR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'ko'
        );
        
        User recipient = new User(
            FirstName = 'Test',
            LastName = 'Recipient',
            Email = 'testrecipient@test.com',
            Username = 'testrecipient@test.com.test',
            Alias = 'trecip',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'Asia/Seoul',
            LocaleSidKey = 'ko_KR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'ko'
        );
        
        insert new List<User>{ sender, recipient };
    }
    
    @isTest
    static void testSendNote() {
        User sender = [SELECT Id FROM User WHERE Username = 'testsender@test.com.test' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE Username = 'testrecipient@test.com.test' LIMIT 1];
        
        Test.startTest();
        System.runAs(sender) {
            Id noteId = NoteController.sendNote(
                recipient.Id,
                'Test Subject',
                'Test Content',
                null
            );
            
            System.assertNotEquals(null, noteId, 'Note should be created');
            
            List<Inner_Note__c> notes = [
                SELECT Id, Subject__c, Content__c, Sender__c, Recipient__c, Is_Read__c
                FROM Inner_Note__c
                WHERE Id = :noteId
            ];
            
            System.assertEquals(1, notes.size(), 'Note should exist');
            System.assertEquals('Test Subject', notes[0].Subject__c);
            System.assertEquals('Test Content', notes[0].Content__c);
            System.assertEquals(sender.Id, notes[0].Sender__c);
            System.assertEquals(recipient.Id, notes[0].Recipient__c);
            System.assertEquals(false, notes[0].Is_Read__c, 'Note should be unread initially');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testSendNoteToSelf() {
        User sender = [SELECT Id FROM User WHERE Username = 'testsender@test.com.test' LIMIT 1];
        
        Test.startTest();
        System.runAs(sender) {
            try {
                NoteController.sendNote(
                    sender.Id,
                    'Test Subject',
                    'Test Content',
                    null
                );
                System.assert(false, 'Should throw exception when sending to self');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('cannot send'), 'Should prevent self-sending');
            }
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetReceivedNotes() {
        User sender = [SELECT Id FROM User WHERE Username = 'testsender@test.com.test' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE Username = 'testrecipient@test.com.test' LIMIT 1];
        
        // Create test notes
        List<Inner_Note__c> notes = new List<Inner_Note__c>();
        notes.add(new Inner_Note__c(
            Sender__c = sender.Id,
            Recipient__c = recipient.Id,
            Subject__c = 'Unread Note',
            Content__c = 'Content 1',
            Is_Read__c = false
        ));
        notes.add(new Inner_Note__c(
            Sender__c = sender.Id,
            Recipient__c = recipient.Id,
            Subject__c = 'Read Note',
            Content__c = 'Content 2',
            Is_Read__c = true,
            Read_At__c = System.now()
        ));
        insert notes;
        
        Test.startTest();
        System.runAs(recipient) {
            List<NoteController.NoteWrapper> received = NoteController.getReceivedNotes(false);
            System.assertEquals(2, received.size(), 'Should return 2 notes');
            
            List<NoteController.NoteWrapper> unreadOnly = NoteController.getReceivedNotes(true);
            System.assertEquals(1, unreadOnly.size(), 'Should return 1 unread note');
            System.assertEquals('Unread Note', unreadOnly[0].subject);
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetSentNotes() {
        User sender = [SELECT Id FROM User WHERE Username = 'testsender@test.com.test' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE Username = 'testrecipient@test.com.test' LIMIT 1];
        
        // Create test note
        Inner_Note__c note = new Inner_Note__c(
            Sender__c = sender.Id,
            Recipient__c = recipient.Id,
            Subject__c = 'Sent Note',
            Content__c = 'Content'
        );
        insert note;
        
        Test.startTest();
        System.runAs(sender) {
            List<NoteController.NoteWrapper> sent = NoteController.getSentNotes();
            System.assertEquals(1, sent.size(), 'Should return 1 sent note');
            System.assertEquals('Sent Note', sent[0].subject);
        }
        Test.stopTest();
    }
    
    @isTest
    static void testMarkAsRead() {
        User sender = [SELECT Id FROM User WHERE Username = 'testsender@test.com.test' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE Username = 'testrecipient@test.com.test' LIMIT 1];
        
        Inner_Note__c note = new Inner_Note__c(
            Sender__c = sender.Id,
            Recipient__c = recipient.Id,
            Subject__c = 'Test Note',
            Content__c = 'Content',
            Is_Read__c = false
        );
        insert note;
        
        Test.startTest();
        System.runAs(recipient) {
            NoteController.markAsRead(note.Id);
            
            Inner_Note__c updatedNote = [
                SELECT Id, Is_Read__c, Read_At__c
                FROM Inner_Note__c
                WHERE Id = :note.Id
            ];
            
            System.assertEquals(true, updatedNote.Is_Read__c, 'Note should be marked as read');
            System.assertNotEquals(null, updatedNote.Read_At__c, 'Read_At should be set');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testToggleImportant() {
        User sender = [SELECT Id FROM User WHERE Username = 'testsender@test.com.test' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE Username = 'testrecipient@test.com.test' LIMIT 1];
        
        Inner_Note__c note = new Inner_Note__c(
            Sender__c = sender.Id,
            Recipient__c = recipient.Id,
            Subject__c = 'Test Note',
            Content__c = 'Content',
            Is_Important__c = false
        );
        insert note;
        
        Test.startTest();
        System.runAs(recipient) {
            NoteController.toggleImportant(note.Id, true);
            
            Inner_Note__c updatedNote = [
                SELECT Id, Is_Important__c
                FROM Inner_Note__c
                WHERE Id = :note.Id
            ];
            
            System.assertEquals(true, updatedNote.Is_Important__c, 'Note should be marked as important');
            
            NoteController.toggleImportant(note.Id, false);
            
            updatedNote = [
                SELECT Id, Is_Important__c
                FROM Inner_Note__c
                WHERE Id = :note.Id
            ];
            
            System.assertEquals(false, updatedNote.Is_Important__c, 'Note should be unmarked');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteNoteReceived() {
        User sender = [SELECT Id FROM User WHERE Username = 'testsender@test.com.test' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE Username = 'testrecipient@test.com.test' LIMIT 1];
        
        Inner_Note__c note = new Inner_Note__c(
            Sender__c = sender.Id,
            Recipient__c = recipient.Id,
            Subject__c = 'Test Note',
            Content__c = 'Content',
            Recipient_Deleted__c = false
        );
        insert note;
        
        Test.startTest();
        System.runAs(recipient) {
            NoteController.deleteNote(note.Id, 'received');
            
            Inner_Note__c deletedNote = [
                SELECT Id, Recipient_Deleted__c
                FROM Inner_Note__c
                WHERE Id = :note.Id
            ];
            
            System.assertEquals(true, deletedNote.Recipient_Deleted__c, 'Recipient deleted flag should be set');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteNoteSent() {
        User sender = [SELECT Id FROM User WHERE Username = 'testsender@test.com.test' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE Username = 'testrecipient@test.com.test' LIMIT 1];
        
        Inner_Note__c note = new Inner_Note__c(
            Sender__c = sender.Id,
            Recipient__c = recipient.Id,
            Subject__c = 'Test Note',
            Content__c = 'Content',
            Sender_Deleted__c = false
        );
        insert note;
        
        Test.startTest();
        System.runAs(sender) {
            NoteController.deleteNote(note.Id, 'sent');
            
            Inner_Note__c deletedNote = [
                SELECT Id, Sender_Deleted__c
                FROM Inner_Note__c
                WHERE Id = :note.Id
            ];
            
            System.assertEquals(true, deletedNote.Sender_Deleted__c, 'Sender deleted flag should be set');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteNoteBothSides() {
        User sender = [SELECT Id FROM User WHERE Username = 'testsender@test.com.test' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE Username = 'testrecipient@test.com.test' LIMIT 1];
        
        Inner_Note__c note = new Inner_Note__c(
            Sender__c = sender.Id,
            Recipient__c = recipient.Id,
            Subject__c = 'Test Note',
            Content__c = 'Content',
            Sender_Deleted__c = false,
            Recipient_Deleted__c = false
        );
        insert note;
        
        Test.startTest();
        System.runAs(sender) {
            NoteController.deleteNote(note.Id, 'sent');
        }
        
        System.runAs(recipient) {
            NoteController.deleteNote(note.Id, 'received');
        }
        
        List<Inner_Note__c> remainingNotes = [
            SELECT Id
            FROM Inner_Note__c
            WHERE Id = :note.Id
        ];
        
        System.assertEquals(0, remainingNotes.size(), 'Note should be hard deleted when both sides delete');
        Test.stopTest();
    }
    
    @isTest
    static void testGetUnreadCount() {
        User sender = [SELECT Id FROM User WHERE Username = 'testsender@test.com.test' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE Username = 'testrecipient@test.com.test' LIMIT 1];
        
        // Create test notes
        List<Inner_Note__c> notes = new List<Inner_Note__c>();
        for (Integer i = 0; i < 3; i++) {
            notes.add(new Inner_Note__c(
                Sender__c = sender.Id,
                Recipient__c = recipient.Id,
                Subject__c = 'Note ' + i,
                Content__c = 'Content',
                Is_Read__c = (i < 2) ? false : true // 2 unread, 1 read
            ));
        }
        insert notes;
        
        Test.startTest();
        System.runAs(recipient) {
            Integer count = NoteController.getUnreadCount();
            System.assertEquals(2, count, 'Should return 2 unread notes');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testSearchUsers() {
        Test.startTest();
        List<User> users = NoteController.searchUsers('Test');
        System.assert(users.size() > 0, 'Should return users');
        Test.stopTest();
    }
    
    @isTest
    static void testGetNoteDetail() {
        User sender = [SELECT Id FROM User WHERE Username = 'testsender@test.com.test' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE Username = 'testrecipient@test.com.test' LIMIT 1];
        
        Inner_Note__c note = new Inner_Note__c(
            Sender__c = sender.Id,
            Recipient__c = recipient.Id,
            Subject__c = 'Test Note',
            Content__c = 'Test Content'
        );
        insert note;
        
        Test.startTest();
        System.runAs(recipient) {
            NoteController.NoteWrapper detail = NoteController.getNoteDetail(note.Id);
            System.assertNotEquals(null, detail, 'Note detail should be returned');
            System.assertEquals('Test Note', detail.subject);
            System.assertEquals('Test Content', detail.content);
        }
        Test.stopTest();
    }
    
    @isTest
    static void testUploadImageFromBase64() {
        String base64Data = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
        
        Test.startTest();
        Id contentDocId = NoteController.uploadImageFromBase64(base64Data, 'test.png');
        System.assertNotEquals(null, contentDocId, 'ContentDocument should be created');
        Test.stopTest();
    }
}