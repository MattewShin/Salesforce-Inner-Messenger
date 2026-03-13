/**
 * @description utilityChat 컴포넌트 다국어 라벨 정의
 *              지원 언어: EN(기본값), KO(한국어)
 *              사용법: import { LABELS } from './lang';
 *                      const LOCALE = (LANGUAGE || 'en').startsWith('ko') ? 'KO' : 'EN';
 *                      labels = LABELS[LOCALE];
 */
export const LABELS = {
    EN: {
        // ── Header ──────────────────────────────────────────────
        headerTitle: 'Chat',
        backAlt: 'Back',
        newChatAlt: 'New Chat',
        chatMenuAlt: 'Chat Room Menu',
        menuParticipants: 'Participants',
        menuInvite: 'Invite',
        menuRename: 'Rename Chat',
        menuDownload: 'Download History',
        menuLeave: 'Leave Chat',
        menuDelete: 'Delete Chat',

        // ── Session List ─────────────────────────────────────────
        noSessions: 'No chat rooms joined.',
        selectChatMessage: 'Select a chat to view messages',
        collapsePanelAlt: 'Collapse chat list',
        expandPanelAlt: 'Expand chat list',
        pinAlt: 'Pin',
        pinTitle: 'Pin',
        muteAlt: 'Notifications',
        muteTitle: 'Notifications',

        // ── Message Actions ──────────────────────────────────────
        msgMenuAlt: 'Message menu',
        msgMenuCopy: 'Copy',
        msgMenuReply: 'Reply',

        // ── Input Area ───────────────────────────────────────────
        fileAttachTitle: 'Attach file',
        msgInputPlaceholder: 'Type a message... (Enter: send, Shift+Enter: new line, Ctrl+V: paste image)',
        sendAlt: 'Send',
        replyTitle: 'Reply',
        replyCancelAlt: 'Cancel reply',
        replyCancelTitle: 'Cancel',

        // ── People Modal ─────────────────────────────────────────
        createChatTitle: 'Create Chat',
        inviteParticipantsTitle: 'Invite Participants',
        step1Label: 'Step 1/2: Select',
        step2Label: 'Step 2/2: Confirm',
        createBtn: 'Create',
        inviteBtn: 'Invite',
        userSearchLabel: 'Search users',
        userSearchPlaceholder: 'Search by name...',
        selectedLabel: 'Selected',
        /** 인원 수 접미어. "(3 people)" 형태: `(${n}${suffix})` */
        personCountSuffix: ' people',
        nextBtn: 'Next',
        chatNameOptionalLabel: 'Chat room name (optional)',
        selectedUsersTitle: 'Selected users',
        noUsersSelected: 'Please select a user.',
        closeBtn: 'Close',

        // ── Rename Modal ─────────────────────────────────────────
        renameChatTitle: 'Rename Chat',
        chatNameLabel: 'Chat room name',
        changeBtn: 'Change',

        // ── Participants Modal ───────────────────────────────────
        participantsTitle: 'Participants',
        meLabel: '(Me)',
        noParticipants: 'No participants found.',
        /** 참여자 수 단위. "${n} participants" 형태: `${n}${unit}` */
        participantsUnit: ' participants',

        // ── JS: alert / confirm ──────────────────────────────────
        sessionExistsAlert: 'Chat session already exists. Joining existing session.',
        requestErrorDefault: 'Request processing error occurred.',
        leaveConfirm: 'Do you want to leave this chat? (Other participants will see your departure message)',
        deleteConfirm: 'Delete this chat permanently? (Messages and participants data will be removed)',
        loadParticipantsError: 'Failed to load participants list.',
        renameError: 'Chat rename error occurred.',
        pinError: 'Pin error occurred.',
        muteError: 'Notification setting error occurred.',

        // ── JS: 메시지 콘텐츠 ──────────────────────────────────────
        screenshotAttached: 'Screenshot attached.',
        fileAttached: 'File attached.',
        /** 답장 미리보기 첨부 접두어: "[File] filename" */
        filePrefix: '[File] ',
        imagePasteError: 'An error occurred while uploading the image.',
        copyFailed: 'Copy failed.',

        // ── JS: 대화내역 다운로드 ──────────────────────────────────
        noChatRoomInfo: 'Chat room information not found.',
        noMessagesToDownload: 'No messages to download.',
        downloadFilenamePrefix: 'ChatHistory',
        downloadError: 'An error occurred while downloading the chat history.',
        csvHeaders: ['Date/Time', 'Sender', 'Content', 'Reply To', 'Reply Content', 'Attachment'],
        /** CSV 첨부파일 셀 접두어 */
        fileAttachPrefix: '[File] ',

        // ── JS: 시스템 메시지 표시 문구 ───────────────────────────
        systemInvited: 'invited participants',
        systemLeft: 'left the chat',

        // ── JS: 날짜 포맷 로케일 ──────────────────────────────────
        dateLocale: 'en-US',
    },

    KO: {
        // ── Header ──────────────────────────────────────────────
        headerTitle: 'Chat',
        backAlt: '뒤로',
        newChatAlt: '새 채팅',
        chatMenuAlt: '채팅방 메뉴',
        menuParticipants: '참여자 목록',
        menuInvite: '참여자 초대',
        menuRename: '채팅방 이름 변경',
        menuDownload: '대화내역 내려받기',
        menuLeave: '채팅방 나가기',
        menuDelete: '채팅방 삭제',

        // ── Session List ─────────────────────────────────────────
        noSessions: '참여 중인 채팅방이 없습니다.',
        selectChatMessage: '채팅방을 선택하여 메시지를 확인하세요',
        collapsePanelAlt: '채팅방 목록 접기',
        expandPanelAlt: '채팅방 목록 펼치기',
        pinAlt: '고정',
        pinTitle: '고정',
        muteAlt: '알림',
        muteTitle: '알림',

        // ── Message Actions ──────────────────────────────────────
        msgMenuAlt: '메시지 메뉴',
        msgMenuCopy: '복사',
        msgMenuReply: '답장',

        // ── Input Area ───────────────────────────────────────────
        fileAttachTitle: '파일 첨부',
        msgInputPlaceholder: '메시지 입력... (Enter: 전송, Shift+Enter: 줄바꿈, Ctrl+V: 이미지 붙여넣기)',
        sendAlt: '전송',
        replyTitle: '답장',
        replyCancelAlt: '답장 취소',
        replyCancelTitle: '취소',

        // ── People Modal ─────────────────────────────────────────
        createChatTitle: '채팅 만들기',
        inviteParticipantsTitle: '참여자 초대',
        step1Label: '1/2단계: 선택',
        step2Label: '2/2단계: 확인',
        createBtn: '만들기',
        inviteBtn: '초대',
        userSearchLabel: '사용자 검색',
        userSearchPlaceholder: '이름 검색...',
        selectedLabel: '선택됨',
        personCountSuffix: '명',
        nextBtn: '다음',
        chatNameOptionalLabel: '채팅방 이름(선택)',
        selectedUsersTitle: '선택된 사용자',
        noUsersSelected: '사용자를 선택하세요.',
        closeBtn: '닫기',

        // ── Rename Modal ─────────────────────────────────────────
        renameChatTitle: '채팅방 이름 변경',
        chatNameLabel: '채팅방 이름',
        changeBtn: '변경',

        // ── Participants Modal ───────────────────────────────────
        participantsTitle: '참여자 목록',
        meLabel: '(나)',
        noParticipants: '참여자를 찾을 수 없습니다.',
        participantsUnit: '명',

        // ── JS: alert / confirm ──────────────────────────────────
        sessionExistsAlert: '이미 존재하는 채팅방입니다. 기존 채팅방으로 이동합니다.',
        requestErrorDefault: '요청 처리 중 오류가 발생했습니다.',
        leaveConfirm: '채팅방을 나가시겠습니까? (다른 참여자에게 퇴장 메시지가 표시됩니다)',
        deleteConfirm: '채팅방을 완전히 삭제하시겠습니까? (메시지와 참여자 데이터가 모두 삭제됩니다)',
        loadParticipantsError: '참여자 목록을 불러오는 데 실패했습니다.',
        renameError: '채팅방 이름 변경 중 오류가 발생했습니다.',
        pinError: '고정 처리 중 오류가 발생했습니다.',
        muteError: '알림 설정 중 오류가 발생했습니다.',

        // ── JS: 메시지 콘텐츠 ──────────────────────────────────────
        screenshotAttached: '스크린샷이 첨부되었습니다.',
        fileAttached: '파일이 첨부되었습니다.',
        filePrefix: '[파일] ',
        imagePasteError: '이미지 업로드 중 오류가 발생했습니다.',
        copyFailed: '복사에 실패했습니다.',

        // ── JS: 대화내역 다운로드 ──────────────────────────────────
        noChatRoomInfo: '채팅방 정보를 찾을 수 없습니다.',
        noMessagesToDownload: '다운로드할 메시지가 없습니다.',
        downloadFilenamePrefix: '채팅내역',
        downloadError: '대화내역 다운로드 중 오류가 발생했습니다.',
        csvHeaders: ['일시', '보낸사람', '내용', '답장 대상', '답장 내용', '첨부파일'],
        fileAttachPrefix: '[파일] ',

        // ── JS: 시스템 메시지 표시 문구 ───────────────────────────
        systemInvited: '님을 초대했습니다',
        systemLeft: '님이 퇴장했습니다',

        // ── JS: 날짜 포맷 로케일 ──────────────────────────────────
        dateLocale: 'ko-KR',
    },
};