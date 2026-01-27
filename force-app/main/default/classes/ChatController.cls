/**
 * ===========================================================================================
 * @description       : Controller for Internal Chat functionality (sessions, messages, participants, Platform Events)
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Chat session management, message sending/receiving, participant management, and real-time notifications via Platform Events
 */
public with sharing class ChatController {
    
    // Retrieve chat sessions the current user is participating in
    @AuraEnabled
    public static List<ChatSessionWrapper> getChatSessions() {
        Id currentUserId = UserInfo.getUserId();
        
        List<Inner_Chat_Participant__c> participations = [
            SELECT Inner_Chat_Session__c, Inner_Chat_Session__r.Name, Inner_Chat_Session__r.Type__c,
                   Inner_Chat_Session__r.LastModifiedDate, Inner_Chat_Session__r.CreatedById,
                   Inner_Chat_Session__r.Last_Message_At__c,
                   Last_Read_At__c,
                   Is_Pinned__c,
                   Is_Muted__c
            FROM Inner_Chat_Participant__c
            WHERE User__c = :currentUserId
            ORDER BY Is_Pinned__c DESC, Inner_Chat_Session__r.Last_Message_At__c DESC, Inner_Chat_Session__r.LastModifiedDate DESC
        ];
        
        // Calculate unread message count: Messages in session after Last_Read_At__c (excluding system messages and own messages)
        Map<Id, DateTime> lastReadMap = new Map<Id, DateTime>();
        Set<Id> sessionIds = new Set<Id>();
        DateTime minLastRead = null;
        for (Inner_Chat_Participant__c p : participations) {
            sessionIds.add(p.Inner_Chat_Session__c);
            DateTime lr = p.Last_Read_At__c;
            if (lr == null) lr = DateTime.newInstance(1970, 1, 1, 0, 0, 0); // Unread state (entire conversation)
            lastReadMap.put(p.Inner_Chat_Session__c, lr);
            if (minLastRead == null || lr < minLastRead) minLastRead = lr;
        }

        Map<Id, Integer> unreadMap = new Map<Id, Integer>();
        if (!sessionIds.isEmpty() && minLastRead != null) {
            List<Inner_Chat_Message__c> msgs = [
                SELECT Inner_Chat_Session__c, CreatedDate, Sender__c, Content__c
                FROM Inner_Chat_Message__c
                WHERE Inner_Chat_Session__c IN :sessionIds
                  AND CreatedDate > :minLastRead
                ORDER BY CreatedDate ASC
            ];
            for (Inner_Chat_Message__c m : msgs) {
                // Skip own messages from unread count
                if (m.Sender__c == currentUserId) continue;
                // Skip system messages from unread count (may change based on requirements)
                if (m.Content__c != null && m.Content__c.startsWith('[SYSTEM]')) continue;

                DateTime lr = lastReadMap.get(m.Inner_Chat_Session__c);
                if (lr != null && m.CreatedDate <= lr) continue;

                Integer cur = unreadMap.containsKey(m.Inner_Chat_Session__c) ? unreadMap.get(m.Inner_Chat_Session__c) : 0;
                unreadMap.put(m.Inner_Chat_Session__c, cur + 1);
            }
        }

        // Get last message preview (excluding system messages)
        Map<Id, String> lastPreviewMap = new Map<Id, String>();
        if (!sessionIds.isEmpty()) {
            List<Inner_Chat_Message__c> latestMsgs = [
                SELECT Inner_Chat_Session__c, Content__c, CreatedDate
                FROM Inner_Chat_Message__c
                WHERE Inner_Chat_Session__c IN :sessionIds
                ORDER BY CreatedDate DESC
            ];
            for (Inner_Chat_Message__c m : latestMsgs) {
                if (m.Inner_Chat_Session__c == null) continue;
                if (lastPreviewMap.containsKey(m.Inner_Chat_Session__c)) continue; // One message per session
                String c = (m.Content__c == null) ? '' : m.Content__c;
                // Exclude system messages from preview
                if (!String.isBlank(c) && c.startsWith('[SYSTEM]')) continue;
                c = c.replace('\n', ' ').replace('\r', ' ').trim();
                // Truncate if too long (final ... handled in UI)
                Integer maxLen = 80;
                if (c.length() > maxLen) {
                    c = c.substring(0, maxLen - 3) + '...';
                }
                lastPreviewMap.put(m.Inner_Chat_Session__c, c);
            }
        }

        List<ChatSessionWrapper> results = new List<ChatSessionWrapper>();
        for (Inner_Chat_Participant__c p : participations) {
            Integer unread = unreadMap.containsKey(p.Inner_Chat_Session__c) ? unreadMap.get(p.Inner_Chat_Session__c) : 0;
            DateTime lastMsgAt = (p.Inner_Chat_Session__r.Last_Message_At__c != null)
                ? p.Inner_Chat_Session__r.Last_Message_At__c
                : p.Inner_Chat_Session__r.LastModifiedDate; // Fallback if no messages
            String preview = lastPreviewMap.containsKey(p.Inner_Chat_Session__c) ? lastPreviewMap.get(p.Inner_Chat_Session__c) : '';
            results.add(new ChatSessionWrapper(p.Inner_Chat_Session__r, unread, lastMsgAt, p.Is_Pinned__c, p.Is_Muted__c, preview));
        }
        return results;
    }

    // Retrieve single chat session (after creation for UI refresh)
    @AuraEnabled
    public static ChatSessionWrapper getChatSession(Id sessionId) {
        if (sessionId == null) return null;

        Id me = UserInfo.getUserId();
        Integer mine = [
            SELECT COUNT()
            FROM Inner_Chat_Participant__c
            WHERE Inner_Chat_Session__c = :sessionId
              AND User__c = :me
        ];
        if (mine == 0) {
            throw new AuraHandledException('Non-participant users cannot retrieve chat session information.');
        }

        Inner_Chat_Session__c s = [
            SELECT Id, Name, Type__c, LastModifiedDate, CreatedById, Last_Message_At__c
            FROM Inner_Chat_Session__c
            WHERE Id = :sessionId
            LIMIT 1
        ];
        DateTime lastMsgAt = (s.Last_Message_At__c != null) ? s.Last_Message_At__c : s.LastModifiedDate;
        return new ChatSessionWrapper(s, 0, lastMsgAt, false, false, null);
    }

    // Set pin status for chat session
    @AuraEnabled
    public static void setPinned(Id sessionId, Boolean pinned) {
        if (sessionId == null) return;
        Id me = UserInfo.getUserId();
        Boolean willPin = (pinned == true);

        List<Inner_Chat_Participant__c> mine = [
            SELECT Id, Is_Pinned__c
            FROM Inner_Chat_Participant__c
            WHERE Inner_Chat_Session__c = :sessionId
              AND User__c = :me
            LIMIT 1
        ];
        if (mine.isEmpty()) return;

        // If already pinned and pin requested again, do nothing
        if (willPin && mine[0].Is_Pinned__c == true) return;

        // Pinned sessions limited to 3 maximum
        if (willPin) {
            Integer pinnedCount = [
                SELECT COUNT()
                FROM Inner_Chat_Participant__c
                WHERE User__c = :me
                  AND Is_Pinned__c = true
            ];
            if (pinnedCount >= 3) {
                throw new AuraHandledException('Chat pin limit is 3 maximum.');
            }
        }

        mine[0].Is_Pinned__c = willPin;
        update mine[0];
    }

    // Set mute status for chat session
    @AuraEnabled
    public static void setMuted(Id sessionId, Boolean muted) {
        if (sessionId == null) return;
        Id me = UserInfo.getUserId();
        List<Inner_Chat_Participant__c> mine = [
            SELECT Id, Is_Muted__c
            FROM Inner_Chat_Participant__c
            WHERE Inner_Chat_Session__c = :sessionId
              AND User__c = :me
            LIMIT 1
        ];
        if (mine.isEmpty()) return;
        mine[0].Is_Muted__c = (muted == true);
        update mine[0];
    }

    // Retrieve list of participants (users currently in chat)
    @AuraEnabled
    public static List<ChatParticipantWrapper> getParticipants(Id sessionId) {
        if (sessionId == null) return new List<ChatParticipantWrapper>();

        Id me = UserInfo.getUserId();
        Integer mine = [
            SELECT COUNT()
            FROM Inner_Chat_Participant__c
            WHERE Inner_Chat_Session__c = :sessionId
              AND User__c = :me
        ];
        if (mine == 0) {
            throw new AuraHandledException('Non-participant users cannot retrieve participant list.');
        }

        List<Inner_Chat_Participant__c> parts = [
            SELECT Id,
                   User__c, User__r.Name,
                   Last_Read_At__c,
                   Is_Pinned__c,
                   Is_Muted__c
            FROM Inner_Chat_Participant__c
            WHERE Inner_Chat_Session__c = :sessionId
            ORDER BY User__r.Name ASC
        ];

        List<ChatParticipantWrapper> results = new List<ChatParticipantWrapper>();
        for (Inner_Chat_Participant__c p : parts) {
            results.add(new ChatParticipantWrapper(p));
        }
        return results;
    }

    // Mark chat session as read (update current user's participant Last_Read_At__c)
    @AuraEnabled
    public static void markSessionAsRead(Id sessionId) {
        if (sessionId == null) return;
        Id me = UserInfo.getUserId();

        List<Inner_Chat_Participant__c> mine = [
            SELECT Id, Last_Read_At__c
            FROM Inner_Chat_Participant__c
            WHERE Inner_Chat_Session__c = :sessionId
              AND User__c = :me
            LIMIT 1
        ];
        if (mine.isEmpty()) return;

        // Important: "view receipt" is NOT the same as "read receipt for latest message".
        // ReadReceipt Platform Event must avoid infinite loops.
        DateTime latestMsgAt = null;
        List<Inner_Chat_Message__c> latest = [
            SELECT CreatedDate
            FROM Inner_Chat_Message__c
            WHERE Inner_Chat_Session__c = :sessionId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!latest.isEmpty()) latestMsgAt = latest[0].CreatedDate;
        if (latestMsgAt == null) return;

        DateTime prev = mine[0].Last_Read_At__c;
        if (prev != null && prev >= latestMsgAt) return; // Already up to date

        mine[0].Last_Read_At__c = latestMsgAt;
        update mine[0];

        // Publish read receipt Platform Event (for immediate UI refresh)
        if (prev == null || prev < latestMsgAt) {
            List<Inner_Chat_Participant__c> parts = [
                SELECT User__c
                FROM Inner_Chat_Participant__c
                WHERE Inner_Chat_Session__c = :sessionId
            ];
            List<String> participantIds = new List<String>();
            for (Inner_Chat_Participant__c p : parts) {
                if (p.User__c != null) participantIds.add(String.valueOf(p.User__c).substring(0, 15));
            }

            Inner_Chat_Notification__e notif = new Inner_Chat_Notification__e(
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

    // Get messages for specific chat session
    // Real-time synchronization is important, so caching is not recommended.
    @AuraEnabled
    public static List<MessageWrapper> getMessages(Id sessionId) {
        Map<Id, DateTime> lastReadByUser = new Map<Id, DateTime>();
        for (Inner_Chat_Participant__c p : [
            SELECT User__c, Last_Read_At__c
            FROM Inner_Chat_Participant__c
            WHERE Inner_Chat_Session__c = :sessionId
        ]) {
            if (p.User__c != null) lastReadByUser.put(p.User__c, p.Last_Read_At__c);
        }
        Integer totalParticipants = lastReadByUser.size();

        List<Inner_Chat_Message__c> msgs = [
            SELECT Id, Content__c, Sender__c, Sender__r.Name, CreatedDate,
                   Reply_To__c, Reply_Preview__c,
                   Reply_To__r.Content__c, Reply_To__r.Sender__r.Name,
                   (SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension, ContentDocument.LatestPublishedVersionId
                    FROM ContentDocumentLinks LIMIT 1)
            FROM Inner_Chat_Message__c
            WHERE Inner_Chat_Session__c = :sessionId
            ORDER BY CreatedDate ASC
            LIMIT 50
        ];
        
        List<MessageWrapper> results = new List<MessageWrapper>();
        for (Inner_Chat_Message__c msg : msgs) {
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

    // Get paged messages (infinite scroll)
    // - before: if null, returns latest limitSize messages
    // - if before is set, returns limitSize messages before that timestamp
    // Returns ordered by CreatedDate ASC (oldest first)
    @AuraEnabled
    public static List<MessageWrapper> getMessagesPaged(Id sessionId, Datetime before, Integer limitSize) {
        if (sessionId == null) return new List<MessageWrapper>();
        Integer lim = (limitSize == null || limitSize <= 0) ? 50 : Math.min(limitSize, 200);

        Map<Id, DateTime> lastReadByUser = new Map<Id, DateTime>();
        for (Inner_Chat_Participant__c p : [
            SELECT User__c, Last_Read_At__c
            FROM Inner_Chat_Participant__c
            WHERE Inner_Chat_Session__c = :sessionId
        ]) {
            if (p.User__c != null) lastReadByUser.put(p.User__c, p.Last_Read_At__c);
        }
        Integer totalParticipants = lastReadByUser.size();

        // Query newest messages first (ORDER BY DESC) then reverse order to ASC for display
        List<Inner_Chat_Message__c> msgs;
        if (before == null) {
            msgs = [
                SELECT Id, Content__c, Sender__c, Sender__r.Name, CreatedDate,
                       Reply_To__c, Reply_Preview__c,
                       Reply_To__r.Content__c, Reply_To__r.Sender__r.Name,
                       (SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension, ContentDocument.LatestPublishedVersionId
                        FROM ContentDocumentLinks LIMIT 1)
                FROM Inner_Chat_Message__c
                WHERE Inner_Chat_Session__c = :sessionId
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
                FROM Inner_Chat_Message__c
                WHERE Inner_Chat_Session__c = :sessionId
                  AND CreatedDate < :before
                ORDER BY CreatedDate DESC
                LIMIT :lim
            ];
        }

        List<MessageWrapper> results = new List<MessageWrapper>();
        // Since queried DESC, reverse order to ASC for rendering
        for (Integer i = msgs.size() - 1; i >= 0; i--) {
            Inner_Chat_Message__c msg = msgs[i];
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

    // Send message and publish notification
    @AuraEnabled
    public static void sendMessage(Id sessionId, String content, Id contentDocumentId, Id replyToMessageId, String replyPreview) {
        try {
            // 1. Create message
            String preview = replyPreview;
            if (preview != null && preview.length() > 255) {
                preview = preview.substring(0, 252) + '...';
            }
            Inner_Chat_Message__c newMsg = new Inner_Chat_Message__c(
                Inner_Chat_Session__c = sessionId,
                Content__c = content,
                Sender__c = UserInfo.getUserId(),
                Reply_To__c = replyToMessageId,
                Reply_Preview__c = preview
            );
            insert newMsg;

            // 2. Link file if attachment provided
            if (contentDocumentId != null) {
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = contentDocumentId;
                cdl.LinkedEntityId = newMsg.Id;
                cdl.ShareType = 'V'; // Viewer permission
                insert cdl;
            }

            // 3. Update chat session last message time (for sorting)
            // Note: Must update before Platform Event publish, so on listener receives event and refreshes list, UI immediately reflects new order
            update new Inner_Chat_Session__c(
                Id = sessionId,
                Last_Message_At__c = System.now()
            );

            // 4. Publish Platform Event (real-time notification)
            // Send to all participants in session; listener ignores non-participant notifications
            List<Inner_Chat_Participant__c> participants = [
                SELECT User__c
                FROM Inner_Chat_Participant__c
                WHERE Inner_Chat_Session__c = :sessionId
            ];
            List<String> participantIds = new List<String>();
            for (Inner_Chat_Participant__c p : participants) {
                if (p.User__c != null) participantIds.add(String.valueOf(p.User__c).substring(0, 15));
            }

            Inner_Chat_Notification__e notif = new Inner_Chat_Notification__e(
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
            throw new AuraHandledException('Message send failed: ' + e.getMessage());
        }
    }

    // Create new chat session (group or 1:1)
    @AuraEnabled
    public static Id createChatSession(String name, List<Id> userIds) {
        // Auto-generate session name from participant names if not provided
        String finalName = name;
        if (String.isBlank(finalName)) {
            Set<Id> uniqueUsers = new Set<Id>(userIds);
            uniqueUsers.add(UserInfo.getUserId());
            List<User> users = [SELECT Id, Name FROM User WHERE Id IN :uniqueUsers ORDER BY Name ASC];
            List<String> names = new List<String>();
            for (User u : users) names.add(u.Name);
            finalName = String.join(names, ', ');

            // Truncate Name field if exceeds max length (typically 80)
            Integer maxLen = 80;
            if (finalName.length() > maxLen) {
                finalName = finalName.substring(0, maxLen - 3) + '...';
            }
        }

        // Create chat session
        Inner_Chat_Session__c session = new Inner_Chat_Session__c(
            Name = finalName,
            Type__c = (userIds.size() > 1) ? 'Group' : 'Direct'
        );
        insert session;

        // Add participants (including current user)
        List<Inner_Chat_Participant__c> participants = new List<Inner_Chat_Participant__c>();
        Set<Id> uniqueUsers = new Set<Id>(userIds);
        uniqueUsers.add(UserInfo.getUserId());

        for (Id uid : uniqueUsers) {
            participants.add(new Inner_Chat_Participant__c(
                Inner_Chat_Session__c = session.Id,
                User__c = uid,
                // Mark as read from creation for current user only
                Last_Read_At__c = (uid == UserInfo.getUserId()) ? System.now() : null
            ));
        }
        insert participants;

        return session.Id;
    }

    // Create or get existing Direct chat session
    // - For 1:1 sessions, if existing Direct session already exists, returns that instead of creating new
    @AuraEnabled
    public static CreateOrGetChatResult createOrGetChatSession(String name, List<Id> userIds) {
        CreateOrGetChatResult res = new CreateOrGetChatResult();
        res.existed = false;

        if (userIds == null || userIds.isEmpty()) {
            // No creation possible without participant selection
            throw new AuraHandledException('Please select participants.');
        }

        Id me = UserInfo.getUserId();

        // Before creating 1:1 session, search for existing one
        if (userIds.size() == 1) {
            Id other = userIds[0];
            if (other != null && other != me) {
                Set<Id> pair = new Set<Id>{ me, other };

                // Check if Direct chat session already exists with both users
                // - Type__c = 'Direct'
                // - Participants = 2
                List<AggregateResult> ars = [
                    SELECT Inner_Chat_Session__c sessionId,
                           MAX(Inner_Chat_Session__r.LastModifiedDate) lastMod,
                           COUNT(Id) cnt,
                           COUNT_DISTINCT(User__c) userCnt
                    FROM Inner_Chat_Participant__c
                    WHERE User__c IN :pair
                      AND Inner_Chat_Session__r.Type__c = 'Direct'
                    GROUP BY Inner_Chat_Session__c
                    HAVING COUNT(Id) = 2 AND COUNT_DISTINCT(User__c) = 2
                    ORDER BY MAX(Inner_Chat_Session__r.LastModifiedDate) DESC
                    LIMIT 1
                ];

                if (!ars.isEmpty()) {
                    res.sessionId = (Id) ars[0].get('sessionId');
                    res.existed = true;
                    return res;
                }
            }
        }

        // No existing session found, create new one
        res.sessionId = createChatSession(name, userIds);
        res.existed = false;
        return res;
    }

    // Rename chat session (participants only)
    @AuraEnabled
    public static void renameChatSession(Id sessionId, String newName) {
        if (sessionId == null) return;
        if (String.isBlank(newName)) {
            throw new AuraHandledException('Please enter chat session name.');
        }

        Id me = UserInfo.getUserId();
        Integer mine = [
            SELECT COUNT()
            FROM Inner_Chat_Participant__c
            WHERE Inner_Chat_Session__c = :sessionId
              AND User__c = :me
        ];
        if (mine == 0) {
            throw new AuraHandledException('Non-participant users cannot rename chat session.');
        }

        try {
            update new Inner_Chat_Session__c(
                Id = sessionId,
                Name = newName
            );

            // Get all participants for notification (non-participants ignore event)
            List<Inner_Chat_Participant__c> parts = [
                SELECT User__c
                FROM Inner_Chat_Participant__c
                WHERE Inner_Chat_Session__c = :sessionId
            ];
            List<String> participantIds = new List<String>();
            for (Inner_Chat_Participant__c p : parts) {
                if (p.User__c != null) participantIds.add(String.valueOf(p.User__c).substring(0, 15));
            }

            // Publish session renamed event (immediate UI refresh)
            Inner_Chat_Notification__e notif = new Inner_Chat_Notification__e(
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
            throw new AuraHandledException('Rename failed: ' + e.getMessage());
        }
    }

    // Leave chat session (current user only removed from participants)
    @AuraEnabled
    public static void leaveChatSession(Id sessionId) {
        if (sessionId == null) return;
        Id me = UserInfo.getUserId();

        try {
            // Remove current user from participants
            List<Inner_Chat_Participant__c> mine = [
                SELECT Id
                FROM Inner_Chat_Participant__c
                WHERE Inner_Chat_Session__c = :sessionId
                  AND User__c = :me
            ];
            if (!mine.isEmpty()) {
                delete mine;
            }

            // Check remaining participants
            List<Inner_Chat_Participant__c> remainParts = [
                SELECT User__c
                FROM Inner_Chat_Participant__c
                WHERE Inner_Chat_Session__c = :sessionId
            ];

            // If no remaining participants, delete session and messages
            if (remainParts.isEmpty()) {
                List<Inner_Chat_Message__c> msgs = [
                    SELECT Id
                    FROM Inner_Chat_Message__c
                    WHERE Inner_Chat_Session__c = :sessionId
                ];
                if (!msgs.isEmpty()) delete msgs;

                delete new Inner_Chat_Session__c(Id = sessionId);
                return;
            }

            // Create system message (visible to remaining participants only)
            Inner_Chat_Message__c systemMsg = new Inner_Chat_Message__c(
                Inner_Chat_Session__c = sessionId,
                Content__c = '[SYSTEM] ' + UserInfo.getName() + ' left the chat.',
                Sender__c = me
            );
            insert systemMsg;

            // Publish event (remaining participants only notified)
            List<String> participantIds = new List<String>();
            for (Inner_Chat_Participant__c p : remainParts) {
                if (p.User__c != null) participantIds.add(String.valueOf(p.User__c).substring(0, 15));
            }

            Inner_Chat_Notification__e notif = new Inner_Chat_Notification__e(
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
            // Update last message time for sorting/refresh
            update new Inner_Chat_Session__c(
                Id = sessionId,
                Last_Message_At__c = System.now()
            );
            EventBus.publish(notif);
        } catch (Exception e) {
            throw new AuraHandledException('Leave failed: ' + e.getMessage());
        }
    }

    // Delete chat session (creator only; deletes messages and participants too)
    @AuraEnabled
    public static void deleteChatSession(Id sessionId) {
        if (sessionId == null) return;
        Id me = UserInfo.getUserId();

        try {
            Inner_Chat_Session__c session = [
                SELECT Id, CreatedById
                FROM Inner_Chat_Session__c
                WHERE Id = :sessionId
                LIMIT 1
            ];

            // Security: Only creator can delete
            if (session.CreatedById != me) {
                throw new AuraHandledException('Only creator can delete chat session.');
            }

            List<Inner_Chat_Message__c> msgs = [
                SELECT Id
                FROM Inner_Chat_Message__c
                WHERE Inner_Chat_Session__c = :sessionId
            ];
            if (!msgs.isEmpty()) delete msgs;

            List<Inner_Chat_Participant__c> parts = [
                SELECT Id
                FROM Inner_Chat_Participant__c
                WHERE Inner_Chat_Session__c = :sessionId
            ];
            if (!parts.isEmpty()) delete parts;

            delete session;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Delete failed: ' + e.getMessage());
        }
    }

    // Invite participants to chat session (only existing participants can invite)
    @AuraEnabled
    public static void inviteParticipants(Id sessionId, List<Id> userIds) {
        if (sessionId == null) return;
        if (userIds == null || userIds.isEmpty()) return;

        Id me = UserInfo.getUserId();

        try {
            // Verify inviter is participant in chat session
            Integer mine = [
                SELECT COUNT()
                FROM Inner_Chat_Participant__c
                WHERE Inner_Chat_Session__c = :sessionId
                  AND User__c = :me
            ];
            if (mine == 0) {
                throw new AuraHandledException('Non-participants cannot invite.');
            }

            // Get existing participants
            List<Inner_Chat_Participant__c> existing = [
                SELECT User__c
                FROM Inner_Chat_Participant__c
                WHERE Inner_Chat_Session__c = :sessionId
            ];
            Set<Id> existingUsers = new Set<Id>();
            for (Inner_Chat_Participant__c p : existing) {
                if (p.User__c != null) existingUsers.add(p.User__c);
            }

            // Remove duplicates and self from invite list
            Set<Id> targets = new Set<Id>(userIds);
            targets.remove(me);
            targets.removeAll(existingUsers);
            if (targets.isEmpty()) return;

            // Add new participants
            List<Inner_Chat_Participant__c> toInsert = new List<Inner_Chat_Participant__c>();
            for (Id uid : targets) {
                toInsert.add(new Inner_Chat_Participant__c(
                    Inner_Chat_Session__c = sessionId,
                    User__c = uid
                ));
            }
            insert toInsert;

            // Get all participants for notification
            List<Inner_Chat_Participant__c> allParts = [
                SELECT User__c
                FROM Inner_Chat_Participant__c
                WHERE Inner_Chat_Session__c = :sessionId
            ];
            List<String> participantIds = new List<String>();
            for (Inner_Chat_Participant__c p : allParts) {
                if (p.User__c != null) participantIds.add(String.valueOf(p.User__c).substring(0, 15));
            }

            // Get invited user names (for system message)
            Map<Id, User> invitedUsers = new Map<Id, User>([
                SELECT Id, Name
                FROM User
                WHERE Id IN :targets
            ]);
            List<String> invitedNames = new List<String>();
            for (Id uid : targets) {
                if (invitedUsers.containsKey(uid)) invitedNames.add(invitedUsers.get(uid).Name);
            }
            // Format system message to keep it concise
            // - 1 user: "B"
            // - N users: "B (and N-1 more)"
            String namesText = '';
            if (!invitedNames.isEmpty()) {
                if (invitedNames.size() == 1) {
                    namesText = invitedNames[0];
                } else {
                    namesText = invitedNames[0] + ' (and ' + String.valueOf(invitedNames.size() - 1) + ' more)';
                }
            }

            // Create system message
            // Example: "A invited B." / "A invited B (and 2 more)."
            Inner_Chat_Message__c systemMsg = new Inner_Chat_Message__c(
                Inner_Chat_Session__c = sessionId,
                Content__c = '[SYSTEM] ' + UserInfo.getName() + ' invited ' + namesText + '.',
                Sender__c = me
            );
            insert systemMsg;

            // Publish event (new invitees also see notification via participantIds)
            Inner_Chat_Notification__e notif = new Inner_Chat_Notification__e(
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
            // Update last message time for sorting + change type to Group if count > 2
            Integer countParts = allParts.size();
            Inner_Chat_Session__c toUpdate = new Inner_Chat_Session__c(Id = sessionId);
            if (countParts > 2) {
                toUpdate.Type__c = 'Group';
            }
            toUpdate.Last_Message_At__c = System.now();
            update toUpdate;

            // Publish event after update so UI refresh picks up new state
            EventBus.publish(notif);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Invite failed: ' + e.getMessage());
        }
    }

    // Search users (for chat participant selection)
    @AuraEnabled(cacheable=true)
    public static List<User> searchUsers(String searchTerm) {
        String key = '%' + searchTerm + '%';
        return [SELECT Id, Name, SmallPhotoUrl FROM User WHERE Name LIKE :key AND IsActive = true LIMIT 10];
    }

    // --- Wrapper Classes ---

    /**
     * Result wrapper for createOrGetChatSession operation
     */
    public class CreateOrGetChatResult {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public Boolean existed;
    }

    /**
     * Wrapper for chat session display
     */
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

        public ChatSessionWrapper(Inner_Chat_Session__c s) {
            this(s, 0, s.LastModifiedDate, false, false, null);
        }

        public ChatSessionWrapper(Inner_Chat_Session__c s, Integer unreadCount, DateTime lastMessageAt, Boolean isPinned, Boolean isMuted, String lastMessagePreview) {
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

    /**
     * Wrapper for chat message display
     */
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

        public MessageWrapper(Inner_Chat_Message__c m) {
            this(m, 0);
        }

        public MessageWrapper(Inner_Chat_Message__c m, Integer unreadByOthers) {
            this(m, unreadByOthers, 0, 0);
        }

        public MessageWrapper(Inner_Chat_Message__c m, Integer unreadByOthers, Integer readByOthers, Integer otherParticipantCount) {
            this.id = m.Id;
            this.content = m.Content__c;
            this.senderId = m.Sender__c;
            this.senderName = m.Sender__r.Name;
            this.createdDate = m.CreatedDate;
            this.isMine = (m.Sender__c == UserInfo.getUserId());
            this.unreadByOthers = (unreadByOthers == null) ? 0 : unreadByOthers;
            this.readByOthers = (readByOthers == null) ? 0 : readByOthers;
            this.otherParticipantCount = (otherParticipantCount == null) ? 0 : otherParticipantCount;

            // Reply information
            this.replyToId = m.Reply_To__c;
            if (m.Reply_To__c != null) {
                this.replyToSenderName = (m.Reply_To__r != null && m.Reply_To__r.Sender__r != null)
                    ? m.Reply_To__r.Sender__r.Name
                    : null;
                // Use Reply_Preview__c if available, otherwise use original message content as fallback
                this.replyToPreview = (m.Reply_Preview__c != null)
                    ? m.Reply_Preview__c
                    : ((m.Reply_To__r != null) ? m.Reply_To__r.Content__c : null);
            }
            
            if (!m.ContentDocumentLinks.isEmpty()) {
                this.attachment = new AttachmentWrapper(m.ContentDocumentLinks[0]);
            }
        }
    }

    /**
     * Wrapper for message attachment information
     */
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

    /**
     * Wrapper for chat participant display
     */
    public class ChatParticipantWrapper {
        @AuraEnabled public Id participantId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public DateTime lastReadAt;
        @AuraEnabled public Boolean isPinned;
        @AuraEnabled public Boolean isMuted;
        @AuraEnabled public Boolean isMe;

        public ChatParticipantWrapper(Inner_Chat_Participant__c p) {
            this.participantId = p.Id;
            this.userId = p.User__c;
            this.userName = (p.User__r != null) ? p.User__r.Name : '(Unknown)';
            this.lastReadAt = p.Last_Read_At__c;
            this.isPinned = (p.Is_Pinned__c == true);
            this.isMuted = (p.Is_Muted__c == true);
            this.isMe = (p.User__c == UserInfo.getUserId());
        }
    }
}
