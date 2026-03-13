import { LightningElement, track, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getReceivedNotes from '@salesforce/apex/NoteController.getReceivedNotes';
import getSentNotes from '@salesforce/apex/NoteController.getSentNotes';
import sendNote from '@salesforce/apex/NoteController.sendNote';
import markAsRead from '@salesforce/apex/NoteController.markAsRead';
import toggleImportant from '@salesforce/apex/NoteController.toggleImportant';
import deleteNote from '@salesforce/apex/NoteController.deleteNote';
import getUnreadCount from '@salesforce/apex/NoteController.getUnreadCount';
import searchUsers from '@salesforce/apex/NoteController.searchUsers';
import getNoteDetail from '@salesforce/apex/NoteController.getNoteDetail';
import uploadImageFromBase64 from '@salesforce/apex/NoteController.uploadImageFromBase64';
import USER_ID from '@salesforce/user/Id';

export default class UtilityNote extends NavigationMixin(LightningElement) {
    @api height;
    @api width;

    @track receivedNotes = [];
    @track sentNotes = [];
    @track currentNotes = [];
    @track noteItemClasses = {}; // Map of noteId -> class string
    @track noteUnreadIndicators = {}; // Map of noteId -> boolean
    
    currentView = 'received'; // 'received' or 'sent'
    selectedNoteId = null;
    selectedNote = null;
    
    // Compose note state
    isComposeModalOpen = false;
    composeRecipientId = null;
    composeRecipientName = '';
    composeSubject = '';
    composeContent = '';
    composeAttachmentId = null;
    
    // User search for compose
    @track userSearchResults = [];
    isUserSearching = false;
    
    isLoading = false;
    isLoadingNotes = false;
    
    // Unread count badge
    unreadCount = 0;
    previousUnreadCount = 0; // Track previous count for notifications
    unreadCountTimer = null;
    
    // Notification settings
    notificationPermission = 'default'; // 'default', 'granted', 'denied'

    get isReceivedView() {
        return this.currentView === 'received';
    }

    get isSentView() {
        return this.currentView === 'sent';
    }

    get isNotesEmpty() {
        return this.currentNotes.length === 0;
    }

    get hasSelectedNote() {
        return this.selectedNote != null;
    }

    get badgeLabel() {
        return this.unreadCount > 0 ? `쪽지 (${this.unreadCount})` : '쪽지';
    }

    get hasUnreadCount() {
        return this.unreadCount > 0;
    }


    get importantIconName() {
        return this.selectedNote && this.selectedNote.isImportant ? 'utility:favorite' : 'utility:favorite_border';
    }

    get isSendButtonDisabled() {
        return this.isLoading || !this.composeRecipientId || !this.composeSubject;
    }

    get receivedTabClass() {
        return this.currentView === 'received' ? 'active' : '';
    }

    get sentTabClass() {
        return this.currentView === 'sent' ? 'active' : '';
    }

    get unreadFilterChecked() {
        return false;
    }


    get hasReadAt() {
        return this.selectedNote && this.selectedNote.isRead && this.selectedNote.readAt;
    }


    handleClearRecipient() {
        this.composeRecipientId = null;
        this.composeRecipientName = '';
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    connectedCallback() {
        this.loadNotes();
        this.loadUnreadCount();
        this.startUnreadCountPolling();
        this.requestNotificationPermission();
    }
    
    async requestNotificationPermission() {
        if ('Notification' in window) {
            try {
                const permission = await Notification.requestPermission();
                this.notificationPermission = permission;
                console.log('Notification permission:', permission);
            } catch (error) {
                console.error('Error requesting notification permission:', error);
            }
        }
    }
    
    showBrowserNotification(title, body, noteId) {
        if (this.notificationPermission === 'granted' && 'Notification' in window) {
            try {
                const notification = new Notification(title, {
                    body: body,
                    icon: '/favicon.ico',
                    badge: '/favicon.ico',
                    tag: `note-${noteId}`, // Prevent duplicate notifications
                    requireInteraction: false
                });
                
                notification.onclick = () => {
                    window.focus();
                    notification.close();
                    // Switch to received view and select the note
                    if (this.currentView !== 'received') {
                        this.currentView = 'received';
                        this.loadNotes().then(() => {
                            // Select the note after loading
                            setTimeout(() => {
                                const noteElement = this.template.querySelector(`[data-id="${noteId}"]`);
                                if (noteElement) {
                                    noteElement.click();
                                }
                            }, 500);
                        });
                    }
                };
                
                // Auto close after 5 seconds
                setTimeout(() => {
                    notification.close();
                }, 5000);
            } catch (error) {
                console.error('Error showing browser notification:', error);
            }
        }
    }
    
    showToast(title, message, variant = 'info') {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable'
        });
        this.dispatchEvent(evt);
    }
    
    updateUtilityBarBadge() {
        if (this.utilityBarApi && this.unreadCount > 0) {
            try {
                this.utilityBarApi.setBadge({
                    value: this.unreadCount,
                    label: this.unreadCount > 99 ? '99+' : String(this.unreadCount)
                });
            } catch (error) {
                console.error('Error updating Utility Bar badge:', error);
            }
        } else if (this.utilityBarApi && this.unreadCount === 0) {
            try {
                this.utilityBarApi.clearBadge();
            } catch (error) {
                console.error('Error clearing Utility Bar badge:', error);
            }
        }
    }

    disconnectedCallback() {
        if (this.unreadCountTimer) {
            clearInterval(this.unreadCountTimer);
        }
    }

    // --- Data Loading ---

    async loadNotes() {
        this.isLoadingNotes = true;
        try {
            let notes = [];
            if (this.currentView === 'received') {
                notes = await getReceivedNotes({ unreadOnly: false });
                this.receivedNotes = notes;
            } else {
                notes = await getSentNotes();
                this.sentNotes = notes;
            }
            
            // Create new array with computed properties
            this.currentNotes = notes.map(note => {
                let classStr = 'note-item';
                if (this.selectedNoteId === note.id) {
                    classStr += ' selected';
                }
                if (!note.isRead && this.currentView === 'received') {
                    classStr += ' unread';
                }
                
                return {
                    ...note,
                    itemClass: classStr,
                    showUnreadIndicator: !note.isRead && this.isReceivedView
                };
            });
            
            // Also update the original arrays for consistency
            if (this.currentView === 'received') {
                this.receivedNotes = this.currentNotes;
            } else {
                this.sentNotes = this.currentNotes;
            }
        } catch (error) {
            console.error('Error loading notes', error);
            this.currentNotes = [];
        } finally {
            this.isLoadingNotes = false;
        }
    }

    updateNoteItemClasses() {
        // Recreate currentNotes with updated classes
        this.currentNotes = this.currentNotes.map(note => {
            let classStr = 'note-item';
            if (this.selectedNoteId === note.id) {
                classStr += ' selected';
            }
            if (!note.isRead && this.currentView === 'received') {
                classStr += ' unread';
            }
            
            return {
                ...note,
                itemClass: classStr,
                showUnreadIndicator: !note.isRead && this.isReceivedView
            };
        });
        
        // Update the original arrays
        if (this.currentView === 'received') {
            this.receivedNotes = this.currentNotes;
        } else {
            this.sentNotes = this.currentNotes;
        }
    }
    

    async loadUnreadCount() {
        try {
            const newCount = await getUnreadCount();
            const previousCount = this.unreadCount;
            this.unreadCount = newCount;
            
            // Check if new messages arrived
            if (newCount > previousCount && previousCount > 0) {
                const newMessageCount = newCount - previousCount;
                // Show notification for new messages
                this.showBrowserNotification(
                    '새 쪽지',
                    `읽지 않은 쪽지 ${newMessageCount}개가 있습니다.`,
                    null
                );
                this.showToast('새 쪽지', `읽지 않은 쪽지 ${newMessageCount}개가 있습니다.`, 'info');
            } else if (newCount > 0 && previousCount === 0) {
                // First unread message
                this.showBrowserNotification(
                    '새 쪽지',
                    `읽지 않은 쪽지 ${newCount}개가 있습니다.`,
                    null
                );
            }
            
        } catch (error) {
            console.error('Error loading unread count', error);
        }
    }

    startUnreadCountPolling() {
        // Poll every 30 seconds for unread count update
        this.unreadCountTimer = setInterval(() => {
            this.loadUnreadCount();
        }, 30000);
    }

    // --- View Navigation ---

    handleViewChange(event) {
        const view = event.currentTarget.dataset.view;
        if (view === this.currentView) return;
        
        this.currentView = view;
        this.selectedNoteId = null;
        this.selectedNote = null;
        this.noteItemClasses = {};
        this.loadNotes();
    }

    // --- Note Selection ---

    async handleNoteSelect(event) {
        const noteId = event.currentTarget.dataset.id;
        if (!noteId) {
            console.error('No note ID found in event');
            return;
        }

        console.log('Selecting note:', noteId);

        this.selectedNoteId = noteId;
        this.isLoading = true;

        try {
            const note = await getNoteDetail({ noteId });
            console.log('Note detail loaded:', note);
            
            if (!note) {
                console.error('Note detail is null for ID:', noteId);
                // eslint-disable-next-line no-alert
                alert('쪽지를 찾을 수 없습니다.');
                this.selectedNoteId = null;
                return;
            }

            this.selectedNote = note;
            this.updateNoteItemClasses();

            // Mark as read if viewing received note
            if (this.currentView === 'received' && note && !note.isRead) {
                try {
                    await markAsRead({ noteId });
                    console.log('Note marked as read:', noteId);
                    
                    // Update selected note's read status immediately
                    this.selectedNote.isRead = true;
                    this.selectedNote.readAt = new Date();
                    
                    // Decrease unread count immediately (optimistic update)
                    if (this.unreadCount > 0) {
                        this.unreadCount = this.unreadCount - 1;
                    }
                    
                    // Refresh unread count from server to ensure accuracy
                    await this.loadUnreadCount();
                    
                    // Refresh notes list to update read status, but preserve selected note
                    const currentSelectedNote = this.selectedNote;
                    await this.loadNotes();
                    // Restore selected note after reload
                    this.selectedNote = currentSelectedNote;
                    this.selectedNoteId = noteId;
                    this.updateNoteItemClasses();
                } catch (markError) {
                    console.error('Error marking as read:', markError);
                    // Don't fail the selection if mark as read fails
                }
            }
        } catch (error) {
            console.error('Error loading note detail', error);
            console.error('Error details:', JSON.stringify(error, null, 2));
            const msg = error?.body?.message || error?.message || '쪽지를 불러오는 중 오류가 발생했습니다.';
            // eslint-disable-next-line no-alert
            alert(msg);
            this.selectedNoteId = null;
            this.selectedNote = null;
        } finally {
            this.isLoading = false;
        }
    }

    // --- Compose Note ---

    openComposeModal() {
        this.isComposeModalOpen = true;
        this.composeRecipientId = null;
        this.composeRecipientName = '';
        this.composeSubject = '';
        this.composeContent = '';
        this.composeAttachmentId = null;
        this.userSearchResults = [];
    }

    closeComposeModal() {
        this.isComposeModalOpen = false;
        this.composeRecipientId = null;
        this.composeRecipientName = '';
        this.composeSubject = '';
        this.composeContent = '';
        this.composeAttachmentId = null;
        this.userSearchResults = [];
    }

    handleRecipientSearch(event) {
        const term = event.target.value;
        if (term && term.length > 1) {
            this.isUserSearching = true;
            searchUsers({ searchTerm: term })
                .then(result => {
                    this.userSearchResults = result || [];
                })
                .catch(err => {
                    console.error('User search error', err);
                    this.userSearchResults = [];
                })
                .finally(() => {
                    this.isUserSearching = false;
                });
        } else {
            this.userSearchResults = [];
        }
    }

    handleRecipientSelect(event) {
        const userId = event.currentTarget.dataset.id;
        const userName = event.currentTarget.dataset.name;
        this.composeRecipientId = userId;
        this.composeRecipientName = userName;
        this.userSearchResults = [];
    }

    handleSubjectChange(event) {
        this.composeSubject = event.target.value;
    }

    handleContentChange(event) {
        this.composeContent = event.target.value;
    }

    handlePaste(event) {
        // Clipboard image paste support
        if (this.isLoading) return;

        try {
            const clipboardData = event.clipboardData || window.clipboardData;
            if (!clipboardData) return;

            const items = clipboardData.items;
            if (!items) return;

            for (let i = 0; i < items.length; i++) {
                const item = items[i];
                if (item.type.indexOf('image') !== -1) {
                    event.preventDefault();
                    
                    const file = item.getAsFile();
                    if (!file) continue;

                    const reader = new FileReader();
                    reader.onload = async (e) => {
                        try {
                            const base64Data = e.target.result;
                            const fileName = file.name || 'screenshot.png';

                            this.isLoading = true;

                            const contentDocumentId = await uploadImageFromBase64({
                                base64Data: base64Data,
                                fileName: fileName
                            });

                            this.composeAttachmentId = contentDocumentId;
                            this.isLoading = false;
                        } catch (error) {
                            this.isLoading = false;
                            console.error('Image paste upload error', error);
                            // eslint-disable-next-line no-alert
                            alert('이미지 업로드 중 오류가 발생했습니다.');
                        }
                    };

                    reader.readAsDataURL(file);
                    break;
                }
            }
        } catch (error) {
            console.error('Paste event error', error);
        }
    }

    async handleSendNote() {
        if (!this.composeRecipientId) {
            // eslint-disable-next-line no-alert
            alert('받는 사람을 선택해주세요.');
            return;
        }
        if (!this.composeSubject || !this.composeSubject.trim()) {
            // eslint-disable-next-line no-alert
            alert('제목을 입력해주세요.');
            return;
        }

        this.isLoading = true;
        try {
            const noteId = await sendNote({
                recipientId: this.composeRecipientId,
                subject: this.composeSubject,
                content: this.composeContent,
                attachmentId: this.composeAttachmentId
            });

            console.log('Note sent successfully, ID:', noteId);

            // Clear compose form
            this.composeRecipientId = null;
            this.composeRecipientName = '';
            this.composeSubject = '';
            this.composeContent = '';
            this.composeAttachmentId = null;
            this.isComposeModalOpen = false;

            // Switch to sent view immediately to show the sent note
            this.currentView = 'sent';
            
            // Clear selected note
            this.selectedNoteId = null;
            this.selectedNote = null;
            
            // Force refresh sent notes immediately - wait a bit for database to commit
            await new Promise(resolve => setTimeout(resolve, 100)); // Small delay for DB commit
            await this.loadNotes();
            
            // Reload unread count
            await this.loadUnreadCount();
            
            console.log('Notes reloaded, sent notes count:', this.sentNotes.length);
            
            // Show success message
            this.showToast('쪽지 전송 완료', '쪽지가 성공적으로 전송되었습니다.', 'success');
        } catch (error) {
            console.error('Send note error', error);
            console.error('Error details:', JSON.stringify(error, null, 2));
            const msg = error?.body?.message || error?.message || '쪽지 전송 중 오류가 발생했습니다.';
            this.showToast('쪽지 전송 실패', msg, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // --- Note Actions ---

    async handleToggleImportant() {
        if (!this.selectedNote) return;

        const newValue = !this.selectedNote.isImportant;
        this.isLoading = true;

        try {
            await toggleImportant({
                noteId: this.selectedNoteId,
                isImportant: newValue
            });

            this.selectedNote.isImportant = newValue;
            // Refresh notes list
            this.loadNotes();
        } catch (error) {
            console.error('Toggle important error', error);
            // eslint-disable-next-line no-alert
            alert('중요 표시 변경 중 오류가 발생했습니다.');
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeleteNote() {
        if (!this.selectedNote) return;

        const confirmMsg = this.currentView === 'received' 
            ? '받은 쪽지를 삭제하시겠습니까?'
            : '보낸 쪽지를 삭제하시겠습니까?';
        
        if (!window.confirm(confirmMsg)) return;

        this.isLoading = true;
        try {
            await deleteNote({
                noteId: this.selectedNoteId,
                type: this.currentView
            });

            this.selectedNoteId = null;
            this.selectedNote = null;
            this.loadNotes();
            this.loadUnreadCount();
        } catch (error) {
            console.error('Delete note error', error);
            const msg = error?.body?.message || error?.message || '쪽지 삭제 중 오류가 발생했습니다.';
            // eslint-disable-next-line no-alert
            alert(msg);
        } finally {
            this.isLoading = false;
        }
    }

    handlePreviewFile(event) {
        const docId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: docId
            }
        });
    }

    // --- Filter ---

    handleUnreadFilter(event) {
        const showUnreadOnly = event.target.checked;
        if (this.currentView === 'received') {
            this.loadReceivedNotesFiltered(showUnreadOnly);
        }
    }

    async loadReceivedNotesFiltered(unreadOnly) {
        this.isLoadingNotes = true;
        try {
            this.receivedNotes = await getReceivedNotes({ unreadOnly });
            this.currentNotes = this.receivedNotes;
            this.updateNoteItemClasses();
        } catch (error) {
            console.error('Error loading filtered notes', error);
        } finally {
            this.isLoadingNotes = false;
        }
    }
}