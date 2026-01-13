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
    // 메시지 페이징(무한 스크롤)
    messagePageSize = 30;
    oldestCreatedDate = null;
    hasMoreMessages = true;
    isLoadingMoreMessages = false;
    // People Modal(공용) 상태
    @track peopleSearchResults = [];
    @track peopleSelectedUsers = []; // {id, name}

    currentSessionId;
    currentSessionName;
    currentSessionCreatedById;
    isRenameModalOpen = false;
    renameChatName = '';

    // 참여자 목록 모달
    isParticipantsModalOpen = false;
    isParticipantsLoading = false;
    @track participants = []; // [{ userId, userName, lastReadAt, isPinned, isMuted, isMe }]

    // 답장(Reply) 상태
    replyDraft = null; // { messageId, senderName, preview }

    // 읽음 처리 디바운스(스크롤/실시간 갱신 시 과도한 Apex 호출 방지)
    markReadTimer;

    isChatView = false;
    // People Modal(공용): create/invite
    isPeopleModalOpen = false;
    peopleModalMode = 'create'; // 'create' | 'invite'
    peopleModalStep = 1; // 1: 선택, 2: 관리/확인
    messageInput = '';
    peopleChatName = '';
    isLoading = false;

    // 수신 알림(플래시) 상태: sessionId별로 표시
    @track sessionFlashMap = {}; // { [sessionId]: true }
    mutedSessionMap = {}; // { [sessionId15]: true }

    subscription = {};
    channelName = '/event/Chat_Notification__e';
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
            // 카카오톡 스타일: "안 읽은 사람 수(보낸 사람 제외)"만 표시 (0이면 숨김)
            const unreadByOthers = Number(msg.unreadByOthers || 0);
            const showUnreadCount = !isSystem && unreadByOthers > 0;
            const replyToId = msg.replyToId;
            const replyToSenderName = msg.replyToSenderName;
            const replyToPreview = (msg.replyToPreview || '').replace(/^\[SYSTEM\]\s*/, '');

            // 첨부파일 UI용 파생 필드
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
                // 내 메시지도 이름을 표시
                showSender: !isSystem,
                showTimeRight: !msg.isMine,
                showUnreadCount,
                unreadByOthers,

                // 답장(Reply)
                hasReply: !!replyToId,
                replyToId,
                replyToSenderName,
                replyToPreview,

                // 메시지 액션(복사/답장)
                showActions: !isSystem,
                actionsRowClass: msg.isMine ? 'message-actions-row mine' : 'message-actions-row others',
                actionsMenuAlignment: msg.isMine ? 'right' : 'left',

                // attachment(파생 필드 포함)
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
        // 기존 호출부 호환: "초기 로드"로 동작
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

            // divider는 원본 메시지 기준으로 다시 계산(중복 방지 위해 id로 merge)
            const currentMsgs = (this.messages || []).filter(m => !m.isDivider);
            const byId = new Map();
            for (const m of [...older, ...currentMsgs]) {
                if (m && m.id) byId.set(m.id, m);
            }
            const merged = Array.from(byId.values()).sort((a, b) => new Date(a.createdDate) - new Date(b.createdDate));

            this.messages = this.addDateDividers(merged);

            // 스크롤 위치 유지(위에 prepend되었으니 증가한 높이만큼 내려줌)
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
        // 상단 근처(여유값 10px) 도달 시 이전 메시지 로드
        if (container.scrollTop <= 10) {
            this.loadMoreMessages();
        }

        // 하단 근처면 "읽음 처리" (사용자가 실제로 보고 있는 경우를 우선)
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
        // list view에서는 의미 없으므로 방지
        if (!this.isChatView) return;

        // 디바운스
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
        // 서버 업데이트는 실패해도 UI는 유지
        markSessionAsRead({ sessionId: this.currentSessionId })
            .then(() => {
                this.loadSessions(); // unreadCount 즉시 갱신
            })
            .catch((e) => {
                // 기존에는 에러를 삼켜서 "읽었는데 배지 뜸" 같은 현상의 원인 파악이 어려웠습니다.
                // 콘솔에 남겨서(필요 시) 디버깅 가능하게 합니다.
                // eslint-disable-next-line no-console
                console.error('markSessionAsRead failed', e);
            });
    }

    formatDateLabel(dt) {
        try {
            const d = new Date(dt);
            if (Number.isNaN(d.getTime())) return '';
            // 예: "2026년 1월 8일 목요일"
            return d.toLocaleDateString('ko-KR', {
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
        // 시스템 문구는 "무조건 2줄"로만 렌더링
        // - 1줄: 이름/대상(길면 ... 처리)
        // - 2줄: 고정 문구(채팅방을 나갔습니다. / 초대했습니다.)
        const t = (text || '').toString().trim();
        if (!t) return { line1: '', line2: '' };

        // 나가기: "A님이 채팅방을 나갔습니다."
        if (t.endsWith('채팅방을 나갔습니다.')) {
            const base = t.replace(/채팅방을 나갔습니다\.$/, '').trim(); // "A님이"
            const marker = '님이';
            const pos = base.indexOf(marker);
            if (pos >= 0) {
                const line1 = base.substring(0, pos + marker.length).trim(); // "A님이"
                return { line1, line2: '채팅방을 나갔습니다.' };
            }
            return { line1: base, line2: '채팅방을 나갔습니다.' };
        }

        // 초대: "A님이 B님을 초대했습니다."
        if (t.endsWith('초대했습니다.')) {
            const base = t.replace(/초대했습니다\.$/, '').trim(); // "A님이 B님을"
            const marker = '님이';
            const pos = base.indexOf(marker);
            if (pos >= 0) {
                const actor = base.substring(0, pos + marker.length).trim(); // "A님이"
                const rest = base.substring(pos + marker.length).trim(); // "B님을"
                return { line1: actor, line2: (rest ? (rest + ' ') : '') + '초대했습니다.' };
            }
            return { line1: base, line2: '초대했습니다.' };
        }

        // 기타 시스템 메시지(예외)
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
        // 입장 직후도 읽음 처리(초기 진입)
        this.markCurrentSessionRead();
    }

    handleBack() {
        // 리스트로 돌아가기 전에 마지막으로 읽음 처리(배지 튐 방지)
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

    // --- People Modal (공용) ---

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
        return this.isPeopleCreateMode ? '새 채팅방 만들기' : '참여자 초대';
    }

    get peopleStepLabel() {
        return this.isPeopleStep1 ? '1/2 선택' : '2/2 확인';
    }

    get peoplePrimaryLabel() {
        return this.isPeopleCreateMode ? '생성' : '초대';
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
                // 이름 미입력 시 Apex에서 참여자 전원(생성자 포함) 이름으로 자동 생성
                const name = (this.peopleChatName || '').trim();
                const result = await createOrGetChatSession({ name, userIds });
                const newSessionId = result?.sessionId;
                const existed = !!result?.existed;
                if (existed) {
                    // eslint-disable-next-line no-alert
                    alert('기존 채팅방이 있습니다. 해당 채팅방으로 이동합니다.');
                }

                // 생성 직후 바로 채팅방 화면으로 전환
                this.closePeopleModal();
                this.isChatView = true;
                this.currentSessionId = newSessionId;
                this.clearSessionFlash(newSessionId);

                // 헤더 이름/생성자 정보는 Apex에서 조회 (자동 생성 이름까지 정확히 반영)
                try {
                    const s = await getChatSession({ sessionId: newSessionId });
                    if (s) {
                        this.currentSessionName = s.name;
                        this.currentSessionCreatedById = s.createdById;
                    }
                } catch (e) {
                    // ignore (메시지 화면 진입은 유지)
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
            const msg = e?.body?.message || e?.message || '요청 처리 중 오류가 발생했습니다.';
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
                const ok = window.confirm('이 채팅방에서 나가시겠습니까? (다시 보려면 초대가 필요합니다)');
                if (!ok) return;

                await leaveChatSession({ sessionId: this.currentSessionId });
                this.handleBack();
                return;
            }

            if (action === 'delete') {
                const ok = window.confirm('채팅방을 삭제하시겠습니까? (메시지/참여자 정보가 함께 삭제됩니다)');
                if (!ok) return;

                await deleteChatSession({ sessionId: this.currentSessionId });
                this.handleBack();
                return;
            }
        } catch (e) {
            // 토스트 대신 간단한 alert 사용
            const msg = e?.body?.message || e?.message || '요청 처리 중 오류가 발생했습니다.';
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
            // (나) 항목을 최상단으로, 그 외는 이름순 정렬
            list.sort((a, b) => {
                const aMe = a?.isMe ? 1 : 0;
                const bMe = b?.isMe ? 1 : 0;
                if (aMe !== bMe) return bMe - aMe; // me 먼저
                const an = (a?.userName || '').toString();
                const bn = (b?.userName || '').toString();
                return an.localeCompare(bn, 'ko-KR');
            });

            this.participants = list.map(p => ({
                ...p,
                rowClass: p?.isMe ? 'participants-item me' : 'participants-item'
            }));
        } catch (e) {
            const msg = e?.body?.message || e?.message || '참여자 목록을 불러오지 못했습니다.';
            // eslint-disable-next-line no-alert
            alert(msg);
            this.participants = [];
        } finally {
            this.isParticipantsLoading = false;
        }
    }

    get participantCountLabel() {
        return `${(this.participants || []).length}명`;
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

            // 목록도 즉시 갱신(사용자가 '뒤로'를 눌렀을 때 바로 반영되도록)
            const currentId = this.normalizeId(this.currentSessionId);
            this.sessions = this.decorateSessions(
                (this.sessions || []).map(s =>
                    this.normalizeId(s.sessionId) === currentId ? { ...s, name } : s
                )
            );

            this.closeRenameModal();
            await this.loadSessions();
        } catch (e) {
            const msg = e?.body?.message || e?.message || '채팅방 이름 변경 중 오류가 발생했습니다.';
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
        // lightning-input의 oncommit은 "값 변경"이 없으면 Enter로 커밋이 안 되는 경우가 있어
        // Enter 키를 직접 캐치해서 동일 값 반복도 전송되게 처리합니다.
        if (this.isLoading) return;
        if (event && (event.isComposing || event.keyCode === 229)) return; // IME 조합 중

        if (event?.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            event.stopPropagation();
            this.handleSendMessage();
        }
    }

    focusChatInput() {
        // 메시지 전송 후에도 연속 입력이 가능하도록 입력창에 포커스를 다시 줍니다.
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
        // lightning-input은 onchange 타이밍 문제로 동일 값 반복 입력 시 state가 늦게 갱신될 수 있어
        // 전송 시점엔 입력 컴포넌트의 현재 값을 우선 사용합니다.
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
                content: '📎 사진/파일을 첨부했습니다.',
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

    // --- 메시지 액션(복사/답장) ---

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
            preview = `📎 ${msg.attachment.title}`;
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

        // 구형 브라우저 fallback
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
            alert('복사에 실패했습니다.');
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

                    // 참여자가 아닌 사용자는 무시 (Platform Event는 org-wide 브로드캐스트)
                    const myId15 = (this.currentUserId || '').substring(0, 15);
                    const participants = payload?.participantIds;
                    if (Array.isArray(participants) && participants.length) {
                        const ok = participants.some(id => String(id || '').substring(0, 15) === myId15);
                        if (!ok) {
                            return;
                        }
                    } else {
                        // participantIds가 없으면(구버전 이벤트) 오탐 방지를 위해 무시
                        return;
                    }

                    const sessionKey = this.normalizeId(payload.sessionId);
                    const isSameSession = this.normalizeId(this.currentSessionId) === sessionKey;
                    const eventType = payload?.type;

                    // 채팅방 이름 변경: 상대방 포함 즉시 UI에 반영
                    if (eventType === 'SessionRenamed' && sessionKey) {
                        const newName = payload?.newName;
                        if (newName) {
                            if (this.isChatView && isSameSession) {
                                this.currentSessionName = newName;
                            }

                            // 목록도 즉시 반영
                            this.sessions = this.decorateSessions(
                                (this.sessions || []).map(s =>
                                    this.normalizeId(s.sessionId) === sessionKey ? { ...s, name: newName } : s
                                )
                            );
                        }

                        this.loadSessions();
                        return; // 플래시/메시지 로드 처리 불필요
                    }

                    // 읽음 처리 이벤트: 내가 보낸 메시지의 읽음 숫자 갱신을 위해 메시지 재로드
                    if (eventType === 'ReadReceipt' && sessionKey) {
                        // 모든 참여자가(읽은 사람 포함) 동일한 읽음 숫자를 봐야 하므로
                        // self-event도 처리합니다. 루프는 서버에서 최신 시각까지만 업데이트하도록 막습니다.
                        if (this.isChatView && isSameSession) {
                            this.loadMessages();
                        } else {
                            // 리스트 뷰에서도 안읽음 배지 갱신 가능
                            this.loadSessions();
                        }
                        return;
                    }

                    // 실시간성 우선:
                    // - 채팅방을 보고 있는 동안엔 어떤 이벤트가 오든 메시지 목록을 항상 새로고침
                    //   (payload.sessionId가 예상과 달라도 UI가 멈추지 않게)
                    if (this.isChatView && this.currentSessionId) {
                        this.loadMessages();
                    } else {
                        this.loadSessions();
                    }

                    // 플래시 조건: 상대 메시지 + 내가 같은 방을 보고 있지 않을 때만
                    const senderId15 = (payload.senderId || '').substring(0, 15);
                    if (senderId15 && senderId15 !== myId15 && sessionKey) {
                        // Mute 세션이면 깜빡임(세션 플래시) 제외
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
        // ChatFlashAura가 참조할 값(localStorage)
        try {
            const session15 = this.normalizeId(this.currentSessionId);
            window.localStorage.setItem('utilityChat.activeSession15', session15);
            window.localStorage.setItem('utilityChat.isChatView', this.isChatView ? 'true' : 'false');
        } catch (e) {
            // ignore
        }
    }

    writeMutedSessionsToStorage() {
        // ChatFlashAura가 참조할 값(localStorage): muted 세션 목록(15자리)
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
            const msg = e?.body?.message || e?.message || '고정 설정 중 오류가 발생했습니다.';
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
            const msg = e?.body?.message || e?.message || '알림 설정 중 오류가 발생했습니다.';
            // eslint-disable-next-line no-alert
            alert(msg);
        }
    }
}