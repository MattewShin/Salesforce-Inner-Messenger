/**
 * ===========================================================================================
 * @description       : Batch class to delete chat messages and archive chunks older than 1 year
 *                      This is the final cleanup step in the 2-stage retention policy:
 *                      1. Archive messages older than 3 months (ChatMessageArchiveBatch)
 *                      2. Delete messages and archives older than 1 year (this batch)
 * @author            : CNXK
 * @last modified on  : 2025-03-13
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-03-06   CNXK                Initial version - Batch job to delete messages older than 1 year
 * 2.0   2025-03-13   CNXK                Updated to handle both active messages and archive chunks
 */
public class ChatMessageCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    // Retention period in days (1 year = 365 days)
    private static final Integer RETENTION_DAYS = 365;
    
    // Track statistics
    private Integer totalProcessed = 0;
    private Integer totalDeleted = 0;
    private Integer totalArchiveChunksDeleted = 0;
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Calculate cutoff date (1 year ago)
        Date cutoffDate = Date.today().addDays(-RETENTION_DAYS);
        DateTime cutoffDateTime = DateTime.newInstance(cutoffDate.year(), cutoffDate.month(), cutoffDate.day(), 0, 0, 0);
        
        // Query messages older than 1 year
        return Database.getQueryLocator([
            SELECT Id, Inner_Chat_Session__c, CreatedDate
            FROM Inner_Chat_Message__c
            WHERE CreatedDate < :cutoffDateTime
            ORDER BY CreatedDate ASC
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<Inner_Chat_Message__c> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        
        try {
            // Calculate cutoff date (1 year ago)
            Date cutoffDate = Date.today().addDays(-RETENTION_DAYS);
            DateTime cutoffDateTime = DateTime.newInstance(cutoffDate.year(), cutoffDate.month(), cutoffDate.day(), 0, 0, 0);
            
            // Collect session IDs to check for archive chunks
            Set<Id> sessionIds = new Set<Id>();
            List<Id> messageIds = new List<Id>();
            for (Inner_Chat_Message__c msg : scope) {
                messageIds.add(msg.Id);
                if (msg.Inner_Chat_Session__c != null) {
                    sessionIds.add(msg.Inner_Chat_Session__c);
                }
            }
            
            // Delete ContentDocumentLinks first (if any)
            List<ContentDocumentLink> cdls = [
                SELECT Id, ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :messageIds
            ];
            
            if (!cdls.isEmpty()) {
                // Get unique ContentDocumentIds
                Set<Id> contentDocIds = new Set<Id>();
                for (ContentDocumentLink cdl : cdls) {
                    contentDocIds.add(cdl.ContentDocumentId);
                }
                
                // Delete ContentDocumentLinks
                delete cdls;
                
                // Delete ContentVersions and ContentDocuments
                List<ContentVersion> cvs = [
                    SELECT Id, ContentDocumentId
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :contentDocIds
                ];
                
                if (!cvs.isEmpty()) {
                    Set<Id> docIdsToDelete = new Set<Id>();
                    for (ContentVersion cv : cvs) {
                        docIdsToDelete.add(cv.ContentDocumentId);
                    }
                    
                    List<ContentDocument> docsToDelete = [
                        SELECT Id
                        FROM ContentDocument
                        WHERE Id IN :docIdsToDelete
                    ];
                    
                    if (!docsToDelete.isEmpty()) {
                        delete docsToDelete;
                    }
                }
            }
            
            // Delete active messages older than 1 year
            delete scope;
            
            totalProcessed += scope.size();
            totalDeleted += scope.size();
            
            // Delete archive chunks older than 1 year (based on Last_Message_Date__c)
            if (!sessionIds.isEmpty()) {
                List<Inner_Chat_Message_Archive__c> oldArchives = [
                    SELECT Id, Inner_Chat_Session__c, Last_Message_Date__c
                    FROM Inner_Chat_Message_Archive__c
                    WHERE Inner_Chat_Session__c IN :sessionIds
                      AND Last_Message_Date__c < :cutoffDateTime
                ];
                
                if (!oldArchives.isEmpty()) {
                    // Group by session to update metadata
                    Map<Id, List<Inner_Chat_Message_Archive__c>> archivesBySession = new Map<Id, List<Inner_Chat_Message_Archive__c>>();
                    for (Inner_Chat_Message_Archive__c archive : oldArchives) {
                        if (!archivesBySession.containsKey(archive.Inner_Chat_Session__c)) {
                            archivesBySession.put(archive.Inner_Chat_Session__c, new List<Inner_Chat_Message_Archive__c>());
                        }
                        archivesBySession.get(archive.Inner_Chat_Session__c).add(archive);
                    }
                    
                    // Delete archive chunks
                    delete oldArchives;
                    totalArchiveChunksDeleted += oldArchives.size();
                    
                    // Update session metadata for affected sessions
                    List<Inner_Chat_Session__c> sessionsToUpdate = new List<Inner_Chat_Session__c>();
                    for (Id sessionId : archivesBySession.keySet()) {
                        // Recalculate archived message count
                        Integer archivedCount = 0;
                        List<Inner_Chat_Message_Archive__c> remainingArchives = [
                            SELECT Message_Count__c
                            FROM Inner_Chat_Message_Archive__c
                            WHERE Inner_Chat_Session__c = :sessionId
                        ];
                        for (Inner_Chat_Message_Archive__c archive : remainingArchives) {
                            archivedCount += Integer.valueOf(archive.Message_Count__c);
                        }
                        
                        sessionsToUpdate.add(new Inner_Chat_Session__c(
                            Id = sessionId,
                            Archived_Message_Count__c = archivedCount
                        ));
                    }
                    
                    if (!sessionsToUpdate.isEmpty()) {
                        update sessionsToUpdate;
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug('Error deleting messages/archives in batch: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // Continue processing even if one batch fails
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        // Log completion
        System.debug('ChatMessageCleanupBatch completed.');
        System.debug('Total active messages processed: ' + totalProcessed);
        System.debug('Total active messages deleted: ' + totalDeleted);
        System.debug('Total archive chunks deleted: ' + totalArchiveChunksDeleted);
        
        // Also process archive chunks from sessions that don't have active messages older than 1 year
        // This handles cases where all messages were already archived
        try {
            Date cutoffDate = Date.today().addDays(-RETENTION_DAYS);
            DateTime cutoffDateTime = DateTime.newInstance(cutoffDate.year(), cutoffDate.month(), cutoffDate.day(), 0, 0, 0);
            
            List<Inner_Chat_Message_Archive__c> remainingOldArchives = [
                SELECT Id, Inner_Chat_Session__c, Last_Message_Date__c, Message_Count__c
                FROM Inner_Chat_Message_Archive__c
                WHERE Last_Message_Date__c < :cutoffDateTime
                LIMIT 1000
            ];
            
            if (!remainingOldArchives.isEmpty()) {
                // Group by session
                Map<Id, List<Inner_Chat_Message_Archive__c>> archivesBySession = new Map<Id, List<Inner_Chat_Message_Archive__c>>();
                for (Inner_Chat_Message_Archive__c archive : remainingOldArchives) {
                    if (!archivesBySession.containsKey(archive.Inner_Chat_Session__c)) {
                        archivesBySession.put(archive.Inner_Chat_Session__c, new List<Inner_Chat_Message_Archive__c>());
                    }
                    archivesBySession.get(archive.Inner_Chat_Session__c).add(archive);
                }
                
                // Delete archive chunks
                delete remainingOldArchives;
                totalArchiveChunksDeleted += remainingOldArchives.size();
                
                // Update session metadata
                List<Inner_Chat_Session__c> sessionsToUpdate = new List<Inner_Chat_Session__c>();
                for (Id sessionId : archivesBySession.keySet()) {
                    Integer archivedCount = 0;
                    List<Inner_Chat_Message_Archive__c> remainingArchives = [
                        SELECT Message_Count__c
                        FROM Inner_Chat_Message_Archive__c
                        WHERE Inner_Chat_Session__c = :sessionId
                    ];
                    for (Inner_Chat_Message_Archive__c archive : remainingArchives) {
                        archivedCount += Integer.valueOf(archive.Message_Count__c);
                    }
                    
                    sessionsToUpdate.add(new Inner_Chat_Session__c(
                        Id = sessionId,
                        Archived_Message_Count__c = archivedCount
                    ));
                }
                
                if (!sessionsToUpdate.isEmpty()) {
                    update sessionsToUpdate;
                }
            }
        } catch (Exception e) {
            System.debug('Error processing remaining archive chunks in finish: ' + e.getMessage());
        }
        
        // Optional: Send notification email or create a log record
        // You can add custom notification logic here if needed
    }
}