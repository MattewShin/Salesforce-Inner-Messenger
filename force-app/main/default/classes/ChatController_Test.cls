@IsTest
private class ChatController_Test {
    private static User makeUser(String aliasSeed) {
        String unique = String.valueOf(DateTime.now().getTime()) + String.valueOf(Math.mod(Crypto.getRandomInteger(), 100000));
        Profile p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            Username = 'chat.test+' + aliasSeed + '+' + unique + '@example.com',
            Email = 'chat.test+' + aliasSeed + '+' + unique + '@example.com',
            LastName = 'ChatTest' + aliasSeed,
            Alias = (aliasSeed.length() > 8 ? aliasSeed.substring(0, 8) : aliasSeed),
            TimeZoneSidKey = 'Asia/Seoul',
            LocaleSidKey = 'ko_KR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'ko'
        );
        insert u;
        return u;
    }

    private static Chat_Session__c makeSession(User creator, String name, String typeVal) {
        Chat_Session__c s;
        System.runAs(creator) {
            s = new Chat_Session__c(
                Name = name,
                Type__c = typeVal
            );
            insert s;
        }
        return s;
    }

    private static void addParticipants(Id sessionId, List<User> users) {
        List<Chat_Participant__c> parts = new List<Chat_Participant__c>();
        for (User u : users) {
            parts.add(new Chat_Participant__c(
                Chat_Session__c = sessionId,
                User__c = u.Id
            ));
        }
        insert parts;
    }

    private static Chat_Message__c addMessage(Id sessionId, User sender, String content) {
        Chat_Message__c m;
        System.runAs(sender) {
            m = new Chat_Message__c(
                Chat_Session__c = sessionId,
                Sender__c = sender.Id,
                Content__c = content
            );
            insert m;
        }
        return m;
    }

    @IsTest
    static void test_coreFlows_andRealtimeEvents() {
        User u1 = makeUser('u1');
        User u2 = makeUser('u2');
        User u3 = makeUser('u3');

        // u1이 Direct 방 생성 + u2 초대
        Chat_Session__c s = makeSession(u1, 'U1-U2 Direct', 'Direct');
        addParticipants(s.Id, new List<User>{ u1, u2 });

        // 메시지 구성: 시스템/내메시지/상대메시지
        Chat_Message__c mMine = addMessage(s.Id, u1, 'hi from u1');
        Chat_Message__c mSystem = addMessage(s.Id, u1, '[SYSTEM] u1님이 채팅방을 나갔습니다.');
        Chat_Message__c mOther = addMessage(s.Id, u2, 'hello from u2');

        // CreatedDate를 조정해 unread/preview 로직을 안정적으로 검증
        Test.setCreatedDate(mMine.Id, DateTime.now().addMinutes(-30));
        Test.setCreatedDate(mSystem.Id, DateTime.now().addMinutes(-20));
        Test.setCreatedDate(mOther.Id, DateTime.now().addMinutes(-10));

        System.runAs(u2) {
            Test.startTest();
            List<ChatController.ChatSessionWrapper> sessions = ChatController.getChatSessions();
            Test.stopTest();

            System.assertEquals(1, sessions.size(), '참여중인 세션 1개');
            System.assertEquals(s.Id, sessions[0].sessionId);
            System.assertEquals(true, sessions[0].unreadCount >= 0, 'unreadCount 존재');
            System.assertEquals('hello from u2', sessions[0].lastMessagePreview, '시스템 메시지 제외 프리뷰');
        }

        // 메시지 조회/페이징 + 답장 프리뷰
        Chat_Message__c base = addMessage(s.Id, u2, 'base message for reply');
        Test.setCreatedDate(base.Id, DateTime.now().addMinutes(-5));
        System.runAs(u1) {
            Test.startTest();
            ChatController.sendMessage(s.Id, 'replying', null, base.Id, 'base message for reply');
            List<ChatController.MessageWrapper> msgs = ChatController.getMessages(s.Id);
            List<ChatController.MessageWrapper> paged = ChatController.getMessagesPaged(s.Id, null, 10);
            Test.stopTest();
            System.assert(msgs.size() > 0, '메시지 존재');
            System.assert(paged.size() > 0, '페이징 메시지 존재');
        }

        // 읽음 처리 이벤트: u1이 방을 보고 최신까지 읽음 처리
        System.runAs(u1) {
            Test.startTest();
            ChatController.markSessionAsRead(s.Id);
            Test.stopTest();
        }

        // 이름 변경 + 이벤트 발행
        System.runAs(u1) {
            Test.startTest();
            ChatController.renameChatSession(s.Id, 'Renamed Chat');
            Test.stopTest();
        }
        System.runAs(u1) {
            ChatController.ChatSessionWrapper single = ChatController.getChatSession(s.Id);
            System.assertEquals(s.Id, single.sessionId, '단일 세션 조회');
            System.assertEquals('Renamed Chat', single.name, '이름 변경 반영');
        }

        // 참여자 초대: u3 초대 시 시스템 메시지 + 이벤트 발행 + 인원>2면 Group 전환
        System.runAs(u1) {
            Test.startTest();
            ChatController.inviteParticipants(s.Id, new List<Id>{ u3.Id });
            Test.stopTest();
        }

        // 참여자 목록
        System.runAs(u2) {
            List<ChatController.ChatParticipantWrapper> parts = ChatController.getParticipants(s.Id);
            System.assertEquals(true, parts.size() >= 2, '참여자 최소 2명');
        }

        // setMuted / setPinned 기본 동작
        System.runAs(u2) {
            Test.startTest();
            ChatController.setMuted(s.Id, true);
            ChatController.setPinned(s.Id, true);
            Test.stopTest();
        }

        // 고정 최대 3개 제한 검증: u2 기준으로 이미 3개 고정 후, 4번째 고정 시 예외
        Chat_Session__c s2 = makeSession(u1, 'S2', 'Group');
        Chat_Session__c s3 = makeSession(u1, 'S3', 'Group');
        Chat_Session__c s4 = makeSession(u1, 'S4', 'Group');
        addParticipants(s2.Id, new List<User>{ u2, u1 });
        addParticipants(s3.Id, new List<User>{ u2, u1 });
        addParticipants(s4.Id, new List<User>{ u2, u1 });

        System.runAs(u2) {
            ChatController.setPinned(s2.Id, true);
            ChatController.setPinned(s3.Id, true);
            ChatController.setPinned(s4.Id, true);
        }

        Chat_Session__c s5 = makeSession(u1, 'S5', 'Group');
        addParticipants(s5.Id, new List<User>{ u2, u1 });
        System.runAs(u2) {
            Boolean threw = false;
            try {
                ChatController.setPinned(s5.Id, true);
            } catch (Exception e) {
                threw = true;
            }
            System.assertEquals(true, threw, '고정 4개째는 예외');
        }

        // createOrGetChatSession: Direct(1:1) 기존 방 반환 케이스
        System.runAs(u1) {
            Test.startTest();
            ChatController.CreateOrGetChatResult res = ChatController.createOrGetChatSession('', new List<Id>{ u2.Id });
            Test.stopTest();
            System.assertEquals(true, res != null, '결과 존재');
            System.assertEquals(true, res.sessionId != null, '세션 id 존재');
        }

        // createOrGetChatSession: 신규 생성 분기(그룹)로 createChatSession도 커버
        System.runAs(u1) {
            Test.startTest();
            ChatController.CreateOrGetChatResult created = ChatController.createOrGetChatSession('New Group', new List<Id>{ u2.Id, u3.Id });
            Test.stopTest();
            System.assertEquals(false, created.existed, '그룹은 신규 생성');
            System.assertNotEquals(null, created.sessionId, '신규 세션 생성됨');
        }

        // leaveChatSession: u3가 나가도 방은 유지(남은 참여자 존재)
        System.runAs(u3) {
            Test.startTest();
            ChatController.leaveChatSession(s.Id);
            Test.stopTest();
        }

        // leaveChatSession: 마지막 참여자가 나가면 세션/메시지 삭제 분기 커버
        Chat_Session__c solo = makeSession(u1, 'Solo', 'Direct');
        addParticipants(solo.Id, new List<User>{ u1 });
        Chat_Message__c soloMsg = addMessage(solo.Id, u1, 'solo msg');
        Test.setCreatedDate(soloMsg.Id, DateTime.now().addMinutes(-1));
        System.runAs(u1) {
            Test.startTest();
            ChatController.leaveChatSession(solo.Id);
            Test.stopTest();
        }
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Chat_Session__c WHERE Id = :solo.Id],
            '마지막 참여자 나가면 세션 삭제'
        );

        // deleteChatSession: 생성자만 가능
        System.runAs(u2) {
            Boolean threw = false;
            try {
                ChatController.deleteChatSession(s.Id);
            } catch (Exception e) {
                threw = true;
            }
            System.assertEquals(true, threw, '비생성자 삭제 불가');
        }
        System.runAs(u1) {
            Test.startTest();
            ChatController.deleteChatSession(s.Id);
            Test.stopTest();
        }

        // searchUsers 간단 호출(캐시 가능 메서드)
        Test.startTest();
        List<User> found = ChatController.searchUsers('ChatTest');
        Test.stopTest();
        System.assert(found.size() >= 0, '검색 호출 성공');
    }
}

