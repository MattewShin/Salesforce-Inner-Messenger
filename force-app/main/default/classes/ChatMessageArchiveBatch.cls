/**
 * ===========================================================================================
 * @description       : Batch class to archive chat messages older than retention period (3 months) 
 *                      by converting them to JSON format and storing in Inner_Chat_Message_Archive__c
 * @author            : CNXK
 * @last modified on  : 2025-03-13
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-03-13   CNXK                Initial version - Archive old messages to JSON chunks
 */
public class ChatMessageArchiveBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    // Retention period in days (3 months = 90 days)
    // Messages older than this will be archived
    private static final Integer RETENTION_DAYS = 90;
    
    // Maximum messages per JSON chunk (to stay within Long Text Area limit)
    private static final Integer MAX_MESSAGES_PER_CHUNK = 100;
    
    // Track statistics
    private Integer totalProcessed = 0;
    private Integer totalArchived = 0;
    private Integer totalChunksCreated = 0;
    private Map<Id, Integer> sessionArchiveCounts = new Map<Id, Integer>();
    
    /**
     * Start method - Query messages older than retention period, grouped by session
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Calculate cutoff date (3 months ago)
        Date cutoffDate = Date.today().addDays(-RETENTION_DAYS);
        DateTime cutoffDateTime = DateTime.newInstance(cutoffDate.year(), cutoffDate.month(), cutoffDate.day(), 0, 0, 0);
        
        // Query messages older than retention period
        // Only get messages from sessions that haven't been archived yet
        return Database.getQueryLocator([
            SELECT Id, Inner_Chat_Session__c, Content__c, Sender__c, CreatedDate,
                   Reply_To__c, Reply_Preview__c,
                   Sender__r.Name
            FROM Inner_Chat_Message__c
            WHERE CreatedDate < :cutoffDateTime
              AND Inner_Chat_Session__r.Archive_Storage_Type__c != 'JSON'
            ORDER BY Inner_Chat_Session__c, CreatedDate ASC
        ]);
    }
    
    /**
     * Execute method - Archive messages by converting to JSON and storing in chunks
     */
    public void execute(Database.BatchableContext bc, List<Inner_Chat_Message__c> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        
        try {
            // Group messages by session
            Map<Id, List<Inner_Chat_Message__c>> messagesBySession = new Map<Id, List<Inner_Chat_Message__c>>();
            for (Inner_Chat_Message__c msg : scope) {
                if (!messagesBySession.containsKey(msg.Inner_Chat_Session__c)) {
                    messagesBySession.put(msg.Inner_Chat_Session__c, new List<Inner_Chat_Message__c>());
                }
                messagesBySession.get(msg.Inner_Chat_Session__c).add(msg);
            }
            
            // Process each session
            for (Id sessionId : messagesBySession.keySet()) {
                List<Inner_Chat_Message__c> sessionMessages = messagesBySession.get(sessionId);
                archiveMessagesForSession(sessionId, sessionMessages);
            }
            
            totalProcessed += scope.size();
            
        } catch (Exception e) {
            System.debug('Error archiving messages in batch: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // Continue processing even if one batch fails
        }
    }
    
    /**
     * Archive messages for a specific session
     */
    private void archiveMessagesForSession(Id sessionId, List<Inner_Chat_Message__c> messages) {
        if (messages == null || messages.isEmpty()) {
            return;
        }
        
        // Get existing archive chunks for this session to determine next chunk index
        List<Inner_Chat_Message_Archive__c> existingChunks = [
            SELECT Chunk_Index__c
            FROM Inner_Chat_Message_Archive__c
            WHERE Inner_Chat_Session__c = :sessionId
            ORDER BY Chunk_Index__c DESC
            LIMIT 1
        ];
        
        Integer nextChunkIndex = 0;
        if (!existingChunks.isEmpty()) {
            nextChunkIndex = Integer.valueOf(existingChunks[0].Chunk_Index__c) + 1;
        }
        
        // Split messages into chunks
        List<List<Inner_Chat_Message__c>> messageChunks = splitIntoChunks(messages, MAX_MESSAGES_PER_CHUNK);
        
        // Create archive chunks
        List<Inner_Chat_Message_Archive__c> archiveChunks = new List<Inner_Chat_Message_Archive__c>();
        
        for (List<Inner_Chat_Message__c> chunk : messageChunks) {
            // Convert messages to JSON
            List<Map<String, Object>> messageData = new List<Map<String, Object>>();
            DateTime firstDate = null;
            DateTime lastDate = null;
            
            for (Inner_Chat_Message__c msg : chunk) {
                Map<String, Object> msgData = new Map<String, Object>{
                    'id' => String.valueOf(msg.Id).substring(0, 15),
                    'content' => msg.Content__c,
                    'senderId' => msg.Sender__c != null ? String.valueOf(msg.Sender__c).substring(0, 15) : null,
                    'senderName' => msg.Sender__r != null ? msg.Sender__r.Name : null,
                    'createdDate' => msg.CreatedDate != null ? msg.CreatedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') : null,
                    'replyToId' => msg.Reply_To__c != null ? String.valueOf(msg.Reply_To__c).substring(0, 15) : null,
                    'replyPreview' => msg.Reply_Preview__c
                };
                messageData.add(msgData);
                
                // Track date range
                if (firstDate == null || msg.CreatedDate < firstDate) {
                    firstDate = msg.CreatedDate;
                }
                if (lastDate == null || msg.CreatedDate > lastDate) {
                    lastDate = msg.CreatedDate;
                }
            }
            
            String jsonString = JSON.serialize(messageData);
            
            // Create archive chunk
            Inner_Chat_Message_Archive__c archiveChunk = new Inner_Chat_Message_Archive__c(
                Inner_Chat_Session__c = sessionId,
                Chunk_Index__c = nextChunkIndex,
                Messages_JSON__c = jsonString,
                Message_Count__c = chunk.size(),
                First_Message_Date__c = firstDate,
                Last_Message_Date__c = lastDate
            );
            
            archiveChunks.add(archiveChunk);
            nextChunkIndex++;
            totalArchived += chunk.size();
        }
        
        // Insert archive chunks
        if (!archiveChunks.isEmpty()) {
            insert archiveChunks;
            totalChunksCreated += archiveChunks.size();
            
            // Track archive count for this session
            if (!sessionArchiveCounts.containsKey(sessionId)) {
                sessionArchiveCounts.put(sessionId, 0);
            }
            sessionArchiveCounts.put(sessionId, sessionArchiveCounts.get(sessionId) + messages.size());
        }
        
        // Delete original messages (ContentDocumentLinks will be handled by cascade delete or separately)
        // Note: We keep ContentDocuments as they may be referenced elsewhere
        delete messages;
        
        // Update session archive metadata
        updateSessionArchiveMetadata(sessionId);
    }
    
    /**
     * Split list into chunks of specified size
     */
    private List<List<Inner_Chat_Message__c>> splitIntoChunks(List<Inner_Chat_Message__c> messages, Integer chunkSize) {
        List<List<Inner_Chat_Message__c>> chunks = new List<List<Inner_Chat_Message__c>>();
        
        for (Integer i = 0; i < messages.size(); i += chunkSize) {
            Integer endIndex = Math.min(i + chunkSize, messages.size());
            List<Inner_Chat_Message__c> chunk = new List<Inner_Chat_Message__c>();
            for (Integer j = i; j < endIndex; j++) {
                chunk.add(messages[j]);
            }
            chunks.add(chunk);
        }
        
        return chunks;
    }
    
    /**
     * Update session metadata with archive counts
     */
    private void updateSessionArchiveMetadata(Id sessionId) {
        // Count active messages (not archived)
        Integer activeCount = [
            SELECT COUNT()
            FROM Inner_Chat_Message__c
            WHERE Inner_Chat_Session__c = :sessionId
        ];
        
        // Count archived messages
        Integer archivedCount = 0;
        List<Inner_Chat_Message_Archive__c> chunks = [
            SELECT Message_Count__c
            FROM Inner_Chat_Message_Archive__c
            WHERE Inner_Chat_Session__c = :sessionId
        ];
        for (Inner_Chat_Message_Archive__c chunk : chunks) {
            archivedCount += Integer.valueOf(chunk.Message_Count__c);
        }
        
        // Update session
        Inner_Chat_Session__c session = new Inner_Chat_Session__c(
            Id = sessionId,
            Active_Message_Count__c = activeCount,
            Archived_Message_Count__c = archivedCount,
            Archive_Storage_Type__c = 'JSON',
            Last_Archive_Date__c = System.now()
        );
        update session;
    }
    
    /**
     * Finish method - Log completion statistics
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('ChatMessageArchiveBatch completed.');
        System.debug('Total messages processed: ' + totalProcessed);
        System.debug('Total messages archived: ' + totalArchived);
        System.debug('Total chunks created: ' + totalChunksCreated);
        System.debug('Sessions processed: ' + sessionArchiveCounts.size());
        
        // Optional: Send notification email or create a log record
        // You can add custom notification logic here if needed
    }
}
