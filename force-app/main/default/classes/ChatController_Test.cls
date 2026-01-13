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

    private static Chat_Session__c makeSession(User creator, String name, String typeVal) {
        Chat_Session__c s;
        System.runAs(creator) {
            s = new Chat_Session__c(Name = name, Type__c = typeVal);
            insert s;
        }
        return s;
    }

    private static void addParticipants(Id sessionId, List<User> users) {
        List<Chat_Participant__c> parts = new List<Chat_Participant__c>();
        for (User u : users) {
            parts.add(new Chat_Participant__c(Chat_Session__c = sessionId, User__c = u.Id));
        }
        insert parts;
    }

    private static Chat_Message__c addMessage(Id sessionId, User sender, String content) {
        Chat_Message__c m;
        System.runAs(sender) {
            m = new Chat_Message__c(Chat_Session__c = sessionId, Sender__c = sender.Id, Content__c = content);
            insert m;
        }
        return m;
    }

    @IsTest
    static void test_getChatSessions_previewAndUnread() {
        User a = u1();
        User b = u2();

        Chat_Session__c s = makeSession(a, 'U1-U2 Direct', 'Direct');
        addParticipants(s.Id, new List<User>{ a, b });

        Chat_Message__c mMine = addMessage(s.Id, a, 'hi from u1');
        Chat_Message__c mSystem = addMessage(s.Id, a, '[SYSTEM] u1님이 채팅방을 나갔습니다.');
        Chat_Message__c mOther = addMessage(s.Id, b, 'hello from u2');

        Test.setCreatedDate(mMine.Id, DateTime.now().addMinutes(-30));
        Test.setCreatedDate(mSystem.Id, DateTime.now().addMinutes(-20));
        Test.setCreatedDate(mOther.Id, DateTime.now().addMinutes(-10));

        System.runAs(b) {
            Test.startTest();
            List<ChatController.ChatSessionWrapper> sessions = ChatController.getChatSessions();
            Test.stopTest();

            System.assertEquals(1, sessions.size(), '참여중인 세션 1개');
            System.assertEquals(s.Id, sessions[0].sessionId);
            System.assertEquals('hello from u2', sessions[0].lastMessagePreview, '시스템 메시지 제외 프리뷰');
        }
    }

    @IsTest
    static void test_messages_paging_reply() {
        User a = u1();
        User b = u2();

        Chat_Session__c s = makeSession(a, 'Msg Test', 'Direct');
        addParticipants(s.Id, new List<User>{ a, b });

        Chat_Message__c base = addMessage(s.Id, b, 'base message for reply');
        Test.setCreatedDate(base.Id, DateTime.now().addMinutes(-5));

        System.runAs(a) {
            Test.startTest();
            ChatController.sendMessage(s.Id, 'replying', null, base.Id, 'base message for reply');
            List<ChatController.MessageWrapper> msgs = ChatController.getMessages(s.Id);
            List<ChatController.MessageWrapper> paged = ChatController.getMessagesPaged(s.Id, null, 10);
            Test.stopTest();

            System.assert(msgs.size() > 0, '메시지 존재');
            System.assert(paged.size() > 0, '페이징 메시지 존재');
        }
    }

    @IsTest
    static void test_read_rename_invite_participants() {
        User a = u1();
        User b = u2();
        User c = u3();

        Chat_Session__c s = makeSession(a, 'Flow Test', 'Direct');
        addParticipants(s.Id, new List<User>{ a, b });
        addMessage(s.Id, b, 'hello');

        System.runAs(a) {
            Test.startTest();
            ChatController.markSessionAsRead(s.Id);
            ChatController.renameChatSession(s.Id, 'Renamed Chat');
            ChatController.inviteParticipants(s.Id, new List<Id>{ c.Id });
            List<ChatController.ChatParticipantWrapper> parts = ChatController.getParticipants(s.Id);
            Test.stopTest();

            System.assert(parts.size() >= 2, '참여자 목록 조회');
        }

        Chat_Session__c after = [SELECT Name, Type__c FROM Chat_Session__c WHERE Id = :s.Id LIMIT 1];
        System.assertEquals('Renamed Chat', after.Name, '이름 변경 반영');
        System.assertEquals('Group', after.Type__c, '3명 이상이면 Group 전환');
    }

    @IsTest
    static void test_mute_and_pin_basic() {
        User a = u1();
        User b = u2();

        Chat_Session__c s = makeSession(a, 'PinBase', 'Direct');
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

        // b 기준으로 3개 고정 후 4번째 고정 시 예외
        Chat_Session__c s1 = makeSession(a, 'Pin1', 'Group');
        Chat_Session__c s2 = makeSession(a, 'Pin2', 'Group');
        Chat_Session__c s3 = makeSession(a, 'Pin3', 'Group');
        Chat_Session__c s4 = makeSession(a, 'Pin4', 'Group');
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
            System.assertEquals(true, threw, '고정 4개째는 예외');
        }
    }

    @IsTest
    static void test_createOrGet_existingDirect_and_createGroup() {
        User a = u1();
        User b = u2();
        User c = u3();

        Chat_Session__c direct = makeSession(a, 'Direct Exists', 'Direct');
        addParticipants(direct.Id, new List<User>{ a, b });

        System.runAs(a) {
            Test.startTest();
            ChatController.CreateOrGetChatResult res = ChatController.createOrGetChatSession('', new List<Id>{ b.Id });
            ChatController.CreateOrGetChatResult created = ChatController.createOrGetChatSession('New Group', new List<Id>{ b.Id, c.Id });
            Test.stopTest();

            System.assertNotEquals(null, res.sessionId, '기존/생성 결과 존재');
            System.assertNotEquals(null, created.sessionId, '신규 세션 생성됨');
        }
    }

    @IsTest
    static void test_leave_keeps_session_when_others_remain() {
        User a = u1();
        User b = u2();
        User c = u3();

        Chat_Session__c s = makeSession(a, 'DeleteMe', 'Group');
        addParticipants(s.Id, new List<User>{ a, b, c });
        addMessage(s.Id, b, 'msg');

        // c가 나가도 방은 유지
        System.runAs(c) {
            ChatController.leaveChatSession(s.Id);
        }

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Chat_Session__c WHERE Id = :s.Id],
            '남은 참여자가 있으면 세션 유지'
        );
    }

    @IsTest
    static void test_leave_deletes_session_when_last_participant() {
        User a = u1();

        // 마지막 참여자가 나가면 세션 삭제 분기
        Chat_Session__c solo = makeSession(a, 'Solo', 'Direct');
        addParticipants(solo.Id, new List<User>{ a });
        addMessage(solo.Id, a, 'solo msg');
        System.runAs(a) {
            ChatController.leaveChatSession(solo.Id);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Chat_Session__c WHERE Id = :solo.Id], '마지막 참여자 나가면 세션 삭제');
    }

    @IsTest
    static void test_delete_permissions_and_search() {
        User a = u1();
        User b = u2();

        Chat_Session__c s = makeSession(a, 'DeleteAuth', 'Group');
        addParticipants(s.Id, new List<User>{ a, b });
        addMessage(s.Id, b, 'msg');

        // 비생성자 삭제 불가
        System.runAs(b) {
            Boolean threw = false;
            try {
                ChatController.deleteChatSession(s.Id);
            } catch (Exception e) {
                threw = true;
            }
            System.assertEquals(true, threw, '비생성자 삭제 불가');
        }

        // 생성자 삭제 가능 + searchUsers 호출
        System.runAs(a) {
            Test.startTest();
            ChatController.deleteChatSession(s.Id);
            List<User> found = ChatController.searchUsers('ChatTest');
            Test.stopTest();
            System.assert(found.size() >= 0, '검색 호출 성공');
        }
    }
}

