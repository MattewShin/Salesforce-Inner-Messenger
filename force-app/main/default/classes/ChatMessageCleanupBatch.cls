/**
 * ===========================================================================================
 * @description       : Batch class to delete chat messages older than 1 year
 * @author            : CNXK
 * @last modified on  : 2025-03-06
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-03-06   CNXK                Initial version - Batch job to delete messages older than 1 year
 */
public class ChatMessageCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    // Retention period in days (1 year = 365 days)
    private static final Integer RETENTION_DAYS = 365;
    
    // Track statistics
    private Integer totalProcessed = 0;
    private Integer totalDeleted = 0;
    
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
            // Delete messages in batch
            List<Id> messageIds = new List<Id>();
            for (Inner_Chat_Message__c msg : scope) {
                messageIds.add(msg.Id);
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
            
            // Delete messages
            delete scope;
            
            totalProcessed += scope.size();
            totalDeleted += scope.size();
            
        } catch (Exception e) {
            System.debug('Error deleting messages in batch: ' + e.getMessage());
            // Continue processing even if one batch fails
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        // Log completion
        System.debug('ChatMessageCleanupBatch completed. Total processed: ' + totalProcessed + ', Total deleted: ' + totalDeleted);
        
        // Optional: Send notification email or create a log record
        // You can add custom notification logic here if needed
    }
}
