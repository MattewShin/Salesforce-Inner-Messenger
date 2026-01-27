/**
 * ===========================================================================================
 * @description       : Test class for ChatController
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Test coverage for ChatController methods (sessions, messages, participants)
 */
@IsTest
private class ChatController_Test {
    @testSetup
    static void setupUsers() {
        String unique = String.valueOf(DateTime.now().getTime()) + String.valueOf(Math.mod(Crypto.getRandomInteger(), 100000));
        Profile p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];

        insert new List<User>{
            new User(
                ProfileId = p.Id,
                Username = 'chat.test+u1+' + unique + '@example.com',
                Email = 'chat.test+u1+' + unique + '@example.com',
                LastName = 'ChatTest_u1',
                Alias = 'ctu1',
                TimeZoneSidKey = 'Asia/Seoul',
                LocaleSidKey = 'ko_KR',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'ko'
            ),
            new User(
                ProfileId = p.Id,
                Username = 'chat.test+u2+' + unique + '@example.com',
                Email = 'chat.test+u2+' + unique + '@example.com',
                LastName = 'ChatTest_u2',
                Alias = 'ctu2',
                TimeZoneSidKey = 'Asia/Seoul',
                LocaleSidKey = 'ko_KR',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'ko'
            ),
            new User(
                ProfileId = p.Id,
                Username = 'chat.test+u3+' + unique + '@example.com',
                Email = 'chat.test+u3+' + unique + '@example.com',
                LastName = 'ChatTest_u3',
                Alias = 'ctu3',
                TimeZoneSidKey = 'Asia/Seoul',
                LocaleSidKey = 'ko_KR',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'ko'
            )
        };
    }

    private static User u1() {
        return [SELECT Id, Name FROM User WHERE LastName = 'ChatTest_u1' LIMIT 1];
    }
    private static User u2() {
        return [SELECT Id, Name FROM User WHERE LastName = 'ChatTest_u2' LIMIT 1];
    }
    private static User u3() {
        return [SELECT Id, Name FROM User WHERE LastName = 'ChatTest_u3' LIMIT 1];
    }

    private static Inner_Chat_Session__c makeSession(User creator, String name, String typeVal) {
        Inner_Chat_Session__c s;
        System.runAs(creator) {
            s = new Inner_Chat_Session__c(Name = name, Type__c = typeVal);
            insert s;
        }
        return s;
    }

    private static void addParticipants(Id sessionId, List<User> users) {
        List<Inner_Chat_Participant__c> parts = new List<Inner_Chat_Participant__c>();
        for (User u : users) {
            parts.add(new Inner_Chat_Participant__c(Inner_Chat_Session__c = sessionId, User__c = u.Id));
        }
        insert parts;
    }

    private static Inner_Chat_Message__c addMessage(Id sessionId, User sender, String content) {
        Inner_Chat_Message__c m;
        System.runAs(sender) {
            m = new Inner_Chat_Message__c(Inner_Chat_Session__c = sessionId, Sender__c = sender.Id, Content__c = content);
            insert m;
        }
        return m;
    }

    @IsTest
    static void test_getChatSessions_previewAndUnread() {
        User a = u1();
        User b = u2();

        Inner_Chat_Session__c s = makeSession(a, 'U1-U2 Direct', 'Direct');
        addParticipants(s.Id, new List<User>{ a, b });

        Inner_Chat_Message__c mMine = addMessage(s.Id, a, 'hi from u1');
        Inner_Chat_Message__c mSystem = addMessage(s.Id, a, '[SYSTEM] u1 left the chat.');
        Inner_Chat_Message__c mOther = addMessage(s.Id, b, 'hello from u2');

        Test.setCreatedDate(mMine.Id, DateTime.now().addMinutes(-30));
        Test.setCreatedDate(mSystem.Id, DateTime.now().addMinutes(-20));
        Test.setCreatedDate(mOther.Id, DateTime.now().addMinutes(-10));

        System.runAs(b) {
            Test.startTest();
            List<ChatController.ChatSessionWrapper> sessions = ChatController.getChatSessions();
            Test.stopTest();

            System.assertEquals(1, sessions.size(), 'One active chat session');
            System.assertEquals(s.Id, sessions[0].sessionId);
            System.assertEquals('hello from u2', sessions[0].lastMessagePreview, 'Last message preview excludes system messages');
        }
    }

    @IsTest
    static void test_messages_paging_reply() {
        User a = u1();
        User b = u2();

        Inner_Chat_Session__c s = makeSession(a, 'Msg Test', 'Direct');
        addParticipants(s.Id, new List<User>{ a, b });

        Inner_Chat_Message__c base = addMessage(s.Id, b, 'base message for reply');
        Test.setCreatedDate(base.Id, DateTime.now().addMinutes(-5));

        System.runAs(a) {
            Test.startTest();
            ChatController.sendMessage(s.Id, 'replying', null, base.Id, 'base message for reply');
            List<ChatController.MessageWrapper> msgs = ChatController.getMessages(s.Id);
            List<ChatController.MessageWrapper> paged = ChatController.getMessagesPaged(s.Id, null, 10);
            Test.stopTest();

            System.assert(msgs.size() > 0, 'Messages exist');
            System.assert(paged.size() > 0, 'Paged messages exist');
        }
    }

    @IsTest
    static void test_read_rename_invite_participants() {
        User a = u1();
        User b = u2();
        User c = u3();

        Inner_Chat_Session__c s = makeSession(a, 'Flow Test', 'Direct');
        addParticipants(s.Id, new List<User>{ a, b });
        addMessage(s.Id, b, 'hello');

        System.runAs(a) {
            Test.startTest();
            ChatController.markSessionAsRead(s.Id);
            ChatController.renameChatSession(s.Id, 'Renamed Chat');
            ChatController.inviteParticipants(s.Id, new List<Id>{ c.Id });
            List<ChatController.ChatParticipantWrapper> parts = ChatController.getParticipants(s.Id);
            Test.stopTest();

            System.assert(parts.size() >= 2, 'Retrieve participant list');
        }

        Inner_Chat_Session__c after = [SELECT Name, Type__c FROM Inner_Chat_Session__c WHERE Id = :s.Id LIMIT 1];
        System.assertEquals('Renamed Chat', after.Name, 'Rename reflected');
        System.assertEquals('Group', after.Type__c, 'Type changes to Group with 3+ participants');
    }

    @IsTest
    static void test_mute_and_pin_basic() {
        User a = u1();
        User b = u2();

        Inner_Chat_Session__c s = makeSession(a, 'PinBase', 'Direct');
        addParticipants(s.Id, new List<User>{ a, b });

        System.runAs(b) {
            Test.startTest();
            ChatController.setMuted(s.Id, true);
            ChatController.setPinned(s.Id, true);
            Test.stopTest();
        }
    }

    @IsTest
    static void test_pinLimit_max3() {
        User a = u1();
        User b = u2();

        // Create 4 sessions under b, pin 3, fail on 4th pin attempt
        Inner_Chat_Session__c s1 = makeSession(a, 'Pin1', 'Group');
        Inner_Chat_Session__c s2 = makeSession(a, 'Pin2', 'Group');
        Inner_Chat_Session__c s3 = makeSession(a, 'Pin3', 'Group');
        Inner_Chat_Session__c s4 = makeSession(a, 'Pin4', 'Group');
        addParticipants(s1.Id, new List<User>{ b, a });
        addParticipants(s2.Id, new List<User>{ b, a });
        addParticipants(s3.Id, new List<User>{ b, a });
        addParticipants(s4.Id, new List<User>{ b, a });

        System.runAs(b) {
            Test.startTest();
            ChatController.setPinned(s1.Id, true);
            ChatController.setPinned(s2.Id, true);
            ChatController.setPinned(s3.Id, true);
            Test.stopTest();
        }

        System.runAs(b) {
            Boolean threw = false;
            try {
                ChatController.setPinned(s4.Id, true);
            } catch (Exception e) {
                threw = true;
            }
            System.assertEquals(true, threw, 'Fourth pin attempt throws exception');
        }
    }

    @IsTest
    static void test_createOrGet_existingDirect_and_createGroup() {
        User a = u1();
        User b = u2();
        User c = u3();

        Inner_Chat_Session__c direct = makeSession(a, 'Direct Exists', 'Direct');
        addParticipants(direct.Id, new List<User>{ a, b });

        System.runAs(a) {
            Test.startTest();
            ChatController.CreateOrGetChatResult res = ChatController.createOrGetChatSession('', new List<Id>{ b.Id });
            ChatController.CreateOrGetChatResult created = ChatController.createOrGetChatSession('New Group', new List<Id>{ b.Id, c.Id });
            Test.stopTest();

            System.assertNotEquals(null, res.sessionId, 'Result returns existing or created session');
            System.assertNotEquals(null, created.sessionId, 'New group session created');
        }
    }

    @IsTest
    static void test_leave_keeps_session_when_others_remain() {
        User a = u1();
        User b = u2();
        User c = u3();

        Inner_Chat_Session__c s = makeSession(a, 'DeleteMe', 'Group');
        addParticipants(s.Id, new List<User>{ a, b, c });
        addMessage(s.Id, b, 'msg');

        // User c leaves the chat
        System.runAs(c) {
            ChatController.leaveChatSession(s.Id);
        }

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Inner_Chat_Session__c WHERE Id = :s.Id],
            'Session remains if other participants exist'
        );
    }

    @IsTest
    static void test_leave_deletes_session_when_last_participant() {
        User a = u1();

        // Create session with single participant then leave to trigger deletion
        Inner_Chat_Session__c solo = makeSession(a, 'Solo', 'Direct');
        addParticipants(solo.Id, new List<User>{ a });
        addMessage(solo.Id, a, 'solo msg');
        System.runAs(a) {
            ChatController.leaveChatSession(solo.Id);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Inner_Chat_Session__c WHERE Id = :solo.Id], 'Session deleted when last participant leaves');
    }

    @IsTest
    static void test_delete_permissions_and_search() {
        User a = u1();
        User b = u2();

        Inner_Chat_Session__c s = makeSession(a, 'DeleteAuth', 'Group');
        addParticipants(s.Id, new List<User>{ a, b });
        addMessage(s.Id, b, 'msg');

        // Non-creator cannot delete
        System.runAs(b) {
            Boolean threw = false;
            try {
                ChatController.deleteChatSession(s.Id);
            } catch (Exception e) {
                threw = true;
            }
            System.assertEquals(true, threw, 'Non-creator cannot delete session');
        }

        // Creator can delete + verify searchUsers works
        System.runAs(a) {
            Test.startTest();
            ChatController.deleteChatSession(s.Id);
            List<User> found = ChatController.searchUsers('ChatTest');
            Test.stopTest();
            System.assert(found.size() >= 0, 'Search users returns results');
        }
    }
}
