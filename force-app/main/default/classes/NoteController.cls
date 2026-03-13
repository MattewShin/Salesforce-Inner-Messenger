/**
 * ===========================================================================================
 * @description       : Controller for Note functionality (non-real-time messaging)
 * @author            : CNXK
 * @last modified on  : 2025-03-06
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-03-06   CNXK                Initial version - Note CRUD operations, read/unread status, important flag, delete functionality
 */
public with sharing class NoteController {
    
    /**
     * Wrapper class for Note display
     */
    public class NoteWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String subject;
        @AuraEnabled public String content;
        @AuraEnabled public Id senderId;
        @AuraEnabled public String senderName;
        @AuraEnabled public Id recipientId;
        @AuraEnabled public String recipientName;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Boolean isRead;
        @AuraEnabled public DateTime readAt;
        @AuraEnabled public Boolean isImportant;
        @AuraEnabled public Boolean senderDeleted;
        @AuraEnabled public Boolean recipientDeleted;
        @AuraEnabled public AttachmentWrapper attachment;
        
        public NoteWrapper(Inner_Note__c note) {
            this.id = note.Id;
            this.subject = note.Subject__c;
            this.content = note.Content__c;
            this.senderId = note.Sender__c;
            this.senderName = (note.Sender__c != null && note.Sender__r != null) ? note.Sender__r.Name : '(삭제된 사용자)';
            this.recipientId = note.Recipient__c;
            this.recipientName = (note.Recipient__c != null && note.Recipient__r != null) ? note.Recipient__r.Name : '(삭제된 사용자)';
            this.createdDate = note.CreatedDate;
            this.isRead = (note.Is_Read__c == true);
            this.readAt = note.Read_At__c;
            this.isImportant = (note.Is_Important__c == true);
            this.senderDeleted = (note.Sender_Deleted__c == true);
            this.recipientDeleted = (note.Recipient_Deleted__c == true);
            
            // Attachment handling
            if (!note.ContentDocumentLinks.isEmpty()) {
                this.attachment = new AttachmentWrapper(note.ContentDocumentLinks[0]);
            }
        }
    }
    
    /**
     * Wrapper for note attachment information
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
     * Get received notes (inbox)
     * @param unreadOnly If true, returns only unread notes
     * @return List of received notes
     */
    @AuraEnabled
    public static List<NoteWrapper> getReceivedNotes(Boolean unreadOnly) {
        Id currentUserId = UserInfo.getUserId();
        
        String query = 'SELECT Id, Subject__c, Content__c, Sender__c, Sender__r.Name, ' +
                       'Recipient__c, Recipient__r.Name, CreatedDate, Is_Read__c, Read_At__c, ' +
                       'Is_Important__c, Sender_Deleted__c, Recipient_Deleted__c, ' +
                       '(SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension, ' +
                       'ContentDocument.LatestPublishedVersionId FROM ContentDocumentLinks LIMIT 1) ' +
                       'FROM Inner_Note__c ' +
                       'WHERE Recipient__c = :currentUserId ' +
                       'AND Recipient_Deleted__c = false ';
        
        if (unreadOnly == true) {
            query += 'AND Is_Read__c = false ';
        }
        
        query += 'ORDER BY Is_Important__c DESC, Is_Read__c ASC, CreatedDate DESC';
        
        List<Inner_Note__c> notes = Database.query(query);
        
        List<NoteWrapper> results = new List<NoteWrapper>();
        for (Inner_Note__c note : notes) {
            results.add(new NoteWrapper(note));
        }
        
        return results;
    }
    
    /**
     * Get sent notes (sent box)
     * @return List of sent notes
     */
    @AuraEnabled
    public static List<NoteWrapper> getSentNotes() {
        Id currentUserId = UserInfo.getUserId();
        
        List<Inner_Note__c> notes = [
            SELECT Id, Subject__c, Content__c, Sender__c, Sender__r.Name,
                   Recipient__c, Recipient__r.Name, CreatedDate, Is_Read__c, Read_At__c,
                   Is_Important__c, Sender_Deleted__c, Recipient_Deleted__c,
                   (SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension,
                    ContentDocument.LatestPublishedVersionId FROM ContentDocumentLinks LIMIT 1)
            FROM Inner_Note__c
            WHERE Sender__c = :currentUserId
              AND Sender_Deleted__c = false
            ORDER BY CreatedDate DESC
        ];
        
        List<NoteWrapper> results = new List<NoteWrapper>();
        for (Inner_Note__c note : notes) {
            results.add(new NoteWrapper(note));
        }
        
        return results;
    }
    
    /**
     * Send a new note
     * @param recipientId Recipient user ID
     * @param subject Note subject
     * @param content Note content
     * @param attachmentId ContentDocument ID (optional)
     * @return Created note ID
     */
    @AuraEnabled
    public static Id sendNote(Id recipientId, String subject, String content, Id attachmentId) {
        if (recipientId == null) {
            throw new AuraHandledException('Recipient is required.');
        }
        if (String.isBlank(subject)) {
            throw new AuraHandledException('Subject is required.');
        }
        if (recipientId == UserInfo.getUserId()) {
            throw new AuraHandledException('You cannot send a note to yourself.');
        }
        
        try {
            Id currentUserId = UserInfo.getUserId();
            
            // Create note with recipient as owner (so they can access it)
            Inner_Note__c note = new Inner_Note__c(
                Sender__c = currentUserId,
                Recipient__c = recipientId,
                Subject__c = subject.trim(),
                Content__c = (content != null) ? content.trim() : null,
                Is_Read__c = false,
                OwnerId = recipientId // Set owner to recipient so they can access the record
            );
            
            insert note;
            
            // Share the record with sender so they can see it in "Sent" folder
            // Using Apex Managed Sharing
            Inner_Note__Share noteShare = new Inner_Note__Share();
            noteShare.ParentId = note.Id;
            noteShare.UserOrGroupId = currentUserId;
            noteShare.AccessLevel = 'Read'; // Sender can only read, not edit
            noteShare.RowCause = Schema.Inner_Note__Share.RowCause.Manual;
            
            try {
                insert noteShare;
            } catch (Exception shareError) {
                // If sharing fails, log but don't fail the note creation
                System.debug('Failed to share note with sender: ' + shareError.getMessage());
            }
            
            // Link attachment if provided
            if (attachmentId != null) {
                try {
                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.ContentDocumentId = attachmentId;
                    cdl.LinkedEntityId = note.Id;
                    cdl.ShareType = 'V'; // Viewer permission
                    insert cdl;
                } catch (Exception e) {
                    // If linking fails, note is still created
                    System.debug('Failed to link attachment: ' + e.getMessage());
                }
            }
            
            return note.Id;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to send note: ' + e.getMessage());
        }
    }
    
    /**
     * Mark note as read
     * @param noteId Note ID to mark as read
     */
    @AuraEnabled
    public static void markAsRead(Id noteId) {
        if (noteId == null) return;
        
        Id currentUserId = UserInfo.getUserId();
        
        // Verify user is the recipient
        List<Inner_Note__c> notes = [
            SELECT Id, Is_Read__c, Read_At__c
            FROM Inner_Note__c
            WHERE Id = :noteId
              AND Recipient__c = :currentUserId
            LIMIT 1
        ];
        
        if (notes.isEmpty()) {
            throw new AuraHandledException('Note not found or you are not the recipient.');
        }
        
        Inner_Note__c note = notes[0];
        if (note.Is_Read__c == false) {
            note.Is_Read__c = true;
            note.Read_At__c = System.now();
            update note;
        }
    }
    
    /**
     * Toggle important flag
     * @param noteId Note ID
     * @param isImportant Important flag value
     */
    @AuraEnabled
    public static void toggleImportant(Id noteId, Boolean isImportant) {
        if (noteId == null) return;
        
        Id currentUserId = UserInfo.getUserId();
        
        // Verify user is the recipient (only recipient can mark as important)
        List<Inner_Note__c> notes = [
            SELECT Id, Is_Important__c
            FROM Inner_Note__c
            WHERE Id = :noteId
              AND Recipient__c = :currentUserId
            LIMIT 1
        ];
        
        if (notes.isEmpty()) {
            throw new AuraHandledException('Note not found or you are not the recipient.');
        }
        
        Inner_Note__c note = notes[0];
        note.Is_Important__c = (isImportant == true);
        update note;
    }
    
    /**
     * Delete note (soft delete)
     * @param noteId Note ID to delete
     * @param type 'received' or 'sent'
     */
    @AuraEnabled
    public static void deleteNote(Id noteId, String type) {
        if (noteId == null || String.isBlank(type)) {
            throw new AuraHandledException('Note ID and type are required.');
        }
        
        Id currentUserId = UserInfo.getUserId();
        
        List<Inner_Note__c> notes = [
            SELECT Id, Sender__c, Recipient__c, Sender_Deleted__c, Recipient_Deleted__c
            FROM Inner_Note__c
            WHERE Id = :noteId
            LIMIT 1
        ];
        
        if (notes.isEmpty()) {
            throw new AuraHandledException('Note not found.');
        }
        
        Inner_Note__c note = notes[0];
        
        if (type == 'received') {
            if (note.Recipient__c != currentUserId) {
                throw new AuraHandledException('You can only delete notes you received.');
            }
            note.Recipient_Deleted__c = true;
        } else if (type == 'sent') {
            if (note.Sender__c != currentUserId) {
                throw new AuraHandledException('You can only delete notes you sent.');
            }
            note.Sender_Deleted__c = true;
        } else {
            throw new AuraHandledException('Invalid type. Use "received" or "sent".');
        }
        
        update note;
        
        // Hard delete if both sides deleted
        if (note.Sender_Deleted__c == true && note.Recipient_Deleted__c == true) {
            // Delete ContentDocumentLinks first
            List<ContentDocumentLink> cdls = [
                SELECT Id, ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :noteId
            ];
            if (!cdls.isEmpty()) {
                Set<Id> contentDocIds = new Set<Id>();
                for (ContentDocumentLink cdl : cdls) {
                    contentDocIds.add(cdl.ContentDocumentId);
                }
                
                delete cdls;
                
                // Delete ContentDocuments
                List<ContentDocument> docs = [
                    SELECT Id
                    FROM ContentDocument
                    WHERE Id IN :contentDocIds
                ];
                if (!docs.isEmpty()) {
                    delete docs;
                }
            }
            
            delete note;
        }
    }
    
    /**
     * Get unread note count
     * @return Number of unread notes
     */
    @AuraEnabled
    public static Integer getUnreadCount() {
        Id currentUserId = UserInfo.getUserId();
        
        Integer count = [
            SELECT COUNT()
            FROM Inner_Note__c
            WHERE Recipient__c = :currentUserId
              AND Is_Read__c = false
              AND Recipient_Deleted__c = false
        ];
        
        return count;
    }
    
    /**
     * Search users for note recipient selection
     * @param searchTerm Search term
     * @return List of users
     */
    @AuraEnabled(cacheable=true)
    public static List<User> searchUsers(String searchTerm) {
        String key = '%' + searchTerm + '%';
        return [
            SELECT Id, Name, SmallPhotoUrl
            FROM User
            WHERE Name LIKE :key
              AND IsActive = true
              AND Id != :UserInfo.getUserId() // Exclude self
            LIMIT 10
        ];
    }
    
    /**
     * Upload image from clipboard (Base64) for note attachment
     * @param base64Data Base64 encoded image data
     * @param fileName File name
     * @return ContentDocumentId
     */
    @AuraEnabled
    public static Id uploadImageFromBase64(String base64Data, String fileName) {
        try {
            // Remove data URL prefix if present
            String base64Content = base64Data;
            if (base64Data.contains(',')) {
                base64Content = base64Data.substring(base64Data.indexOf(',') + 1);
            }

            // Decode base64 to Blob
            Blob fileBlob = EncodingUtil.base64Decode(base64Content);

            // Determine file extension
            String fileExtension = 'png';
            if (fileName != null && fileName.contains('.')) {
                fileExtension = fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase();
            } else if (base64Data.startsWith('data:image/')) {
                String mimeType = base64Data.substring(5, base64Data.indexOf(';'));
                if (mimeType.contains('jpeg')) fileExtension = 'jpg';
                else if (mimeType.contains('gif')) fileExtension = 'gif';
                else if (mimeType.contains('webp')) fileExtension = 'webp';
                else if (mimeType.contains('bmp')) fileExtension = 'bmp';
            }

            // Generate unique filename
            String timestamp = String.valueOf(System.now().getTime());
            String userName = UserInfo.getName().replace(' ', '_');
            String uniqueFileName = 'Note_Image_' + userName + '_' + timestamp + '.' + fileExtension;

            // Create ContentVersion (without FirstPublishLocationId for notes)
            ContentVersion cv = new ContentVersion();
            cv.Title = uniqueFileName;
            cv.PathOnClient = uniqueFileName;
            cv.VersionData = fileBlob;
            insert cv;

            // Get ContentDocumentId
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
            return cv.ContentDocumentId;

        } catch (Exception e) {
            throw new AuraHandledException('Image upload failed: ' + e.getMessage());
        }
    }

    /**
     * Get note detail by ID
     * @param noteId Note ID
     * @return Note wrapper
     */
    @AuraEnabled(cacheable=true)
    public static NoteWrapper getNoteDetail(Id noteId) {
        if (noteId == null) return null;
        
        Id currentUserId = UserInfo.getUserId();
        
        List<Inner_Note__c> notes = [
            SELECT Id, Subject__c, Content__c, Sender__c, Sender__r.Name,
                   Recipient__c, Recipient__r.Name, CreatedDate, Is_Read__c, Read_At__c,
                   Is_Important__c, Sender_Deleted__c, Recipient_Deleted__c,
                   (SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension,
                    ContentDocument.LatestPublishedVersionId FROM ContentDocumentLinks LIMIT 1)
            FROM Inner_Note__c
            WHERE Id = :noteId
              AND (Sender__c = :currentUserId OR Recipient__c = :currentUserId)
              AND ((Sender__c = :currentUserId AND Sender_Deleted__c = false) OR
                   (Recipient__c = :currentUserId AND Recipient_Deleted__c = false))
            LIMIT 1
        ];
        
        if (notes.isEmpty()) {
            return null;
        }
        
        return new NoteWrapper(notes[0]);
    }
}