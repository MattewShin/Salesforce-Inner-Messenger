public with sharing class ChatController {
    
    // 채팅방 목록 조회 (현재 사용자가 참여 중인 방)
    @AuraEnabled
    public static List<ChatSessionWrapper> getChatSessions() {
        Id currentUserId = UserInfo.getUserId();
        
        List<Chat_Participant__c> participations = [
            SELECT Chat_Session__c, Chat_Session__r.Name, Chat_Session__r.Type__c,
                   Chat_Session__r.LastModifiedDate, Chat_Session__r.CreatedById,
                   Chat_Session__r.Last_Message_At__c,
                   Last_Read_At__c,
                   Is_Pinned__c,
                   Is_Muted__c
            FROM Chat_Participant__c
            WHERE User__c = :currentUserId
            ORDER BY Is_Pinned__c DESC, Chat_Session__r.Last_Message_At__c DESC, Chat_Session__r.LastModifiedDate DESC
        ];
        
        // 안읽음 계산: 각 세션별 Last_Read_At__c 이후의 메시지 수(내 메시지/시스템 메시지 제외)
        Map<Id, DateTime> lastReadMap = new Map<Id, DateTime>();
        Set<Id> sessionIds = new Set<Id>();
        DateTime minLastRead = null;
        for (Chat_Participant__c p : participations) {
            sessionIds.add(p.Chat_Session__c);
            DateTime lr = p.Last_Read_At__c;
            if (lr == null) lr = DateTime.newInstance(1970, 1, 1, 0, 0, 0); // 미읽음 상태(전체를 대상으로)
            lastReadMap.put(p.Chat_Session__c, lr);
            if (minLastRead == null || lr < minLastRead) minLastRead = lr;
        }

        Map<Id, Integer> unreadMap = new Map<Id, Integer>();
        if (!sessionIds.isEmpty() && minLastRead != null) {
            List<Chat_Message__c> msgs = [
                SELECT Chat_Session__c, CreatedDate, Sender__c, Content__c
                FROM Chat_Message__c
                WHERE Chat_Session__c IN :sessionIds
                  AND CreatedDate > :minLastRead
                ORDER BY CreatedDate ASC
            ];
            for (Chat_Message__c m : msgs) {
                // 내 메시지는 unread로 치지 않음
                if (m.Sender__c == currentUserId) continue;
                // 시스템 메시지는 unread에서 제외(원하면 포함으로 변경 가능)
                if (m.Content__c != null && m.Content__c.startsWith('[SYSTEM]')) continue;

                DateTime lr = lastReadMap.get(m.Chat_Session__c);
                if (lr != null && m.CreatedDate <= lr) continue;

                Integer cur = unreadMap.containsKey(m.Chat_Session__c) ? unreadMap.get(m.Chat_Session__c) : 0;
                unreadMap.put(m.Chat_Session__c, cur + 1);
            }
        }

        // 마지막 메시지 프리뷰(시스템 메시지 제외)
        Map<Id, String> lastPreviewMap = new Map<Id, String>();
        if (!sessionIds.isEmpty()) {
            List<Chat_Message__c> latestMsgs = [
                SELECT Chat_Session__c, Content__c, CreatedDate
                FROM Chat_Message__c
                WHERE Chat_Session__c IN :sessionIds
                ORDER BY CreatedDate DESC
            ];
            for (Chat_Message__c m : latestMsgs) {
                if (m.Chat_Session__c == null) continue;
                if (lastPreviewMap.containsKey(m.Chat_Session__c)) continue; // 세션별 1개만
                String c = (m.Content__c == null) ? '' : m.Content__c;
                // 시스템 메시지는 프리뷰에서 제외
                if (!String.isBlank(c) && c.startsWith('[SYSTEM]')) continue;
                c = c.replace('\n', ' ').replace('\r', ' ').trim();
                // 너무 길면 서버에서도 1차 축약(최종 ... 처리는 UI에서도 가능)
                Integer maxLen = 80;
                if (c.length() > maxLen) {
                    c = c.substring(0, maxLen - 3) + '...';
                }
                lastPreviewMap.put(m.Chat_Session__c, c);
            }
        }

        List<ChatSessionWrapper> results = new List<ChatSessionWrapper>();
        for (Chat_Participant__c p : participations) {
            Integer unread = unreadMap.containsKey(p.Chat_Session__c) ? unreadMap.get(p.Chat_Session__c) : 0;
            DateTime lastMsgAt = (p.Chat_Session__r.Last_Message_At__c != null)
                ? p.Chat_Session__r.Last_Message_At__c
                : p.Chat_Session__r.LastModifiedDate; // 메시지가 없으면 fallback
            String preview = lastPreviewMap.containsKey(p.Chat_Session__c) ? lastPreviewMap.get(p.Chat_Session__c) : '';
            results.add(new ChatSessionWrapper(p.Chat_Session__r, unread, lastMsgAt, p.Is_Pinned__c, p.Is_Muted__c, preview));
        }
        return results;
    }

    // 단일 채팅방 조회 (생성 직후 UI 전환용)
    @AuraEnabled
    public static ChatSessionWrapper getChatSession(Id sessionId) {
        if (sessionId == null) return null;

        Id me = UserInfo.getUserId();
        Integer mine = [
            SELECT COUNT()
            FROM Chat_Participant__c
            WHERE Chat_Session__c = :sessionId
              AND User__c = :me
        ];
        if (mine == 0) {
            throw new AuraHandledException('참여자가 아닌 사용자는 채팅방 정보를 조회할 수 없습니다.');
        }

        Chat_Session__c s = [
            SELECT Id, Name, Type__c, LastModifiedDate, CreatedById, Last_Message_At__c
            FROM Chat_Session__c
            WHERE Id = :sessionId
            LIMIT 1
        ];
        DateTime lastMsgAt = (s.Last_Message_At__c != null) ? s.Last_Message_At__c : s.LastModifiedDate;
        return new ChatSessionWrapper(s, 0, lastMsgAt, false, false, null);
    }

    // 고정(Pin) 설정
    @AuraEnabled
    public static void setPinned(Id sessionId, Boolean pinned) {
        if (sessionId == null) return;
        Id me = UserInfo.getUserId();
        Boolean willPin = (pinned == true);

        List<Chat_Participant__c> mine = [
            SELECT Id, Is_Pinned__c
            FROM Chat_Participant__c
            WHERE Chat_Session__c = :sessionId
              AND User__c = :me
            LIMIT 1
        ];
        if (mine.isEmpty()) return;

        // 이미 고정된 상태에서 다시 고정 요청이면 그대로
        if (willPin && mine[0].Is_Pinned__c == true) return;

        // 고정 최대 3개 제한
        if (willPin) {
            Integer pinnedCount = [
                SELECT COUNT()
                FROM Chat_Participant__c
                WHERE User__c = :me
                  AND Is_Pinned__c = true
            ];
            if (pinnedCount >= 3) {
                throw new AuraHandledException('채팅방 고정은 최대 3개까지만 가능합니다.');
            }
        }

        mine[0].Is_Pinned__c = willPin;
        update mine[0];
    }

    // 알림 끄기(Mute) 설정
    @AuraEnabled
    public static void setMuted(Id sessionId, Boolean muted) {
        if (sessionId == null) return;
        Id me = UserInfo.getUserId();
        List<Chat_Participant__c> mine = [
            SELECT Id, Is_Muted__c
            FROM Chat_Participant__c
            WHERE Chat_Session__c = :sessionId
              AND User__c = :me
            LIMIT 1
        ];
        if (mine.isEmpty()) return;
        mine[0].Is_Muted__c = (muted == true);
        update mine[0];
    }

    // 참여자 목록 조회 (현재 채팅방에 참여 중인 사용자)
    @AuraEnabled
    public static List<ChatParticipantWrapper> getParticipants(Id sessionId) {
        if (sessionId == null) return new List<ChatParticipantWrapper>();

        Id me = UserInfo.getUserId();
        Integer mine = [
            SELECT COUNT()
            FROM Chat_Participant__c
            WHERE Chat_Session__c = :sessionId
              AND User__c = :me
        ];
        if (mine == 0) {
            throw new AuraHandledException('참여자가 아닌 사용자는 참여자 목록을 조회할 수 없습니다.');
        }

        List<Chat_Participant__c> parts = [
            SELECT Id,
                   User__c, User__r.Name,
                   Last_Read_At__c,
                   Is_Pinned__c,
                   Is_Muted__c
            FROM Chat_Participant__c
            WHERE Chat_Session__c = :sessionId
            ORDER BY User__r.Name ASC
        ];

        List<ChatParticipantWrapper> results = new List<ChatParticipantWrapper>();
        for (Chat_Participant__c p : parts) {
            results.add(new ChatParticipantWrapper(p));
        }
        return results;
    }

    // 채팅방 읽음 처리 (현재 사용자 참여자 레코드의 Last_Read_At__c 갱신)
    @AuraEnabled
    public static void markSessionAsRead(Id sessionId) {
        if (sessionId == null) return;
        Id me = UserInfo.getUserId();

        List<Chat_Participant__c> mine = [
            SELECT Id, Last_Read_At__c
            FROM Chat_Participant__c
            WHERE Chat_Session__c = :sessionId
              AND User__c = :me
            LIMIT 1
        ];
        if (mine.isEmpty()) return;

        // "지금 시각"이 아니라 "채팅방의 최신 메시지 시각"까지만 읽음으로 처리해야
        // ReadReceipt 이벤트가 무한 루프를 만들지 않습니다.
        DateTime latestMsgAt = null;
        List<Chat_Message__c> latest = [
            SELECT CreatedDate
            FROM Chat_Message__c
            WHERE Chat_Session__c = :sessionId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!latest.isEmpty()) latestMsgAt = latest[0].CreatedDate;
        if (latestMsgAt == null) return;

        DateTime prev = mine[0].Last_Read_At__c;
        if (prev != null && prev >= latestMsgAt) return; // 이미 최신까지 읽음

        mine[0].Last_Read_At__c = latestMsgAt;
        update mine[0];

        // 읽음 이벤트(상대방 UI 즉시 갱신용)
        if (prev == null || prev < latestMsgAt) {
            List<Chat_Participant__c> parts = [
                SELECT User__c
                FROM Chat_Participant__c
                WHERE Chat_Session__c = :sessionId
            ];
            List<String> participantIds = new List<String>();
            for (Chat_Participant__c p : parts) {
                if (p.User__c != null) participantIds.add(String.valueOf(p.User__c).substring(0, 15));
            }

            Chat_Notification__e notif = new Chat_Notification__e(
                Payload__c = JSON.serialize(new Map<String, Object>{
                    'type' => 'ReadReceipt',
                    'sessionId' => sessionId,
                    'readerId' => me,
                    'readAt' => latestMsgAt,
                    'participantIds' => participantIds
                })
            );
            EventBus.publish(notif);
        }
    }

    // 특정 채팅방의 메시지 조회
    // 채팅은 실시간성이 중요하므로 캐시를 사용하지 않습니다.
    @AuraEnabled
    public static List<MessageWrapper> getMessages(Id sessionId) {
        Map<Id, DateTime> lastReadByUser = new Map<Id, DateTime>();
        for (Chat_Participant__c p : [
            SELECT User__c, Last_Read_At__c
            FROM Chat_Participant__c
            WHERE Chat_Session__c = :sessionId
        ]) {
            if (p.User__c != null) lastReadByUser.put(p.User__c, p.Last_Read_At__c);
        }
        Integer totalParticipants = lastReadByUser.size();

        List<Chat_Message__c> msgs = [
            SELECT Id, Content__c, Sender__c, Sender__r.Name, CreatedDate,
                   Reply_To__c, Reply_Preview__c,
                   Reply_To__r.Content__c, Reply_To__r.Sender__r.Name,
                   (SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension, ContentDocument.LatestPublishedVersionId
                    FROM ContentDocumentLinks LIMIT 1)
            FROM Chat_Message__c
            WHERE Chat_Session__c = :sessionId
            ORDER BY CreatedDate ASC
            LIMIT 50
        ];
        
        List<MessageWrapper> results = new List<MessageWrapper>();
        for (Chat_Message__c msg : msgs) {
            Integer unreadByOthers = 0;
            for (Id uid : lastReadByUser.keySet()) {
                if (uid == msg.Sender__c) continue;
                DateTime lr = lastReadByUser.get(uid);
                if (lr == null || lr < msg.CreatedDate) unreadByOthers++;
            }
            Integer otherCount = Math.max(totalParticipants - 1, 0);
            Integer readByOthers = Math.max(otherCount - unreadByOthers, 0);
            results.add(new MessageWrapper(msg, unreadByOthers, readByOthers, otherCount));
        }
        return results;
    }

    // 메시지 페이징 조회(무한 스크롤용)
    // - before: null이면 최신 메시지부터 limit개를 가져옵니다.
    // - before가 있으면 before 이전(더 과거) 메시지들을 limit개 가져옵니다.
    // 반환은 CreatedDate ASC(화면 렌더링 편의)로 정렬합니다.
    @AuraEnabled
    public static List<MessageWrapper> getMessagesPaged(Id sessionId, Datetime before, Integer limitSize) {
        if (sessionId == null) return new List<MessageWrapper>();
        Integer lim = (limitSize == null || limitSize <= 0) ? 50 : Math.min(limitSize, 200);

        Map<Id, DateTime> lastReadByUser = new Map<Id, DateTime>();
        for (Chat_Participant__c p : [
            SELECT User__c, Last_Read_At__c
            FROM Chat_Participant__c
            WHERE Chat_Session__c = :sessionId
        ]) {
            if (p.User__c != null) lastReadByUser.put(p.User__c, p.Last_Read_At__c);
        }
        Integer totalParticipants = lastReadByUser.size();

        // 최신 메시지부터 가져온 뒤(ORDER BY DESC) 화면에서는 ASC로 바꿔 렌더링
        List<Chat_Message__c> msgs;
        if (before == null) {
            msgs = [
                SELECT Id, Content__c, Sender__c, Sender__r.Name, CreatedDate,
                       Reply_To__c, Reply_Preview__c,
                       Reply_To__r.Content__c, Reply_To__r.Sender__r.Name,
                       (SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension, ContentDocument.LatestPublishedVersionId
                        FROM ContentDocumentLinks LIMIT 1)
                FROM Chat_Message__c
                WHERE Chat_Session__c = :sessionId
                ORDER BY CreatedDate DESC
                LIMIT :lim
            ];
        } else {
            msgs = [
                SELECT Id, Content__c, Sender__c, Sender__r.Name, CreatedDate,
                       Reply_To__c, Reply_Preview__c,
                       Reply_To__r.Content__c, Reply_To__r.Sender__r.Name,
                       (SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension, ContentDocument.LatestPublishedVersionId
                        FROM ContentDocumentLinks LIMIT 1)
                FROM Chat_Message__c
                WHERE Chat_Session__c = :sessionId
                  AND CreatedDate < :before
                ORDER BY CreatedDate DESC
                LIMIT :lim
            ];
        }

        List<MessageWrapper> results = new List<MessageWrapper>();
        // DESC로 조회했으므로 화면 렌더링을 위해 ASC로 뒤집어서 반환
        for (Integer i = msgs.size() - 1; i >= 0; i--) {
            Chat_Message__c msg = msgs[i];
            Integer unreadByOthers = 0;
            for (Id uid : lastReadByUser.keySet()) {
                if (uid == msg.Sender__c) continue;
                DateTime lr = lastReadByUser.get(uid);
                if (lr == null || lr < msg.CreatedDate) unreadByOthers++;
            }
            Integer otherCount = Math.max(totalParticipants - 1, 0);
            Integer readByOthers = Math.max(otherCount - unreadByOthers, 0);
            results.add(new MessageWrapper(msg, unreadByOthers, readByOthers, otherCount));
        }
        return results;
    }

    // 메시지 전송 및 알림 게시
    @AuraEnabled
    public static void sendMessage(Id sessionId, String content, Id contentDocumentId, Id replyToMessageId, String replyPreview) {
        try {
            // 1. 메시지 저장
            String preview = replyPreview;
            if (preview != null && preview.length() > 255) {
                preview = preview.substring(0, 252) + '...';
            }
            Chat_Message__c newMsg = new Chat_Message__c(
                Chat_Session__c = sessionId,
                Content__c = content,
                Sender__c = UserInfo.getUserId(),
                Reply_To__c = replyToMessageId,
                Reply_Preview__c = preview
            );
            insert newMsg;

            // 2. 파일이 첨부된 경우 링크 생성
            if (contentDocumentId != null) {
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = contentDocumentId;
                cdl.LinkedEntityId = newMsg.Id;
                cdl.ShareType = 'V'; // Viewer 권한
                insert cdl;
            }

            // 3. 채팅방의 마지막 메시지 시간 갱신 (목록 정렬용)
            // 주의: Platform Event보다 먼저 갱신해야, 클라이언트가 이벤트를 받고 목록을 새로고침할 때 정렬이 즉시 반영됩니다.
            update new Chat_Session__c(
                Id = sessionId,
                Last_Message_At__c = System.now()
            );

            // 4. Platform Event 게시 (실시간 알림)
            // 채팅방 참여자 목록을 함께 보내서(클라이언트에서) 비참여자가 이벤트를 무시할 수 있게 합니다.
            List<Chat_Participant__c> participants = [
                SELECT User__c
                FROM Chat_Participant__c
                WHERE Chat_Session__c = :sessionId
            ];
            List<String> participantIds = new List<String>();
            for (Chat_Participant__c p : participants) {
                if (p.User__c != null) participantIds.add(String.valueOf(p.User__c).substring(0, 15));
            }

            Chat_Notification__e notif = new Chat_Notification__e(
                Payload__c = JSON.serialize(new Map<String, Object>{
                    'type' => 'NewMessage',
                    'sessionId' => sessionId,
                    'messageId' => newMsg.Id,
                    'senderId' => UserInfo.getUserId(),
                    'senderName' => UserInfo.getName(),
                    'content' => content,
                    'hasAttachment' => (contentDocumentId != null),
                    'participantIds' => participantIds
                })
            );
            EventBus.publish(notif);

        } catch (Exception e) {
            throw new AuraHandledException('메시지 전송 실패: ' + e.getMessage());
        }
    }

    // 새로운 채팅방 생성 (그룹 또는 1:1)
    @AuraEnabled
    public static Id createChatSession(String name, List<Id> userIds) {
        // 채팅방 이름 기본값: 이름 미입력 시 참여자 전원의 이름으로 자동 생성
        String finalName = name;
        if (String.isBlank(finalName)) {
            Set<Id> uniqueUsers = new Set<Id>(userIds);
            uniqueUsers.add(UserInfo.getUserId());
            List<User> users = [SELECT Id, Name FROM User WHERE Id IN :uniqueUsers ORDER BY Name ASC];
            List<String> names = new List<String>();
            for (User u : users) names.add(u.Name);
            finalName = String.join(names, ', ') + '의 대화';

            // Name 필드 길이(일반적으로 80) 초과 방지
            Integer maxLen = 80;
            if (finalName.length() > maxLen) {
                finalName = finalName.substring(0, maxLen - 3) + '...';
            }
        }

        // 채팅방 생성
        Chat_Session__c session = new Chat_Session__c(
            Name = finalName,
            Type__c = (userIds.size() > 1) ? 'Group' : 'Direct'
        );
        insert session;

        // 참여자 추가 (현재 사용자 포함)
        List<Chat_Participant__c> participants = new List<Chat_Participant__c>();
        Set<Id> uniqueUsers = new Set<Id>(userIds);
        uniqueUsers.add(UserInfo.getUserId());

        for (Id uid : uniqueUsers) {
            participants.add(new Chat_Participant__c(
                Chat_Session__c = session.Id,
                User__c = uid,
                // 생성자는 생성 직후 이미 읽은 것으로 처리
                Last_Read_At__c = (uid == UserInfo.getUserId()) ? System.now() : null
            ));
        }
        insert participants;

        return session.Id;
    }

    // 채팅방 생성(또는 기존 Direct 채팅방 반환)
    // - 상대와 1:1(Direct) 채팅방이 이미 존재하면 새로 만들지 않고 그 방으로 이동합니다.
    @AuraEnabled
    public static CreateOrGetChatResult createOrGetChatSession(String name, List<Id> userIds) {
        CreateOrGetChatResult res = new CreateOrGetChatResult();
        res.existed = false;

        if (userIds == null || userIds.isEmpty()) {
            // 방 생성 자체가 불가한 입력
            throw new AuraHandledException('대화 상대를 선택해주세요.');
        }

        Id me = UserInfo.getUserId();

        // 1:1 생성 시에만 "기존 채팅방"을 탐색
        if (userIds.size() == 1) {
            Id other = userIds[0];
            if (other != null && other != me) {
                Set<Id> pair = new Set<Id>{ me, other };

                // 두 사람만 참여 중인 Direct 채팅방이 있는지 확인
                // - Type__c = 'Direct'
                // - 참여자 수 = 2
                List<AggregateResult> ars = [
                    SELECT Chat_Session__c sessionId,
                           MAX(Chat_Session__r.LastModifiedDate) lastMod,
                           COUNT(Id) cnt,
                           COUNT_DISTINCT(User__c) userCnt
                    FROM Chat_Participant__c
                    WHERE User__c IN :pair
                      AND Chat_Session__r.Type__c = 'Direct'
                    GROUP BY Chat_Session__c
                    HAVING COUNT(Id) = 2 AND COUNT_DISTINCT(User__c) = 2
                    ORDER BY MAX(Chat_Session__r.LastModifiedDate) DESC
                    LIMIT 1
                ];

                if (!ars.isEmpty()) {
                    res.sessionId = (Id) ars[0].get('sessionId');
                    res.existed = true;
                    return res;
                }
            }
        }

        // 기존 방이 없으면 새로 생성
        res.sessionId = createChatSession(name, userIds);
        res.existed = false;
        return res;
    }

    // 채팅방 이름 변경 (참여자만 가능)
    @AuraEnabled
    public static void renameChatSession(Id sessionId, String newName) {
        if (sessionId == null) return;
        if (String.isBlank(newName)) {
            throw new AuraHandledException('채팅방 이름을 입력해주세요.');
        }

        Id me = UserInfo.getUserId();
        Integer mine = [
            SELECT COUNT()
            FROM Chat_Participant__c
            WHERE Chat_Session__c = :sessionId
              AND User__c = :me
        ];
        if (mine == 0) {
            throw new AuraHandledException('참여자가 아닌 사용자는 채팅방 이름을 변경할 수 없습니다.');
        }

        try {
            update new Chat_Session__c(
                Id = sessionId,
                Name = newName
            );

            // 참여자 목록(전체) 조회 → Platform Event에 포함(비참여자 수신 방지)
            List<Chat_Participant__c> parts = [
                SELECT User__c
                FROM Chat_Participant__c
                WHERE Chat_Session__c = :sessionId
            ];
            List<String> participantIds = new List<String>();
            for (Chat_Participant__c p : parts) {
                if (p.User__c != null) participantIds.add(String.valueOf(p.User__c).substring(0, 15));
            }

            // 채팅방 이름 변경 이벤트 발행(상대방 화면 즉시 갱신용)
            Chat_Notification__e notif = new Chat_Notification__e(
                Payload__c = JSON.serialize(new Map<String, Object>{
                    'type' => 'SessionRenamed',
                    'sessionId' => sessionId,
                    'senderId' => me,
                    'newName' => newName,
                    'participantIds' => participantIds
                })
            );
            EventBus.publish(notif);
        } catch (Exception e) {
            throw new AuraHandledException('채팅방 이름 변경 실패: ' + e.getMessage());
        }
    }

    // 채팅방 나가기 (현재 사용자만 참여자에서 제거)
    @AuraEnabled
    public static void leaveChatSession(Id sessionId) {
        if (sessionId == null) return;
        Id me = UserInfo.getUserId();

        try {
            // 참여자 삭제
            List<Chat_Participant__c> mine = [
                SELECT Id
                FROM Chat_Participant__c
                WHERE Chat_Session__c = :sessionId
                  AND User__c = :me
            ];
            if (!mine.isEmpty()) {
                delete mine;
            }

            // 남은 참여자 조회
            List<Chat_Participant__c> remainParts = [
                SELECT User__c
                FROM Chat_Participant__c
                WHERE Chat_Session__c = :sessionId
            ];

            // 남은 참여자가 없으면 세션/메시지도 정리
            if (remainParts.isEmpty()) {
                List<Chat_Message__c> msgs = [
                    SELECT Id
                    FROM Chat_Message__c
                    WHERE Chat_Session__c = :sessionId
                ];
                if (!msgs.isEmpty()) delete msgs;

                delete new Chat_Session__c(Id = sessionId);
                return;
            }

            // 시스템 메시지 생성 (남은 참여자에게만 보이도록 저장)
            Chat_Message__c systemMsg = new Chat_Message__c(
                Chat_Session__c = sessionId,
                Content__c = '[SYSTEM] ' + UserInfo.getName() + '님이 채팅방을 나갔습니다.',
                Sender__c = me
            );
            insert systemMsg;

            // Platform Event 게시 (남은 참여자만 수신하도록 participantIds 포함)
            List<String> participantIds = new List<String>();
            for (Chat_Participant__c p : remainParts) {
                if (p.User__c != null) participantIds.add(String.valueOf(p.User__c).substring(0, 15));
            }

            Chat_Notification__e notif = new Chat_Notification__e(
                Payload__c = JSON.serialize(new Map<String, Object>{
                    'type' => 'System',
                    'sessionId' => sessionId,
                    'messageId' => systemMsg.Id,
                    'senderId' => me,
                    'senderName' => UserInfo.getName(),
                    'content' => systemMsg.Content__c,
                    'hasAttachment' => false,
                    'participantIds' => participantIds
                })
            );
            // 목록 정렬/갱신을 위해 마지막 메시지 시간 갱신 → 그 다음 이벤트 발행
            update new Chat_Session__c(
                Id = sessionId,
                Last_Message_At__c = System.now()
            );
            EventBus.publish(notif);
        } catch (Exception e) {
            throw new AuraHandledException('채팅방 나가기 실패: ' + e.getMessage());
        }
    }

    // 채팅방 삭제 (작성자만 가능): 메시지/참여자까지 함께 삭제
    @AuraEnabled
    public static void deleteChatSession(Id sessionId) {
        if (sessionId == null) return;
        Id me = UserInfo.getUserId();

        try {
            Chat_Session__c session = [
                SELECT Id, CreatedById
                FROM Chat_Session__c
                WHERE Id = :sessionId
                LIMIT 1
            ];

            // 기본 정책: 생성자만 삭제 가능
            if (session.CreatedById != me) {
                throw new AuraHandledException('채팅방 삭제 권한이 없습니다. (생성자만 삭제 가능)');
            }

            List<Chat_Message__c> msgs = [
                SELECT Id
                FROM Chat_Message__c
                WHERE Chat_Session__c = :sessionId
            ];
            if (!msgs.isEmpty()) delete msgs;

            List<Chat_Participant__c> parts = [
                SELECT Id
                FROM Chat_Participant__c
                WHERE Chat_Session__c = :sessionId
            ];
            if (!parts.isEmpty()) delete parts;

            delete session;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('채팅방 삭제 실패: ' + e.getMessage());
        }
    }

    // 채팅방에 참여자 초대 (기존 참여자만 호출 가능)
    @AuraEnabled
    public static void inviteParticipants(Id sessionId, List<Id> userIds) {
        if (sessionId == null) return;
        if (userIds == null || userIds.isEmpty()) return;

        Id me = UserInfo.getUserId();

        try {
            // 호출자가 해당 채팅방 참여자인지 확인
            Integer mine = [
                SELECT COUNT()
                FROM Chat_Participant__c
                WHERE Chat_Session__c = :sessionId
                  AND User__c = :me
            ];
            if (mine == 0) {
                throw new AuraHandledException('참여자가 아닌 사용자는 초대할 수 없습니다.');
            }

            // 기존 참여자 조회
            List<Chat_Participant__c> existing = [
                SELECT User__c
                FROM Chat_Participant__c
                WHERE Chat_Session__c = :sessionId
            ];
            Set<Id> existingUsers = new Set<Id>();
            for (Chat_Participant__c p : existing) {
                if (p.User__c != null) existingUsers.add(p.User__c);
            }

            // 초대 대상(중복 제거, 자기 자신 제외)
            Set<Id> targets = new Set<Id>(userIds);
            targets.remove(me);
            targets.removeAll(existingUsers);
            if (targets.isEmpty()) return;

            // 참여자 추가
            List<Chat_Participant__c> toInsert = new List<Chat_Participant__c>();
            for (Id uid : targets) {
                toInsert.add(new Chat_Participant__c(
                    Chat_Session__c = sessionId,
                    User__c = uid
                ));
            }
            insert toInsert;

            // 추가 후 참여자 목록(전체) 재조회
            List<Chat_Participant__c> allParts = [
                SELECT User__c
                FROM Chat_Participant__c
                WHERE Chat_Session__c = :sessionId
            ];
            List<String> participantIds = new List<String>();
            for (Chat_Participant__c p : allParts) {
                if (p.User__c != null) participantIds.add(String.valueOf(p.User__c).substring(0, 15));
            }

            // 초대된 사용자 이름 조회(시스템 메시지용)
            Map<Id, User> invitedUsers = new Map<Id, User>([
                SELECT Id, Name
                FROM User
                WHERE Id IN :targets
            ]);
            List<String> invitedNames = new List<String>();
            for (Id uid : targets) {
                if (invitedUsers.containsKey(uid)) invitedNames.add(invitedUsers.get(uid).Name + '님');
            }
            // "두 줄 시스템 문구"를 유지하기 위해 너무 긴 초대 대상은 요약 표기합니다.
            // - 1명: "B님"
            // - N명: "B님 외 (N-1)명"
            String namesText = '';
            if (!invitedNames.isEmpty()) {
                if (invitedNames.size() == 1) {
                    namesText = invitedNames[0];
                } else {
                    namesText = invitedNames[0] + ' 외 ' + String.valueOf(invitedNames.size() - 1) + '명';
                }
            }

            // 시스템 메시지 저장
            // 예: "A님이 B님을 초대했습니다." / "A님이 B님 외 2명을 초대했습니다."
            Chat_Message__c systemMsg = new Chat_Message__c(
                Chat_Session__c = sessionId,
                Content__c = '[SYSTEM] ' + UserInfo.getName() + '님이 ' + namesText + '을 초대했습니다.',
                Sender__c = me
            );
            insert systemMsg;

            // Platform Event 게시 (신규 초대자도 participantIds에 포함되므로 수신 가능)
            Chat_Notification__e notif = new Chat_Notification__e(
                Payload__c = JSON.serialize(new Map<String, Object>{
                    'type' => 'System',
                    'sessionId' => sessionId,
                    'messageId' => systemMsg.Id,
                    'senderId' => me,
                    'senderName' => UserInfo.getName(),
                    'content' => systemMsg.Content__c,
                    'hasAttachment' => false,
                    'participantIds' => participantIds
                })
            );
            // 목록 정렬/갱신을 위해 수정 시간 갱신 + 인원이 늘면 Group으로 전환
            Integer countParts = allParts.size();
            Chat_Session__c toUpdate = new Chat_Session__c(Id = sessionId);
            if (countParts > 2) {
                toUpdate.Type__c = 'Group';
            }
            toUpdate.Last_Message_At__c = System.now();
            update toUpdate;

            // 정렬 값이 반영된 뒤 이벤트를 발행해야, 수신자가 리스트를 새로고침했을 때 바로 위로 올라옵니다.
            EventBus.publish(notif);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('참여자 초대 실패: ' + e.getMessage());
        }
    }

    // 사용자 검색 (채팅방 초대용)
    @AuraEnabled(cacheable=true)
    public static List<User> searchUsers(String searchTerm) {
        String key = '%' + searchTerm + '%';
        return [SELECT Id, Name, SmallPhotoUrl FROM User WHERE Name LIKE :key AND IsActive = true LIMIT 10];
    }

    // --- Wrapper Classes ---

    public class CreateOrGetChatResult {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public Boolean existed;
    }

    public class ChatSessionWrapper {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String name;
        @AuraEnabled public String type;
        @AuraEnabled public DateTime lastModified;
        @AuraEnabled public DateTime lastMessageAt;
        @AuraEnabled public Id createdById;
        @AuraEnabled public Integer unreadCount;
        @AuraEnabled public Boolean isPinned;
        @AuraEnabled public Boolean isMuted;
        @AuraEnabled public String lastMessagePreview;

        public ChatSessionWrapper(Chat_Session__c s) {
            this(s, 0, s.LastModifiedDate, false, false, null);
        }

        public ChatSessionWrapper(Chat_Session__c s, Integer unreadCount, DateTime lastMessageAt, Boolean isPinned, Boolean isMuted, String lastMessagePreview) {
            this.sessionId = s.Id;
            this.name = s.Name;
            this.type = s.Type__c;
            this.lastModified = s.LastModifiedDate;
            this.lastMessageAt = lastMessageAt;
            this.createdById = s.CreatedById;
            this.unreadCount = (unreadCount == null) ? 0 : unreadCount;
            this.isPinned = (isPinned == true);
            this.isMuted = (isMuted == true);
            this.lastMessagePreview = (lastMessagePreview == null) ? '' : lastMessagePreview;
        }
    }

    public class MessageWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String content;
        @AuraEnabled public Id senderId;
        @AuraEnabled public String senderName;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Boolean isMine;
        @AuraEnabled public Integer unreadByOthers;
        @AuraEnabled public Integer readByOthers;
        @AuraEnabled public Integer otherParticipantCount;
        @AuraEnabled public AttachmentWrapper attachment;
        @AuraEnabled public Id replyToId;
        @AuraEnabled public String replyToSenderName;
        @AuraEnabled public String replyToPreview;

        public MessageWrapper(Chat_Message__c m) {
            this(m, 0);
        }

        public MessageWrapper(Chat_Message__c m, Integer unreadByOthers) {
            this(m, unreadByOthers, 0, 0);
        }

        public MessageWrapper(Chat_Message__c m, Integer unreadByOthers, Integer readByOthers, Integer otherParticipantCount) {
            this.id = m.Id;
            this.content = m.Content__c;
            this.senderId = m.Sender__c;
            this.senderName = m.Sender__r.Name;
            this.createdDate = m.CreatedDate;
            this.isMine = (m.Sender__c == UserInfo.getUserId());
            this.unreadByOthers = (unreadByOthers == null) ? 0 : unreadByOthers;
            this.readByOthers = (readByOthers == null) ? 0 : readByOthers;
            this.otherParticipantCount = (otherParticipantCount == null) ? 0 : otherParticipantCount;

            // 답장(Reply) 정보
            this.replyToId = m.Reply_To__c;
            if (m.Reply_To__c != null) {
                this.replyToSenderName = (m.Reply_To__r != null && m.Reply_To__r.Sender__r != null)
                    ? m.Reply_To__r.Sender__r.Name
                    : null;
                // Reply_Preview__c가 있으면 그걸 우선 사용, 없으면 원본 메시지 내용 fallback
                this.replyToPreview = (m.Reply_Preview__c != null)
                    ? m.Reply_Preview__c
                    : ((m.Reply_To__r != null) ? m.Reply_To__r.Content__c : null);
            }
            
            if (!m.ContentDocumentLinks.isEmpty()) {
                this.attachment = new AttachmentWrapper(m.ContentDocumentLinks[0]);
            }
        }
    }

    public class AttachmentWrapper {
        @AuraEnabled public Id docId;
        @AuraEnabled public String title;
        @AuraEnabled public String extension;
        @AuraEnabled public Id latestVersionId;

        public AttachmentWrapper(ContentDocumentLink cdl) {
            this.docId = cdl.ContentDocumentId;
            this.title = cdl.ContentDocument.Title;
            this.extension = cdl.ContentDocument.FileExtension;
            this.latestVersionId = cdl.ContentDocument.LatestPublishedVersionId;
        }
    }

    public class ChatParticipantWrapper {
        @AuraEnabled public Id participantId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public DateTime lastReadAt;
        @AuraEnabled public Boolean isPinned;
        @AuraEnabled public Boolean isMuted;
        @AuraEnabled public Boolean isMe;

        public ChatParticipantWrapper(Chat_Participant__c p) {
            this.participantId = p.Id;
            this.userId = p.User__c;
            this.userName = (p.User__r != null) ? p.User__r.Name : '(알 수 없음)';
            this.lastReadAt = p.Last_Read_At__c;
            this.isPinned = (p.Is_Pinned__c == true);
            this.isMuted = (p.Is_Muted__c == true);
            this.isMe = (p.User__c == UserInfo.getUserId());
        }
    }
}