import { LightningElement, track, api } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { NavigationMixin } from 'lightning/navigation';
import getChatSessions from '@salesforce/apex/ChatController.getChatSessions';
import getChatSession from '@salesforce/apex/ChatController.getChatSession';
import getMessages from '@salesforce/apex/ChatController.getMessages';
import getMessagesPaged from '@salesforce/apex/ChatController.getMessagesPaged';
import sendMessage from '@salesforce/apex/ChatController.sendMessage';
import createOrGetChatSession from '@salesforce/apex/ChatController.createOrGetChatSession';
import searchUsers from '@salesforce/apex/ChatController.searchUsers';
import leaveChatSession from '@salesforce/apex/ChatController.leaveChatSession';
import deleteChatSession from '@salesforce/apex/ChatController.deleteChatSession';
import inviteParticipants from '@salesforce/apex/ChatController.inviteParticipants';
import renameChatSession from '@salesforce/apex/ChatController.renameChatSession';
import markSessionAsRead from '@salesforce/apex/ChatController.markSessionAsRead';
import setPinned from '@salesforce/apex/ChatController.setPinned';
import setMuted from '@salesforce/apex/ChatController.setMuted';
import getParticipants from '@salesforce/apex/ChatController.getParticipants';
import USER_ID from '@salesforce/user/Id';

export default class UtilityChat extends NavigationMixin(LightningElement) {
    @api height;
    @api width;

    @track sessions = [];

    @track messages = [];
    // Message pagination (infinite scroll)
    messagePageSize = 30;
    oldestCreatedDate = null;
    hasMoreMessages = true;
    isLoadingMoreMessages = false;
    // People Modal (shared) state
    @track peopleSearchResults = [];
    @track peopleSelectedUsers = []; // {id, name}

    currentSessionId;
    currentSessionName;
    currentSessionCreatedById;
    isRenameModalOpen = false;
    renameChatName = '';

    // Participants list modal
    isParticipantsModalOpen = false;
    isParticipantsLoading = false;
    @track participants = []; // [{ userId, userName, lastReadAt, isPinned, isMuted, isMe }]

    // Reply (Quote) state
    replyDraft = null; // { messageId, senderName, preview }

    // Read mark debounce (infinite scroll + optimize + reduce Apex calls)
    markReadTimer;

    isChatView = false;
    // People Modal (shared): create/invite
    isPeopleModalOpen = false;
    peopleModalMode = 'create'; // 'create' | 'invite'
    peopleModalStep = 1; // 1: User select, 2: Confirm
    messageInput = '';
    peopleChatName = '';
    isLoading = false;

    // Session flash notification (user receives message while away)
    @track sessionFlashMap = {}; // { [sessionId]: true }
    mutedSessionMap = {}; // { [sessionId15]: true }

    subscription = {};
    channelName = '/event/Inner_Chat_Notification__e';
    currentUserId = USER_ID;

    get isListView() {
        return !this.isChatView;
    }

    get isSessionsEmpty() {
        return this.sessions.length === 0;
    }

    connectedCallback() {
        this.handleSubscribe();
        this.writeActiveSessionToStorage();
        this.loadSessions();
    }

    disconnectedCallback() {
        this.handleUnsubscribe();
    }

    // --- Data Loading ---

    decorateSessions(rawSessions) {
        const mutedMap = {};
        (rawSessions || []).forEach(s => {
            const key = this.normalizeId(s.sessionId);
            if (s.isMuted) mutedMap[key] = true;
        });
        this.mutedSessionMap = mutedMap;
        this.writeMutedSessionsToStorage();

        return (rawSessions || []).map(s => ({
            ...s,
            cssClass: this.sessionFlashMap[this.normalizeId(s.sessionId)] ? 'session-item flashing' : 'session-item',
            pinIcon: s.isPinned ? 'utility:pinned' : 'utility:pin',
            muteIcon: s.isMuted ? 'utility:volume_off' : 'utility:volume_high'
        }));
    }

    refreshSessionClasses() {
        this.sessions = this.decorateSessions(this.sessions);
    }

    async loadSessions() {
        try {
            const data = await getChatSessions();
            this.sessions = this.decorateSessions(data);
        } catch (error) {
            console.error('Error loading sessions', error);
            this.sessions = [];
        }
    }

    normalizeId(id) {
        return (id || '').toString().substring(0, 15);
    }

    decorateMessages(result) {
        return (result || []).map(msg => {
            const isSystem = (msg.content || '').startsWith('[SYSTEM]');
            const rawContent = (msg.content || '').replace(/^\[SYSTEM\]\s*/, '');
            const systemLines = isSystem ? this.splitSystemMessage(rawContent) : null;
            const displayContent = isSystem ? '' : rawContent;
            // Kakaotalk read receipt: "Only show unread count if sent by others" (0 if none)
            const unreadByOthers = Number(msg.unreadByOthers || 0);
            const showUnreadCount = !isSystem && unreadByOthers > 0;
            const replyToId = msg.replyToId;
            const replyToSenderName = msg.replyToSenderName;
            const replyToPreview = (msg.replyToPreview || '').replace(/^\[SYSTEM\]\s*/, '');

            // Attachment UI rendering
            const att = msg.attachment;
            let attachment = att;
            try {
                if (att) {
                    const ext = (att.extension || '').toString().toLowerCase();
                    const versionId = att.latestVersionId || att.versionId || null;
                    const isImage = this.isImageExtension(ext);
                    const thumbUrl = (isImage && versionId) ? this.buildRenditionUrl(versionId, 'THUMB720BY480') : null;
                    const fullUrl = versionId ? this.buildDownloadUrl(versionId) : null;
                    attachment = {
                        ...att,
                        extension: att.extension,
                        versionId,
                        isImage,
                        thumbUrl,
                        fullUrl
                    };
                }
            } catch (eAtt) {
                attachment = att;
            }
            return {
                ...msg,
                isSystem,
                isDivider: false,
                displayContent,
                systemLine1: systemLines ? systemLines.line1 : '',
                systemLine2: systemLines ? systemLines.line2 : '',
                wrapperClass: isSystem ? 'msg-wrapper system' : (msg.isMine ? 'msg-wrapper mine' : 'msg-wrapper others'),
                bubbleClass: isSystem ? 'message-bubble system' : (msg.isMine ? 'message-bubble mine' : 'message-bubble others'),
                // Message actions: visibility
                showSender: !isSystem,
                showTimeRight: !msg.isMine,
                showUnreadCount,
                unreadByOthers,

                // Reply (Quote)
                hasReply: !!replyToId,
                replyToId,
                replyToSenderName,
                replyToPreview,

                // Message actions (copy/reply)
                showActions: !isSystem,
                actionsRowClass: msg.isMine ? 'message-actions-row mine' : 'message-actions-row others',
                actionsMenuAlignment: msg.isMine ? 'right' : 'left',

                // Attachment (preview handling)
                attachment
            };
        });
    }

    isImageExtension(extLower) {
        const ext = (extLower || '').toString().toLowerCase();
        return ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'].includes(ext);
    }

    buildDownloadUrl(versionId) {
        if (!versionId) return null;
        return `/sfc/servlet.shepherd/version/download/${versionId}`;
    }

    buildRenditionUrl(versionId, rendition) {
        if (!versionId) return null;
        const r = rendition || 'THUMB720BY480';
        return `/sfc/servlet.shepherd/version/renditionDownload?rendition=${encodeURIComponent(r)}&versionId=${encodeURIComponent(versionId)}`;
    }

    getMessageContainerEl() {
        return (this.refs && this.refs.messageContainer) || this.template.querySelector('.messages');
    }

    async loadMessages() {
        // Previous implementation: "Load initial" mode
        return this.loadInitialMessages();
    }

    async loadInitialMessages() {
        if (!this.currentSessionId) return;

        this.oldestCreatedDate = null;
        this.hasMoreMessages = true;
        this.isLoadingMoreMessages = false;

        try {
            const result = await getMessagesPaged({
                sessionId: this.currentSessionId,
                before: null,
                limitSize: this.messagePageSize
            });

            const decorated = this.decorateMessages(result);
            this.oldestCreatedDate = decorated.length ? decorated[0].createdDate : null;
            this.hasMoreMessages = (result || []).length >= this.messagePageSize;

            this.messages = this.addDateDividers(decorated);
            this.scrollToBottom();
            this.markCurrentSessionRead();
        } catch (e) {
            console.error('Error loading messages', e);
        }
    }

    async loadMoreMessages() {
        if (!this.currentSessionId) return;
        if (!this.hasMoreMessages || this.isLoadingMoreMessages) return;
        if (!this.oldestCreatedDate) return;

        this.isLoadingMoreMessages = true;
        const container = this.getMessageContainerEl();
        const prevScrollHeight = container ? container.scrollHeight : 0;

        try {
            const result = await getMessagesPaged({
                sessionId: this.currentSessionId,
                before: this.oldestCreatedDate,
                limitSize: this.messagePageSize
            });

            const older = this.decorateMessages(result);
            if (!older.length) {
                this.hasMoreMessages = false;
                return;
            }

            this.oldestCreatedDate = older[0].createdDate;
            this.hasMoreMessages = (result || []).length >= this.messagePageSize;

            // Dividers recompute based on oldest message dates (merge by id to prevent duplication)
            const currentMsgs = (this.messages || []).filter(m => !m.isDivider);
            const byId = new Map();
            for (const m of [...older, ...currentMsgs]) {
                if (m && m.id) byId.set(m.id, m);
            }
            const merged = Array.from(byId.values()).sort((a, b) => new Date(a.createdDate) - new Date(b.createdDate));

            this.messages = this.addDateDividers(merged);

            // Scroll adjustment (prepended messages shift display down, adjust scroll)
            if (container) {
                const newScrollHeight = container.scrollHeight;
                container.scrollTop = newScrollHeight - prevScrollHeight;
            }
        } catch (e) {
            console.error('Error loading more messages', e);
        } finally {
            this.isLoadingMoreMessages = false;
        }
    }

    handleMessagesScroll() {
        const container = this.getMessageContainerEl();
        if (!container) return;
        // Top threshold (scrolling up ~10px) triggers load more
        if (container.scrollTop <= 10) {
            this.loadMoreMessages();
        }

        // Bottom threshold triggers "mark read" (scroll monitoring + debounce)
        if (this.isNearBottom(container, 12)) {
            this.scheduleMarkRead();
        }
    }

    isNearBottom(container, thresholdPx) {
        try {
            const t = (thresholdPx == null) ? 12 : thresholdPx;
            const bottom = container.scrollTop + container.clientHeight;
            return bottom >= (container.scrollHeight - t);
        } catch (e) {
            return false;
        }
    }

    scheduleMarkRead() {
        if (!this.currentSessionId) return;
        // In list view mode, skip mark read
        if (!this.isChatView) return;

        // Debounce
        try {
            if (this.markReadTimer) {
                clearTimeout(this.markReadTimer);
            }
        } catch (e) {
            // ignore
        }

        this.markReadTimer = setTimeout(() => {
            this.markCurrentSessionRead();
        }, 200);
    }

    markCurrentSessionRead() {
        if (!this.currentSessionId) return;
        // No error output, just silent fail (UI refresh failure doesn't break chat)
        markSessionAsRead({ sessionId: this.currentSessionId })
            .then(() => {
                this.loadSessions(); // Update unreadCount immediately
            })
            .catch((e) => {
                // Existing error: silent ignore (debugging optional)
                console.error('markSessionAsRead failed', e);
            });
    }

    formatDateLabel(dt) {
        try {
            const d = new Date(dt);
            if (Number.isNaN(d.getTime())) return '';
            // Example: "Friday, January 8, 2026"
            return d.toLocaleDateString('en-US', {
                year: 'numeric',
                month: 'long',
                day: 'numeric',
                weekday: 'long'
            });
        } catch (e) {
            return '';
        }
    }

    dateKey(dt) {
        try {
            const d = new Date(dt);
            if (Number.isNaN(d.getTime())) return '';
            return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
        } catch (e) {
            return '';
        }
    }

    addDateDividers(messages) {
        const out = [];
        let prevKey = null;

        for (let i = 0; i < (messages || []).length; i += 1) {
            const m = messages[i];
            const key = this.dateKey(m?.createdDate);

            if (key && key !== prevKey) {
                out.push({
                    id: `divider-${key}-${i}`,
                    isDivider: true,
                    wrapperClass: 'msg-wrapper divider',
                    dividerLabel: this.formatDateLabel(m?.createdDate)
                });
                prevKey = key;
            }

            out.push(m);
        }

        return out;
    }

    splitSystemMessage(text) {
        // System message format: "Actor did Action." - format as 2 lines max
        // - Line 1: Actor name (abbreviated if too long)
        // - Line 2: Fixed phrase (e.g., "joined the chat." or "left the chat.")
        const t = (text || '').toString().trim();
        if (!t) return { line1: '', line2: '' };

        // Invited: "A invited B."
        if (t.includes('invited')) {
            const base = t.replace(/invited.*/, '').trim(); // "A"
            return { line1: base, line2: 'invited participants' };
        }

        // Left: "A left the chat."
        if (t.includes('left')) {
            const base = t.replace(/left.*/, '').trim(); // "A"
            return { line1: base, line2: 'left the chat' };
        }

        // Generic system message (custom)
        return { line1: t, line2: '' };
    }

    // --- Event Handlers ---

    handleSessionSelect(event) {
        this.currentSessionId = event.currentTarget.dataset.id;
        this.currentSessionName = event.currentTarget.dataset.name;
        this.currentSessionCreatedById = event.currentTarget.dataset.createdby;
        this.isChatView = true;
        this.clearSessionFlash(this.currentSessionId);
        this.writeActiveSessionToStorage();
        this.loadMessages();
        // Immediate mark read (initial load)
        this.markCurrentSessionRead();
    }

    handleBack() {
        // Return to list mode with immediate mark read (debounce protection)
        this.markCurrentSessionRead();
        this.isChatView = false;
        this.currentSessionId = null;
        this.messages = [];
        this.currentSessionCreatedById = null;
        this.replyDraft = null;
        this.writeActiveSessionToStorage();
        this.loadSessions(); // Refresh list to see updates
    }

    get canDeleteCurrentSession() {
        return this.normalizeId(this.currentSessionCreatedById) === this.normalizeId(this.currentUserId);
    }

    // --- People Modal (shared) ---

    get isPeopleCreateMode() {
        return this.peopleModalMode === 'create';
    }

    get isPeopleInviteMode() {
        return this.peopleModalMode === 'invite';
    }

    get isPeopleStep1() {
        return this.peopleModalStep === 1;
    }

    get isPeopleStep2() {
        return this.peopleModalStep === 2;
    }

    get peopleModalTitle() {
        return this.isPeopleCreateMode ? 'Create Chat' : 'Invite Participants';
    }

    get peopleStepLabel() {
        return this.isPeopleStep1 ? 'Step 1/2: Select' : 'Step 2/2: Confirm';
    }

    get peoplePrimaryLabel() {
        return this.isPeopleCreateMode ? 'Create' : 'Invite';
    }

    get peopleSelectedPreview() {
        return (this.peopleSelectedUsers || []).slice(0, 3);
    }

    get peopleSelectedMoreCount() {
        const n = (this.peopleSelectedUsers || []).length - 3;
        return n > 0 ? n : 0;
    }

    get isPeopleNextDisabled() {
        return !this.peopleSelectedUsers || this.peopleSelectedUsers.length === 0;
    }

    get isPeopleConfirmDisabled() {
        return this.isLoading || !this.peopleSelectedUsers || this.peopleSelectedUsers.length === 0;
    }

    openPeopleModal(mode) {
        this.peopleModalMode = mode === 'invite' ? 'invite' : 'create';
        this.peopleModalStep = 1;
        this.peopleSearchResults = [];
        this.peopleSelectedUsers = [];
        this.peopleChatName = '';
        this.isPeopleModalOpen = true;
    }

    closePeopleModal() {
        this.isPeopleModalOpen = false;
        this.peopleModalStep = 1;
        this.peopleSearchResults = [];
        this.peopleSelectedUsers = [];
        this.peopleChatName = '';
    }

    peopleNextStep() {
        if (this.isPeopleNextDisabled) return;
        this.peopleModalStep = 2;
    }

    peoplePrevStep() {
        this.peopleModalStep = 1;
    }

    handlePeopleChatNameChange(event) {
        this.peopleChatName = event.target.value;
    }

    handlePeopleUserSearch(event) {
        const term = event.target.value;
        if (term && term.length > 1) {
            searchUsers({ searchTerm: term })
                .then(result => {
                    const selectedSet = new Set((this.peopleSelectedUsers || []).map(u => u.id));
                    this.peopleSearchResults = (result || []).map(u => ({
                        ...u,
                        _selected: selectedSet.has(u.Id),
                        _rowClass: selectedSet.has(u.Id) ? 'people-result selected' : 'people-result'
                    }));
                })
                .catch(err => {
                    console.error('People search error', err);
                    this.peopleSearchResults = [];
                });
        } else {
            this.peopleSearchResults = [];
        }
    }

    handlePeopleToggleUser(event) {
        const userId = event.currentTarget.dataset.id;
        const userName = event.currentTarget.dataset.name;
        if (!userId) return;

        const exists = (this.peopleSelectedUsers || []).some(u => u.id === userId);
        if (exists) {
            this.peopleSelectedUsers = (this.peopleSelectedUsers || []).filter(u => u.id !== userId);
        } else {
            this.peopleSelectedUsers = [...(this.peopleSelectedUsers || []), { id: userId, name: userName }];
        }

        const selectedSet = new Set((this.peopleSelectedUsers || []).map(u => u.id));
        this.peopleSearchResults = (this.peopleSearchResults || []).map(u => ({
            ...u,
            _selected: selectedSet.has(u.Id),
            _rowClass: selectedSet.has(u.Id) ? 'people-result selected' : 'people-result'
        }));
    }

    handlePeopleRemoveUser(event) {
        const userId = event.currentTarget.dataset.id;
        this.peopleSelectedUsers = (this.peopleSelectedUsers || []).filter(u => u.id !== userId);

        const selectedSet = new Set((this.peopleSelectedUsers || []).map(u => u.id));
        this.peopleSearchResults = (this.peopleSearchResults || []).map(u => ({
            ...u,
            _selected: selectedSet.has(u.Id),
            _rowClass: selectedSet.has(u.Id) ? 'people-result selected' : 'people-result'
        }));
    }

    async confirmPeopleAction() {
        if (this.isPeopleConfirmDisabled) return;

        this.isLoading = true;
        try {
            const userIds = (this.peopleSelectedUsers || []).map(u => u.id);

            if (this.isPeopleCreateMode) {
                // If no name provided, Apex generates name from participants (included in creation)
                const name = (this.peopleChatName || '').trim();
                const result = await createOrGetChatSession({ name, userIds });
                const newSessionId = result?.sessionId;
                const existed = !!result?.existed;
                if (existed) {
                    // eslint-disable-next-line no-alert
                    alert('Chat session already exists. Joining existing session.');
                }

                // After create, immediately switch to chat view
                this.closePeopleModal();
                this.isChatView = true;
                this.currentSessionId = newSessionId;
                this.clearSessionFlash(newSessionId);

                // Fetch chat info from Apex to get name + createdById
                try {
                    const s = await getChatSession({ sessionId: newSessionId });
                    if (s) {
                        this.currentSessionName = s.name;
                        this.currentSessionCreatedById = s.createdById;
                    }
                } catch (e) {
                    // ignore (message view will still work)
                }

                this.writeActiveSessionToStorage();
                this.loadMessages();
                this.loadSessions();
                return;
            }

            if (this.isPeopleInviteMode) {
                await inviteParticipants({ sessionId: this.currentSessionId, userIds });
                this.closePeopleModal();
                this.loadMessages();
                this.loadSessions();
                return;
            }
        } catch (e) {
            const msg = e?.body?.message || e?.message || 'Request processing error occurred.';
            // eslint-disable-next-line no-alert
            alert(msg);
        } finally {
            this.isLoading = false;
        }
    }

    async handleChatMenuSelect(event) {
        const action = event?.detail?.value;
        if (!action || !this.currentSessionId) return;

        try {
            if (action === 'participants') {
                this.openParticipantsModal();
                return;
            }
            if (action === 'invite') {
                this.openPeopleModal('invite');
                return;
            }
            if (action === 'rename') {
                this.openRenameModal();
                return;
            }
            if (action === 'leave') {
                const ok = window.confirm('Do you want to leave this chat? (Other participants will see your departure message)');
                if (!ok) return;

                await leaveChatSession({ sessionId: this.currentSessionId });
                this.handleBack();
                return;
            }

            if (action === 'delete') {
                const ok = window.confirm('Delete this chat permanently? (Messages and participants data will be removed)');
                if (!ok) return;

                await deleteChatSession({ sessionId: this.currentSessionId });
                this.handleBack();
                return;
            }
        } catch (e) {
            // Use simple alert for user feedback
            const msg = e?.body?.message || e?.message || 'Request processing error occurred.';
            // eslint-disable-next-line no-alert
            alert(msg);
        }
    }

    // --- Participants Modal ---

    openParticipantsModal() {
        this.isParticipantsModalOpen = true;
        this.loadParticipants();
    }

    closeParticipantsModal() {
        this.isParticipantsModalOpen = false;
        this.isParticipantsLoading = false;
        this.participants = [];
    }

    async loadParticipants() {
        if (!this.currentSessionId) return;
        this.isParticipantsLoading = true;
        try {
            const data = await getParticipants({ sessionId: this.currentSessionId });
            const list = Array.isArray(data) ? data : [];
            // Sort by: me first, then by name
            list.sort((a, b) => {
                const aMe = a?.isMe ? 1 : 0;
                const bMe = b?.isMe ? 1 : 0;
                if (aMe !== bMe) return bMe - aMe; // me first
                const an = (a?.userName || '').toString();
                const bn = (b?.userName || '').toString();
                return an.localeCompare(bn, 'en-US');
            });

            this.participants = list.map(p => ({
                ...p,
                rowClass: p?.isMe ? 'participants-item me' : 'participants-item'
            }));
        } catch (e) {
            const msg = e?.body?.message || e?.message || 'Failed to load participants list.';
            // eslint-disable-next-line no-alert
            alert(msg);
            this.participants = [];
        } finally {
            this.isParticipantsLoading = false;
        }
    }

    get participantCountLabel() {
        return `${(this.participants || []).length} participants`;
    }

    // --- Rename Modal ---

    openRenameModal() {
        this.renameChatName = this.currentSessionName || '';
        this.isRenameModalOpen = true;
    }

    closeRenameModal() {
        this.isRenameModalOpen = false;
        this.renameChatName = '';
    }

    handleRenameNameChange(event) {
        this.renameChatName = event.target.value;
    }

    async confirmRename() {
        const name = (this.renameChatName || '').trim();
        if (!name) return;

        this.isLoading = true;
        try {
            await renameChatSession({ sessionId: this.currentSessionId, newName: name });
            this.currentSessionName = name;

            // Update list immediately (Platform Event will also refresh, but update now)
            const currentId = this.normalizeId(this.currentSessionId);
            this.sessions = this.decorateSessions(
                (this.sessions || []).map(s =>
                    this.normalizeId(s.sessionId) === currentId ? { ...s, name } : s
                )
            );

            this.closeRenameModal();
            await this.loadSessions();
        } catch (e) {
            const msg = e?.body?.message || e?.message || 'Chat rename error occurred.';
            // eslint-disable-next-line no-alert
            alert(msg);
        } finally {
            this.isLoading = false;
        }
    }


    handleInputChange(event) {
        this.messageInput = event.target.value;
    }

    handleInputKeyDown(event) {
        // lightning-input oncommit doesn't trigger on Enter + Shift, so direct key catch
        // Shift+Enter = line break
        if (this.isLoading) return;
        if (event && (event.isComposing || event.keyCode === 229)) return; // IME composition
        if (event?.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            event.stopPropagation();
            this.handleSendMessage();
        }
    }

    focusChatInput() {
        // After message delete (reply cleared), focus input for UX
        setTimeout(() => {
            try {
                const input = this.refs?.chatInput;
                if (input && typeof input.focus === 'function') {
                    input.focus();
                    return;
                }
                const fallback = this.template.querySelector('.input-box');
                if (fallback && typeof fallback.focus === 'function') {
                    fallback.focus();
                }
            } catch (e) {
                // ignore
            }
        }, 0);
    }

    handleSendMessage() {
        // lightning-input onchange delayed state: use ref for immediate read
        // Message input component: read state directly to avoid race conditions
        const raw = (this.refs?.chatInput?.value ?? this.messageInput ?? '').toString();
        if (!raw.trim()) return;

        const content = raw;
        const replyToMessageId = this.replyDraft?.messageId || null;
        const replyPreview = this.replyDraft?.preview || null;

        // Clear immediately (state + actual input)
        this.messageInput = '';
        try {
            if (this.refs?.chatInput) {
                this.refs.chatInput.value = '';
            }
        } catch (e) {
            // ignore
        }
        this.isLoading = true;
        this.focusChatInput();

        sendMessage({
            sessionId: this.currentSessionId,
            content: content,
            contentDocumentId: null,
            replyToMessageId,
            replyPreview
        })
            .then(() => {
                this.isLoading = false;
                this.replyDraft = null;
                this.loadMessages();
                this.focusChatInput();
            })
            .catch(error => {
                this.isLoading = false;
                console.error('Send error', error);
                this.focusChatInput();
            });
    }

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        if (uploadedFiles && uploadedFiles.length > 0) {
            const docId = uploadedFiles[0].documentId;
            this.isLoading = true;
            const replyToMessageId = this.replyDraft?.messageId || null;
            const replyPreview = this.replyDraft?.preview || null;
            sendMessage({
                sessionId: this.currentSessionId,
                content: 'File attached.',
                contentDocumentId: docId,
                replyToMessageId,
                replyPreview
            })
                .then(() => {
                    this.isLoading = false;
                    this.replyDraft = null;
                    this.loadMessages();
                    this.focusChatInput();
                })
                .catch(error => {
                    this.isLoading = false;
                    console.error('File attach error', error);
                    this.focusChatInput();
                });
        }
    }

    // --- Message actions (copy/reply) ---

    async handleMessageMenuSelect(event) {
        const action = event?.detail?.value;
        const messageId = event?.currentTarget?.dataset?.id;
        if (!action || !messageId) return;

        const msg = (this.messages || []).find(m => m && !m.isDivider && m.id === messageId);
        if (!msg) return;

        if (action === 'copy') {
            this.copyToClipboard(msg.displayContent || '');
            return;
        }
        if (action === 'reply') {
            this.setReplyDraftFromMessage(msg);
        }
    }

    setReplyDraftFromMessage(msg) {
        const senderName = msg.senderName || '';
        let preview = (msg.displayContent || '').toString().trim();
        if (!preview && msg.attachment?.title) {
            preview = `[File] ${msg.attachment.title}`;
        }
        preview = preview.replace(/\s+/g, ' ').trim();
        if (preview.length > 80) preview = preview.substring(0, 77) + '...';

        this.replyDraft = {
            messageId: msg.id,
            senderName,
            preview
        };
        this.focusChatInput();
    }

    clearReplyDraft() {
        this.replyDraft = null;
        this.focusChatInput();
    }

    async copyToClipboard(text) {
        const value = (text || '').toString();
        if (!value) return;
        try {
            if (navigator?.clipboard?.writeText) {
                await navigator.clipboard.writeText(value);
                return;
            }
        } catch (e) {
            // fallback below
        }

        // Old browser fallback
        try {
            const ta = document.createElement('textarea');
            ta.value = value;
            ta.setAttribute('readonly', 'true');
            ta.style.position = 'fixed';
            ta.style.left = '-9999px';
            document.body.appendChild(ta);
            ta.select();
            document.execCommand('copy');
            document.body.removeChild(ta);
        } catch (e2) {
            // eslint-disable-next-line no-alert
            alert('Copy failed.');
        }
    }

    get isReplying() {
        return !!this.replyDraft;
    }

    get replyDraftLabel() {
        const name = this.replyDraft?.senderName || '';
        const preview = this.replyDraft?.preview || '';
        return `${name}: ${preview}`;
    }

    get chatAreaClass() {
        return this.isReplying ? 'chat-area replying' : 'chat-area';
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


    clearSessionFlash(sessionId) {
        const key = this.normalizeId(sessionId);
        if (!key) return;
        if (this.sessionFlashMap[key]) {
            const next = { ...this.sessionFlashMap };
            delete next[key];
            this.sessionFlashMap = next;
            this.refreshSessionClasses();
        }
    }

    scrollToBottom() {
        setTimeout(() => {
            try {
                const container =
                    (this.refs && this.refs.messageContainer) ||
                    this.template.querySelector('.messages');
                if (container) {
                    container.scrollTop = container.scrollHeight;
                }
            } catch (e) {
                // ignore
            }
        }, 100);
    }

    // --- Modal Logic ---

    openNewChatModal() {
        this.openPeopleModal('create');
    }

    // --- EMP API (Real-time) ---

    handleSubscribe() {
        if (this.subscription && this.subscription.id) {
            return;
        }

        const messageCallback = (response) => {
            if (response?.data?.payload?.Payload__c) {
                try {
                    const raw = response.data.payload.Payload__c;
                    const rawStr = String(raw);
                    let payload;
                    try {
                        payload = JSON.parse(rawStr.replace(/#\\\"/g, '"').replace(/#\"/g, '"'));
                    } catch (e) {
                        payload = JSON.parse(rawStr);
                    }

                    // Check participant: only process if in participant list (Platform Event org-wide broadcast)
                    const myId15 = (this.currentUserId || '').substring(0, 15);
                    const participants = payload?.participantIds;
                    if (Array.isArray(participants) && participants.length) {
                        const ok = participants.some(id => String(id || '').substring(0, 15) === myId15);
                        if (!ok) {
                            return;
                        }
                    } else {
                        // If participantIds missing, skip old event (safety)
                        return;
                    }

                    const sessionKey = this.normalizeId(payload.sessionId);
                    const isSameSession = this.normalizeId(this.currentSessionId) === sessionKey;
                    const eventType = payload?.type;

                    // Chat name rename: refresh list + update title immediately
                    if (eventType === 'SessionRenamed' && sessionKey) {
                        const newName = payload?.newName;
                        if (newName) {
                            if (this.isChatView && isSameSession) {
                                this.currentSessionName = newName;
                            }

                            // Update list immediately
                            this.sessions = this.decorateSessions(
                                (this.sessions || []).map(s =>
                                    this.normalizeId(s.sessionId) === sessionKey ? { ...s, name: newName } : s
                                )
                            );
                        }

                        this.loadSessions();
                        return; // Skip below message load
                    }

                    // Read receipt: refresh unread in messages after others mark read
                    if (eventType === 'ReadReceipt' && sessionKey) {
                        // All participants (both sender + reader) should see receipt
                        // Update logic: get recent messages only on unread badge change
                        if (this.isChatView && isSameSession) {
                            this.loadMessages();
                        } else {
                            // List view: update session unread count
                            this.loadSessions();
                        }
                        return;
                    }

                    // Real-time updates:
                    // - New message + notification refresh
                    // (payload.sessionId guaranteed by participant check)
                    if (this.isChatView && this.currentSessionId) {
                        this.loadMessages();
                    } else {
                        this.loadSessions();
                    }

                    // Notification flash: non-sender message + current session not open
                    const senderId15 = (payload.senderId || '').substring(0, 15);
                    if (senderId15 && senderId15 !== myId15 && sessionKey) {
                        // Mute check: if muted, skip flash
                        if (this.mutedSessionMap && this.mutedSessionMap[sessionKey]) {
                            return;
                        }
                        if (!(this.isChatView && isSameSession)) {
                            this.sessionFlashMap = { ...this.sessionFlashMap, [sessionKey]: true };
                            this.refreshSessionClasses();
                        } else {
                            this.clearSessionFlash(sessionKey);
                        }
                    }
                } catch (e) {
                    console.error('JSON Parse Error', e);
                }
            }
        };

        subscribe(this.channelName, -1, messageCallback).then(response => {
            this.subscription = response;
        });

        onError(error => {
            console.error('EMP API Error', error);
        });
    }

    handleUnsubscribe() {
        unsubscribe(this.subscription, () => {});
    }

    writeActiveSessionToStorage() {
        // ChatFlashAura references (localStorage)
        try {
            const session15 = this.normalizeId(this.currentSessionId);
            window.localStorage.setItem('utilityChat.activeSession15', session15);
            window.localStorage.setItem('utilityChat.isChatView', this.isChatView ? 'true' : 'false');
        } catch (e) {
            // ignore
        }
    }

    writeMutedSessionsToStorage() {
        // ChatFlashAura references (localStorage): muted session list (15-char ids)
        try {
            const keys = Object.keys(this.mutedSessionMap || {}).filter(k => this.mutedSessionMap[k]);
            window.localStorage.setItem('utilityChat.mutedSessions15', JSON.stringify(keys));
        } catch (e) {
            // ignore
        }
    }

    async togglePin(event) {
        event.preventDefault();
        event.stopPropagation();
        const sessionId = event.currentTarget.dataset.id;
        const pinned = event.currentTarget.dataset.pinned === 'true';
        try {
            await setPinned({ sessionId, pinned: !pinned });
            await this.loadSessions();
        } catch (e) {
            const msg = e?.body?.message || e?.message || 'Pin error occurred.';
            // eslint-disable-next-line no-alert
            alert(msg);
        }
    }

    async toggleMute(event) {
        event.preventDefault();
        event.stopPropagation();
        const sessionId = event.currentTarget.dataset.id;
        const muted = event.currentTarget.dataset.muted === 'true';
        try {
            await setMuted({ sessionId, muted: !muted });
            await this.loadSessions();
        } catch (e) {
            const msg = e?.body?.message || e?.message || 'Mute error occurred.';
            // eslint-disable-next-line no-alert
            alert(msg);
        }
    }
}
