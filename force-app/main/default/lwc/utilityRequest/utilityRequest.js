import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import upsertDraftLeave from '@salesforce/apex/LeaveRequestController.upsertDraft';
import submitLeave from '@salesforce/apex/LeaveRequestController.submit';
import cancelLeaveBeforeApproval from '@salesforce/apex/LeaveRequestController.cancelBeforeApproval';
import requestCancelAfterApproval from '@salesforce/apex/LeaveRequestController.requestCancelAfterApproval';
import getMyLeaves from '@salesforce/apex/LeaveRequestController.getMyLeaves';
import calculateLeaveDays from '@salesforce/apex/LeaveRequestController.calculateDays';
import upsertDraftBreak from '@salesforce/apex/BreakRequestController.upsertDraft';
import submitBreak from '@salesforce/apex/BreakRequestController.submit';
import cancelBreak from '@salesforce/apex/BreakRequestController.cancel';
import getMyBreaks from '@salesforce/apex/BreakRequestController.getMyBreaks';
import getMyBreaksHistory from '@salesforce/apex/BreakRequestController.getMyBreaksHistory';
import getMyBreaksRange from '@salesforce/apex/BreakRequestController.getMyBreaksRange';
import getActiveBreak from '@salesforce/apex/BreakRequestController.getActiveBreak';
import getServicePresenceStatusId from '@salesforce/apex/OmniPresenceHelper.getServicePresenceStatusId';
import getMyYearlyBalances from '@salesforce/apex/LeaveBalanceController.getMyYearlyBalances';
import getMyBalance from '@salesforce/apex/LeaveBalanceController.getMyBalance';
import clockIn from '@salesforce/apex/WorkTimeController.clockIn';
import clockOut from '@salesforce/apex/WorkTimeController.clockOut';
import getTodayWorkTime from '@salesforce/apex/WorkTimeController.getTodayWorkTime';
import { refreshApex } from '@salesforce/apex';

export default class UtilityRequest extends NavigationMixin(LightningElement) {
    @api height;
    @api width;

    @track selectedTab = 'break';
    @track leaveRequestId;
    @track breakRequestId;
    @track leaveError;
    @track breakError;
    @track leaveDays;
    @track breakDuration;
    @track leaveHistory = [];
    @track breakHistory = [];
    @track historySubTab = 'leave';
    @track isLoadingHistory = false;
    @track currentMonth = new Date().getMonth();
    @track currentYear = new Date().getFullYear();
    @track calendarDays = [];
    @track isLoadingCalendar = false;
    @track calendarLeaves = [];
    @track calendarBreaks = [];
    @track showBalanceModal = false;
    @track yearlyBalances = [];
    @track isLoadingBalance = false;
    @track hasMoreLeaveHistory = false;
    @track hasMoreBreakHistory = false;
    @track showBreakTimer = false;
    @track breakTimerSeconds = 0;
    @track onBreakId; // Omni-Channel OnBreak 상태 Id (15자리)
    @track availableChatId; // Omni-Channel Available/OK 상태 Id (15자리)
    @track lastOmniStatus = null; // 마지막으로 설정한 Omni 상태 (중복 호출 방지)
    lastStatusChangeTimestamp = 0; // 마지막 상태 변경 시도 시간 (디바운싱용)
    breakTimerInterval = null;
    breakStatusCheckInterval = null; // 활성 휴식 상태 확인용 인터벌

    leaveFormData = {};
    breakFormData = {};
    @track currentDraftLeave = null; // 현재 초안 정보
    @track isOnDuty = false; // 근무 중 상태
    @track currentWorkTimeId = null; // 현재 근무 시간 레코드 ID
    @track workStartTime = null; // 출근 시간
    @track workEndTime = null; // 퇴근 시간

    get workTimeLabelClass() {
        return `work-time-label ${this.isOnDuty ? 'work-time-active' : 'work-time-inactive'}`;
    }

    get workTimeCardClass() {
        return `work-time-card ${this.isOnDuty ? 'work-time-card-active' : 'work-time-card-inactive'}`;
    }

    get formattedWorkStartTime() {
        if (!this.workStartTime) return '';
        return this.formatTime(this.workStartTime);
    }

    get formattedWorkEndTime() {
        if (!this.workEndTime) return '';
        return this.formatTime(this.workEndTime);
    }
    wiredLeaveHistory;
    wiredBreakHistory;
    wiredCalendarLeaves;
    wiredCalendarBreaks;

    get isLeaveTab() {
        return this.selectedTab === 'leave';
    }

    get isBreakTab() {
        return this.selectedTab === 'break';
    }

    get isHistoryTab() {
        return this.selectedTab === 'history';
    }

    get isCalendarTab() {
        return this.selectedTab === 'calendar';
    }

    // 상단 탭 링크용 클래스 (현재 탭 강조)
    get leaveTabClass() {
        return `slds-tabs_default__link tab-link ${this.isLeaveTab ? 'tab-active' : ''}`;
    }

    get breakTabClass() {
        return `slds-tabs_default__link tab-link ${this.isBreakTab ? 'tab-active' : ''}`;
    }

    get historyTabClass() {
        return `slds-tabs_default__link tab-link ${this.isHistoryTab ? 'tab-active' : ''}`;
    }

    get calendarTabClass() {
        return `slds-tabs_default__link tab-link ${this.isCalendarTab ? 'tab-active' : ''}`;
    }

    get hasYearlyBalances() {
        return this.yearlyBalances && this.yearlyBalances.length > 0;
    }

    get isLeaveHistory() {
        return this.historySubTab === 'leave';
    }

    get isBreakHistory() {
        return this.historySubTab === 'break';
    }

    get leaveHistoryTabClass() {
        return this.historySubTab === 'leave' 
            ? 'history-tab-link active' 
            : 'history-tab-link';
    }

    get breakHistoryTabClass() {
        return this.historySubTab === 'break' 
            ? 'history-tab-link active' 
            : 'history-tab-link';
    }

    get hasLeaveHistory() {
        return this.leaveHistory && this.leaveHistory.length > 0;
    }

    get hasBreakHistory() {
        return this.breakHistory && this.breakHistory.length > 0;
    }

    get hasDraftLeave() {
        return this.currentDraftLeave !== null;
    }

    get draftButtonLabel() {
        return this.hasDraftLeave ? '초안 수정' : '초안 저장';
    }

    handleTabClick(event) {
        event.preventDefault();
        const tabId = event.currentTarget?.dataset?.tab;
        if (tabId && tabId !== this.selectedTab) {
            // 탭 변경 시 계산된 일수 및 폼 데이터 초기화
            this.leaveDays = null;
            this.breakDuration = null;
            
            // 휴가 신청 탭으로 이동할 때
            if (tabId === 'leave') {
                this.leaveError = undefined;
                // 초안이 있으면 자동으로 로드
                if (this.currentDraftLeave && !this.leaveRequestId) {
                    this.loadDraftToForm(this.currentDraftLeave);
                } else if (!this.currentDraftLeave) {
                    // 초안이 없으면 폼 데이터 초기화
                    this.leaveFormData = {};
                    this.leaveRequestId = null;
                }
            }
            // 휴식 신청 탭으로 이동할 때
            if (tabId === 'break') {
                this.breakError = undefined;
                // Date 필드에 오늘 날짜 설정
                const today = new Date();
                const todayStr = today.toISOString().split('T')[0]; // YYYY-MM-DD 형식
                this.breakFormData = { Date__c: todayStr };
            }
            
            this.selectedTab = tabId;
            this.leaveError = undefined;
            this.breakError = undefined;
            
            if (this.selectedTab === 'history') {
                this.loadHistory();
            } else if (this.selectedTab === 'calendar') {
                this.loadCalendar();
            }
        }
    }

    handleHistorySubTabChange(event) {
        this.historySubTab = event.currentTarget.dataset.tab;
        this.loadHistory();
    }

    // 휴가 신청 관련
    handleLeaveFieldChange(event) {
        // lightning-input-field의 경우 fieldName을 여러 방법으로 얻을 수 있음
        const fieldName = event.target?.fieldName || 
                         event.target?.getAttribute('field-name') || 
                         event.target?.getAttribute('data-field-name') ||
                         event.detail?.fieldName;
        const value = event.detail?.value;
        
        console.log('handleLeaveFieldChange:', {
            fieldName: fieldName,
            value: value,
            eventTarget: event.target,
            eventDetail: event.detail
        });
        
        if (fieldName) {
            // 값이 비어있거나 null/undefined인 경우 필드를 제거하거나 null로 설정
            if (value === undefined || value === null || value === '') {
                delete this.leaveFormData[fieldName];
                // 날짜 필드인 경우 계산 초기화
                if (fieldName === 'Start_Date__c' || fieldName === 'End_Date__c' || 
                    fieldName === 'Start_Slot__c' || fieldName === 'End_Slot__c') {
                    this.leaveDays = null;
                }
            } else {
                this.leaveFormData[fieldName] = value;
                console.log('Field saved to leaveFormData:', fieldName, '=', value);
            }
        } else {
            console.warn('Field name missing:', { fieldName, value });
        }
        
        // 필드 변경 후 검증 및 일수 재계산
        // Reason 필드는 일수 계산과 무관하므로 제외
        this.validateLeaveForm();
        if (fieldName !== 'Reason__c') {
            this.calculateLeaveDays();
        }
    }

    validateLeaveForm() {
        // 에러 메시지 초기화
        this.leaveError = null;
        
        const startDate = this.leaveFormData.Start_Date__c;
        const startSlot = this.leaveFormData.Start_Slot__c;
        const endDate = this.leaveFormData.End_Date__c;
        const endSlot = this.leaveFormData.End_Slot__c;
        
        // 날짜가 모두 입력되었을 때만 검증
        if (startDate && endDate) {
            const parsedStartDate = this.parseDate(startDate);
            const parsedEndDate = this.parseDate(endDate);
            
            if (parsedStartDate && parsedEndDate) {
                // 종료일이 시작일보다 이전인지 확인
                if (parsedEndDate < parsedStartDate) {
                    this.leaveError = '종료일은 시작일보다 이전일 수 없습니다.';
                    return false;
                }
                
                // 같은 날짜인 경우 슬롯 검증
                if (parsedStartDate.getTime() === parsedEndDate.getTime()) {
                    if (startSlot && endSlot) {
                        // 같은 날짜에서 AM -> PM은 가능하지만, PM -> AM은 불가능
                        if (startSlot === 'PM' && endSlot === 'AM') {
                            this.leaveError = '같은 날짜에서는 시작 시간이 종료 시간보다 늦을 수 없습니다.';
                            return false;
                        }
                    }
                }
            }
        }
        
        // 모든 검증 통과
        return true;
    }

    calculateLeaveDays() {
        // leaveFormData가 초기화되지 않았으면 초기화
        if (!this.leaveFormData) {
            this.leaveFormData = {};
            this.leaveDays = null;
            return;
        }
        
        // 검증 실패 시 계산하지 않음
        if (this.leaveError) {
            this.leaveDays = null;
            return;
        }
        
        // 날짜와 슬롯이 모두 입력되었을 때만 계산
        const startDate = this.leaveFormData.Start_Date__c;
        const startSlot = this.leaveFormData.Start_Slot__c;
        const endDate = this.leaveFormData.End_Date__c;
        const endSlot = this.leaveFormData.End_Slot__c;
        
        // 필수 필드가 하나라도 비어있으면 계산하지 않음
        if (!startDate || !startSlot || !endDate || !endSlot) {
            this.leaveDays = null;
            return;
        }
        
        if (startDate && startSlot && endDate && endSlot) {
            // 날짜 파싱
            const parsedStartDate = this.parseDate(startDate);
            const parsedEndDate = this.parseDate(endDate);
            
            if (parsedStartDate && parsedEndDate) {
                // 검증: 종료일이 시작일보다 이전이면 계산하지 않음
                if (parsedEndDate < parsedStartDate) {
                    this.leaveDays = null;
                    return;
                }
                
                this.leaveDays = '계산 중...';
                
                // 서버에서 일수 계산
                calculateLeaveDays({
                    startDate: parsedStartDate,
                    startSlot: startSlot,
                    endDate: parsedEndDate,
                    endSlot: endSlot
                })
                .then(days => {
                    // 계산 결과가 유효한 경우에만 업데이트
                    if (days !== null && days !== undefined) {
                        this.leaveDays = days;
                    } else {
                        this.leaveDays = null;
                    }
                })
                .catch(error => {
                    console.error('일수 계산 오류:', error);
                    this.leaveDays = null;
                });
            } else {
                // 날짜 파싱 실패
                this.leaveDays = null;
            }
        } else {
            // 필수 필드가 하나라도 비어있으면 계산 결과 초기화
            this.leaveDays = null;
        }
    }

    parseDate(dateValue) {
        if (!dateValue) return null;
        
        // 이미 Date 객체인 경우
        if (dateValue instanceof Date) {
            // 유효한 날짜인지 확인
            if (isNaN(dateValue.getTime())) return null;
            return dateValue;
        }
        
        // 문자열인 경우
        if (typeof dateValue === 'string') {
            // 빈 문자열 체크
            if (dateValue.trim() === '') return null;
            
            // "2026-01-20" 형식
            const parts = dateValue.split('-');
            if (parts.length === 3) {
                const year = parseInt(parts[0], 10);
                const month = parseInt(parts[1], 10) - 1;
                const day = parseInt(parts[2], 10);
                
                // 유효한 숫자인지 확인
                if (isNaN(year) || isNaN(month) || isNaN(day)) return null;
                
                const date = new Date(year, month, day);
                // 유효한 날짜인지 확인
                if (isNaN(date.getTime())) return null;
                
                return date;
            }
            
            // 다른 형식 시도 (ISO 형식 등)
            const date = new Date(dateValue);
            if (!isNaN(date.getTime())) {
                return date;
            }
        }
        
        return null;
    }

    // 연도별 휴가 일수 조회 모달 열기
    handleOpenBalance() {
        this.showBalanceModal = true;
        this.isLoadingBalance = true;
        getMyYearlyBalances()
            .then(data => {
                this.yearlyBalances = data || [];
            })
            .catch(error => {
                this.yearlyBalances = [];
                this.showToast('오류', this.getErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoadingBalance = false;
            });
    }

    handleCloseBalance() {
        this.showBalanceModal = false;
    }

    handleLeaveFormSubmit(event) {
        // 폼의 기본 제출을 막음 (우리는 커스텀 로직을 사용)
        event.preventDefault();
        event.stopPropagation();
        return false;
    }

    handleLeaveSaveDraft(event) {
        event.preventDefault();
        event.stopPropagation();
        
        // 초안이 있으면 수정 모드로 전환
        if (this.hasDraftLeave && !this.leaveRequestId) {
            this.loadDraftToForm(this.currentDraftLeave);
        }
        
        this.saveDraftLeave();
    }

    loadDraftToForm(draft) {
        if (!draft) return;
        
        // 초안 데이터를 폼에 로드
        this.leaveRequestId = draft.Id;
        this.leaveFormData = {
            Start_Date__c: draft.Start_Date__c,
            Start_Slot__c: draft.Start_Slot__c,
            End_Date__c: draft.End_Date__c,
            End_Slot__c: draft.End_Slot__c,
            Leave_Type__c: draft.Leave_Type__c,
            Reason__c: draft.Reason__c
        };
        this.leaveDays = draft.Days__c;
        
        // 폼 필드 업데이트를 위해 약간의 지연 후 계산
        setTimeout(() => {
            this.calculateLeaveDays();
        }, 100);
    }

    saveDraftLeave() {
        // 초안 저장 전 검증 (에러는 표시하지 않고 검증만 수행)
        const isValid = this.validateLeaveForm();
        if (!isValid && this.leaveError) {
            // 검증 실패 시에도 초안 저장은 진행 (사용자가 나중에 수정할 수 있도록)
            console.warn('Validation warning (draft can still be saved):', this.leaveError);
        }
        
        // leaveFormData를 직접 사용 (이미 onchange 이벤트로 모든 값이 저장되어 있음)
        const draft = {
            Id: this.leaveRequestId || null,
            Start_Date__c: this.leaveFormData.Start_Date__c,
            Start_Slot__c: this.leaveFormData.Start_Slot__c,
            End_Date__c: this.leaveFormData.End_Date__c,
            End_Slot__c: this.leaveFormData.End_Slot__c,
            Leave_Type__c: this.leaveFormData.Leave_Type__c,
            Reason__c: this.leaveFormData.Reason__c || null,
            Status__c: 'Draft'
        };

        console.log('Draft data to save:', draft);
        console.log('leaveFormData:', JSON.stringify(this.leaveFormData, null, 2));

        // 필수 필드 검증
        if (!draft.Start_Date__c || !draft.Start_Slot__c || !draft.End_Date__c || !draft.End_Slot__c || !draft.Leave_Type__c) {
            const missingFields = [];
            if (!draft.Start_Date__c) missingFields.push('Start Date');
            if (!draft.Start_Slot__c) missingFields.push('Start Slot');
            if (!draft.End_Date__c) missingFields.push('End Date');
            if (!draft.End_Slot__c) missingFields.push('End Slot');
            if (!draft.Leave_Type__c) missingFields.push('Leave Type');
            
            this.leaveError = `필수 필드를 모두 입력해주세요. (누락: ${missingFields.join(', ')})`;
            this.showToast('오류', `필수 필드를 모두 입력해주세요. (누락: ${missingFields.join(', ')})`, 'error');
            return Promise.reject(new Error('Required fields missing: ' + missingFields.join(', ')));
        }

        return upsertDraftLeave({ draft })
            .then(result => {
                console.log('Draft saved successfully:', result);
                this.leaveRequestId = result.Id;
                this.leaveDays = result.Days__c;
                
                // 초안 저장 후 leaveFormData를 서버에서 반환된 값으로 업데이트
                // 폼이 리셋되어도 leaveFormData는 유지됨
                if (result) {
                    this.leaveFormData = {
                        Start_Date__c: result.Start_Date__c,
                        Start_Slot__c: result.Start_Slot__c,
                        End_Date__c: result.End_Date__c,
                        End_Slot__c: result.End_Slot__c,
                        Leave_Type__c: result.Leave_Type__c,
                        Reason__c: result.Reason__c
                    };
                    
                    // currentDraftLeave 업데이트
                    this.currentDraftLeave = result;
                }
                
                // silent 모드가 아닐 때만 메시지 표시
                if (!this._saveDraftSilent) {
                    const message = this.hasDraftLeave ? '초안이 수정되었습니다.' : '초안이 저장되었습니다.';
                    this.showToast('성공', message, 'success');
                }
                
                // 내역 새로고침
                refreshApex(this.wiredLeaveHistory);
                
                return result;
            })
            .catch(error => {
                console.error('Error saving draft:', error);
                this.leaveError = this.getErrorMessage(error);
                this.showToast('오류', this.getErrorMessage(error), 'error');
                throw error;
            });
    }

    handleLeaveSubmit(event) {
        event.preventDefault();
        event.stopPropagation();
        
        console.log('handleLeaveSubmit called', {
            leaveRequestId: this.leaveRequestId,
            leaveFormData: this.leaveFormData
        });
        
        // 제출 전 검증
        if (!this.validateLeaveForm()) {
            this.showToast('오류', this.leaveError, 'error');
            return;
        }
        
        // 먼저 초안 저장 후 제출
        if (!this.leaveRequestId) {
            console.log('No leaveRequestId, saving draft first...');
            this._saveDraftSilent = true; // 제출 시에는 메시지 표시 안 함
            this.saveDraftLeave()
                .then((result) => {
                    console.log('Draft saved successfully, result:', result);
                    console.log('leaveRequestId after save:', this.leaveRequestId);
                    if (this.leaveRequestId) {
                        console.log('Calling submitLeaveRequest...');
                        // 초안 저장 후 잠시 대기하여 상태가 안정화되도록 함
                        setTimeout(() => {
                            this._saveDraftSilent = false; // 플래그 초기화
                            this.submitLeaveRequest();
                        }, 100);
                    } else {
                        this._saveDraftSilent = false; // 플래그 초기화
                        console.error('leaveRequestId is still null after save');
                        this.showToast('오류', '초안 저장 후 레코드 ID를 가져올 수 없습니다.', 'error');
                    }
                })
                .catch(error => {
                    this._saveDraftSilent = false; // 플래그 초기화
                    console.error('Error saving draft in handleLeaveSubmit:', error);
                    // 에러는 이미 saveDraftLeave에서 처리됨
                });
        } else {
            console.log('leaveRequestId exists, calling submitLeaveRequest directly...');
            // 기존 초안이 있는 경우, 최신 상태를 다시 조회하여 확인
            this.submitLeaveRequest();
        }
    }

    submitLeaveRequest() {
        if (!this.leaveRequestId) {
            console.error('submitLeaveRequest: leaveRequestId is null');
            this.leaveError = '레코드 ID가 없습니다. 먼저 초안을 저장해주세요.';
            this.showToast('오류', '먼저 초안을 저장해주세요.', 'error');
            return;
        }

        // 휴가 일수 검증: 잔여 일수 확인
        const startDate = this.leaveFormData.Start_Date__c;
        const requestedDays = this.leaveDays;
        
        if (!startDate || !requestedDays) {
            this.leaveError = '휴가 일수를 확인할 수 없습니다.';
            this.showToast('오류', this.leaveError, 'error');
            return;
        }

        // 시작 날짜의 연도 확인
        const parsedStartDate = this.parseDate(startDate);
        if (!parsedStartDate) {
            this.leaveError = '시작 날짜를 확인할 수 없습니다.';
            this.showToast('오류', this.leaveError, 'error');
            return;
        }

        const year = parsedStartDate.getFullYear();
        const daysNum = parseFloat(requestedDays);

        // 잔여 휴가 일수 확인
        getMyBalance({ yearParam: year })
            .then(balance => {
                // 부여 받은 일수가 없으면 신청 불가
                if (!balance || balance.totalDays === null || balance.totalDays === 0) {
                    this.leaveError = '부여 받은 휴가 일수가 없습니다.';
                    this.showToast('오류', this.leaveError, 'error');
                    return;
                }

                // 잔여 일수 확인
                const remainingDays = balance.remainingDays || 0;
                if (remainingDays < daysNum) {
                    this.leaveError = `잔여 휴가 일수(${remainingDays}일)가 부족합니다. (신청 일수: ${daysNum}일)`;
                    this.showToast('오류', this.leaveError, 'error');
                    return;
                }

                // 검증 통과 시 제출 진행
                console.log('Submitting leave request:', this.leaveRequestId);
                
                // 제출과 동시에 폼 초기화 (제출 요청 직후)
                const requestIdToSubmit = this.leaveRequestId;
                this.leaveRequestId = null;
                this.leaveFormData = {};
                this.leaveDays = null;
                this.leaveError = null;
                this.currentDraftLeave = null; // 초안 초기화
                this.resetLeaveForm();
                
                // 제출 요청 (submitLeave는 void를 반환하므로 에러가 없으면 성공)
                return submitLeave({ requestId: requestIdToSubmit });
            })
            .then(() => {
                // 제출 성공 (submitLeave는 void를 반환하므로 에러가 없으면 성공)
                console.log('Leave request submitted successfully');
                
                // 성공 메시지 표시
                const successEvt = new ShowToastEvent({
                    title: '성공',
                    message: '휴가 신청이 제출되었습니다.',
                    variant: 'success',
                    mode: 'dismissable' // 자동으로 사라지는 모드
                });
                this.dispatchEvent(successEvt);
                
                // 내역 새로고침
                this.loadHistory();
            })
            .catch(error => {
                console.error('Error in submitLeaveRequest:', error);
                const errorMessage = this.getErrorMessage(error);
                
                // "Only Draft/Rejected can be submitted." 오류가 발생한 경우
                // 실제로는 제출이 성공했을 수 있으므로 내역을 새로고침하여 확인
                if (errorMessage && errorMessage.includes('Only Draft/Rejected can be submitted')) {
                    // 내역을 새로고침하여 실제 상태 확인
                    if (this.wiredLeaveHistory) {
                        refreshApex(this.wiredLeaveHistory);
                    }
                    // 잠시 후 다시 확인 (제출이 성공했을 수 있음)
                    setTimeout(() => {
                        if (this.wiredLeaveHistory) {
                            refreshApex(this.wiredLeaveHistory);
                        }
                    }, 1000);
                    
                    // 오류 메시지는 표시하되, 사용자에게 내역을 확인하도록 안내
                    this.leaveError = '제출 중 오류가 발생했습니다. 내역을 확인해주세요.';
                    this.showToast('알림', '제출 중 오류가 발생했지만, 내역을 확인해주세요. 실제로 제출되었을 수 있습니다.', 'warning');
                } else {
                    this.leaveError = errorMessage;
                    this.showToast('오류', errorMessage, 'error');
                }
            });
    }

    handleLeaveCancel() {
        if (!this.leaveRequestId) return;
        cancelLeaveBeforeApproval({ requestId: this.leaveRequestId })
            .then(() => {
                this.showToast('성공', '휴가 신청이 취소되었습니다.', 'success');
                this.leaveRequestId = null;
                this.leaveFormData = {};
                this.leaveDays = null; // 계산된 일수 초기화
                this.leaveError = null;
                this.currentDraftLeave = null; // 초안 초기화
                this.resetLeaveForm();
                // 내역 새로고침
                refreshApex(this.wiredLeaveHistory);
            })
            .catch(error => {
                this.leaveError = this.getErrorMessage(error);
            });
    }

    handleLeaveSuccess(event) {
        this.leaveRequestId = event.detail.id;
        // 폼이 성공적으로 저장된 후에도 leaveFormData는 유지되어야 함
        // handleLeaveSuccess는 lightning-record-edit-form의 onsuccess 이벤트에서 호출됨
        // 이 시점에서 폼 필드의 현재 값을 다시 읽어서 leaveFormData에 저장
        // 하지만 이미 saveDraftLeave에서 업데이트했으므로 여기서는 ID만 설정
    }

    resetLeaveForm() {
        const form = this.template.querySelector('lightning-record-edit-form[data-form="leave"]');
        // lightning-record-edit-form에 reset 메서드가 없는 환경에서도 오류가 나지 않도록 방어 코드 추가
        try {
            if (form && typeof form.reset === 'function') {
                form.reset();
            }
        } catch (e) {
            // reset 실패는 치명적이지 않으므로 콘솔에만 남기고 무시
            // (필드 값은 this.leaveFormData 초기화 및 UI 재렌더링으로 대부분 정리됨)
            // eslint-disable-next-line no-console
            console.warn('resetLeaveForm error (무시 가능):', e);
        }
    }

    handleLeaveReset() {
        // 휴가 신청 폼만 초기화
        // record-id를 먼저 null로 설정하여 폼을 새 레코드 모드로 전환
        this.leaveRequestId = null;
        
        // 휴가 신청 데이터만 초기화
        this.leaveFormData = {};
        this.leaveDays = null;
        this.leaveError = null; // 에러 메시지도 초기화
        
        // 휴가 신청 폼만 초기화 (data-form="leave"로 명확하게 지정)
        const leaveForm = this.template.querySelector('lightning-record-edit-form[data-form="leave"]');
        if (leaveForm) {
            try {
                // 폼 리셋 시도
                if (typeof leaveForm.reset === 'function') {
                    leaveForm.reset();
                }
                
                // 휴가 신청 폼의 필드만 초기화
                const leaveFields = leaveForm.querySelectorAll('lightning-input-field');
                leaveFields.forEach(field => {
                    try {
                        if (field.value !== undefined) {
                            field.value = null;
                        }
                    } catch (e) {
                        // 필드 값 설정 실패는 무시
                    }
                });
            } catch (e) {
                console.warn('Leave form reset error:', e);
            }
        }
        
        this.showToast('알림', '휴가 신청 폼이 초기화되었습니다.', 'info');
    }

    // 휴식 신청 관련
    handleBreakDateChange(event) {
        // Date 필드는 항상 오늘 날짜로 고정 (수정 불가)
        const today = new Date();
        const todayStr = today.toISOString().split('T')[0];
        if (!this.breakFormData) {
            this.breakFormData = {};
        }
        this.breakFormData.Date__c = todayStr;
        
        // 사용자가 날짜를 변경하려고 하면 항상 오늘 날짜로 되돌림
        const dateField = this.template.querySelector('lightning-input-field[field-name="Date__c"]');
        if (dateField) {
            const currentValue = event.detail?.value || dateField.value;
            if (currentValue && currentValue !== todayStr) {
                // 오늘 날짜가 아니면 오늘 날짜로 강제 설정
                this.showToast('알림', 'Date 필드는 오늘 날짜로만 설정할 수 있습니다.', 'info');
                setTimeout(() => {
                    dateField.value = todayStr;
                    // breakFormData도 업데이트
                    this.breakFormData.Date__c = todayStr;
                }, 100);
            } else {
                // 이미 오늘 날짜이면 그대로 유지
                this.breakFormData.Date__c = todayStr;
            }
        }
        
        this.calculateBreakDuration();
    }

    handleBreakFieldChange(event) {
        // lightning-input-field의 경우 fieldName을 다르게 가져올 수 있음
        const fieldName = event.target.fieldName || event.target.dataset.fieldName || event.target.dataset.field;
        const value = event.detail.value;
        
        // breakFormData 초기화 확인
        if (!this.breakFormData) {
            this.breakFormData = {};
        }
        
        // fieldName이 없으면 Reason__c로 가정 (Reason 필드만 이 핸들러 사용)
        const actualFieldName = fieldName || 'Reason__c';
        this.breakFormData[actualFieldName] = value;
        this.calculateBreakDuration();
    }

    handleBreakTypeChange(event) {
        this.breakFormData.Break_Type__c = event.detail.value;
        // 타입에 따라 기본 시간 설정
        this.setDefaultBreakTime();
    }

    setDefaultBreakTime() {
        const type = this.breakFormData.Break_Type__c;
        if (type === 'Morning Break') {
            // 오전 브레이크: 10분 (예: 10:00 - 10:10)
            this.breakFormData.Start_Time__c = '10:00:00.000Z';
            this.breakFormData.End_Time__c = '10:10:00.000Z';
        } else if (type === 'Lunch') {
            // 점심: 1시간 (예: 12:00 - 13:00)
            this.breakFormData.Start_Time__c = '12:00:00.000Z';
            this.breakFormData.End_Time__c = '13:00:00.000Z';
        } else if (type === 'Afternoon Break') {
            // 오후 브레이크: 10분 (예: 15:00 - 15:10)
            this.breakFormData.Start_Time__c = '15:00:00.000Z';
            this.breakFormData.End_Time__c = '15:10:00.000Z';
        }
    }

    calculateBreakDuration() {
        if (this.breakFormData.Start_Time__c && this.breakFormData.End_Time__c) {
            // 실제 계산은 서버에서
            this.breakDuration = '계산 중...';
        }
    }

    // 현재 시간을 Apex Time 형식으로 변환 (HH:mm:ss.SSSZ)
    formatTimeForApex(date) {
        const hours = date.getHours();
        const minutes = date.getMinutes();
        const seconds = date.getSeconds();
        const milliseconds = date.getMilliseconds();
        // UTC 시간으로 변환 (Salesforce Time 필드는 UTC 기준)
        const utcHours = hours < 10 ? '0' + hours : hours;
        const utcMinutes = minutes < 10 ? '0' + minutes : minutes;
        const utcSeconds = seconds < 10 ? '0' + seconds : seconds;
        const utcMs = milliseconds < 10 ? '00' + milliseconds : milliseconds < 100 ? '0' + milliseconds : milliseconds;
        return `${utcHours}:${utcMinutes}:${utcSeconds}.${utcMs}Z`;
    }

    handleBreakSaveDraft(event) {
        event.preventDefault();
        const form = this.template.querySelector('lightning-record-edit-form[data-form="break"]');
        if (!form) return;
        
        const fields = form.getRecord();
        const draft = {
            Id: this.breakRequestId,
            Date__c: fields.fields.Date__c?.value,
            Break_Type__c: fields.fields.Break_Type__c?.value,
            Start_Time__c: fields.fields.Start_Time__c?.value,
            End_Time__c: fields.fields.End_Time__c?.value,
            Reason__c: fields.fields.Reason__c?.value,
            Status__c: 'Draft'
        };

        upsertDraftBreak({ draft })
            .then(result => {
                this.breakRequestId = result.Id;
                this.breakDuration = result.Duration_Minutes__c + '분';
                this.showToast('성공', '초안이 저장되었습니다.', 'success');
            })
            .catch(error => {
                this.breakError = this.getErrorMessage(error);
            });
    }

    handleBreakSubmit(event) {
        event.preventDefault();
        // 초안 저장 없이 바로 제출 (자동 승인)
        this.submitBreakRequestDirectly();
    }

    submitBreakRequestDirectly() {
        // 필수 필드 검증 (Date, Break_Type만 필수)
        if (!this.breakFormData.Date__c || !this.breakFormData.Break_Type__c) {
            const missingFields = [];
            if (!this.breakFormData.Date__c) missingFields.push('Date');
            if (!this.breakFormData.Break_Type__c) missingFields.push('Break Type');
            
            this.breakError = `필수 필드를 모두 입력해주세요. (누락: ${missingFields.join(', ')})`;
            this.showToast('오류', this.breakError, 'error');
            return;
        }

        // Date 필드 검증: 오늘 날짜만 허용
        const today = new Date();
        const todayStr = today.toISOString().split('T')[0];
        const selectedDate = this.breakFormData.Date__c;
        
        if (selectedDate !== todayStr) {
            this.breakError = 'Date 필드는 오늘 날짜만 신청 가능합니다.';
            this.showToast('오류', this.breakError, 'error');
            return;
        }

        // Lunch 타입인 경우: 현재 시간이 12:30을 넘었는지 확인
        if (this.breakFormData.Break_Type__c === 'Lunch') {
            const now = new Date();
            const currentHour = now.getHours();
            const currentMinute = now.getMinutes();
            const currentMinutes = currentHour * 60 + currentMinute;
            const lunchEndMinutes = 12 * 60 + 30; // 12:30
            
            if (currentMinutes > lunchEndMinutes) {
                this.breakError = 'Lunch는 11시 30분부터 12시 30분 사이에만 신청 가능합니다. 현재 시간이 12시 30분을 넘었습니다.';
                this.showToast('오류', this.breakError, 'error');
                return;
            }
        }

        // Break Type을 미리 저장 (제출 후 폼 리셋 전에 사용)
        const submittedBreakType = this.breakFormData.Break_Type__c;
        
        // 폼 데이터를 직접 사용하여 제출 (시간은 Apex에서 자동 설정)
        // Date는 항상 오늘 날짜로 고정
        const breakData = {
            Date__c: todayStr, // 항상 오늘 날짜
            Break_Type__c: this.breakFormData.Break_Type__c,
            Start_Time__c: null, // Apex에서 제출 시점에 자동 설정
            End_Time__c: null, // Apex에서 제출 시점에 자동 설정
            Reason__c: this.breakFormData.Reason__c || null,
            Status__c: 'Draft' // 제출 시 자동 승인되므로 Draft로 시작
        };

        // 초안 저장 없이 바로 제출
        upsertDraftBreak({ draft: breakData })
            .then(result => {
                this.breakRequestId = result.Id;
                // 바로 제출 (자동 승인)
                return submitBreak({ requestId: this.breakRequestId });
            })
            .catch(error => {
                // 오전/오후 제한 검증 오류 처리
                const errorMessage = this.getErrorMessage(error);
                if (errorMessage && (errorMessage.includes('오전') || errorMessage.includes('오후'))) {
                    this.breakError = errorMessage;
                    this.showToast('오류', errorMessage, 'error');
                    return Promise.reject(error); // 체인 중단
                } else {
                    throw error;
                }
            })
            .then(submittedBreak => {
                this.showToast('성공', '휴식 신청이 제출되어 자동 승인되었습니다.', 'success');
                this.breakRequestId = null;
                // Date는 오늘 날짜로 유지
                const today = new Date();
                const todayStr = today.toISOString().split('T')[0];
                this.breakFormData = { Date__c: todayStr };
                this.breakDuration = null;
                this.resetBreakForm();
                // 내역 새로고침
                this.loadHistory();
                // Morning Break, Afternoon Break, 또는 Lunch일 때 타이머 시작
                if (submittedBreakType === 'Morning Break' || submittedBreakType === 'Afternoon Break') {
                    // Morning Break 또는 Afternoon Break: 무조건 10분(600초)
                    this.startBreakTimer(10 * 60);
                } else if (submittedBreakType === 'Lunch') {
                    // Lunch: 1시간(3600초) - 실제 종료 시간에 맞춰 조정
                    // Lunch의 경우 서버에서 계산된 시간을 사용하되, 최대 1시간
                    this.startBreakTimer(60 * 60);
                }
            })
            .catch(error => {
                console.error('Error submitting break request:', error);
                this.breakError = this.getErrorMessage(error);
                this.showToast('오류', this.getErrorMessage(error), 'error');
            });
    }

    submitBreakRequest() {
        submitBreak({ requestId: this.breakRequestId })
            .then(() => {
                this.showToast('성공', '휴식 신청이 제출되어 자동 승인되었습니다.', 'success');
                this.breakRequestId = null;
                this.breakFormData = {};
                this.resetBreakForm();
            })
            .catch(error => {
                this.breakError = this.getErrorMessage(error);
            });
    }

    handleBreakCancel() {
        if (!this.breakRequestId) return;
        cancelBreak({ requestId: this.breakRequestId })
            .then(() => {
                this.showToast('성공', '휴식 신청이 취소되었습니다.', 'success');
                this.breakRequestId = null;
                this.breakError = null; // 에러 메시지 초기화
                this.resetBreakForm();
            })
            .catch(error => {
                const errorMessage = this.getErrorMessage(error);
                this.breakError = errorMessage;
                this.showToast('오류', errorMessage, 'error');
            });
    }

    handleBreakSuccess(event) {
        this.breakRequestId = event.detail.id;
    }

    resetBreakForm() {
        const form = this.template.querySelector('lightning-record-edit-form[data-form="break"]');
        try {
            if (form && typeof form.reset === 'function') {
                form.reset();
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('resetBreakForm error (무시 가능):', e);
        }
    }

    handleBreakReset() {
        // 휴식 신청 폼만 초기화 (Date 필드 제외)
        // record-id를 먼저 null로 설정하여 폼을 새 레코드 모드로 전환
        this.breakRequestId = null;
        
        // 휴식 신청 데이터만 초기화 (Date는 오늘 날짜로 유지)
        const today = new Date();
        const todayStr = today.toISOString().split('T')[0];
        this.breakFormData = { Date__c: todayStr };
        this.breakDuration = null;
        this.breakError = null;
        
        // 휴식 신청 폼만 초기화 (data-form="break"로 명확하게 지정)
        const breakForm = this.template.querySelector('lightning-record-edit-form[data-form="break"]');
        if (breakForm) {
            try {
                // 폼 리셋 시도
                if (typeof breakForm.reset === 'function') {
                    breakForm.reset();
                }
                
                // 휴식 신청 폼의 필드만 초기화 (Date 필드 제외)
                const breakFields = breakForm.querySelectorAll('lightning-input-field');
                breakFields.forEach(field => {
                    try {
                        // Date 필드는 오늘 날짜로 유지
                        if (field.fieldName === 'Date__c') {
                            // Date 필드는 오늘 날짜로 설정
                            setTimeout(() => {
                                if (field.value !== todayStr) {
                                    field.value = todayStr;
                                }
                            }, 100);
                        } else {
                            // 다른 필드는 null로 설정
                            if (field.value !== undefined) {
                                field.value = null;
                            }
                        }
                    } catch (e) {
                        // 필드 값 설정 실패는 무시
                    }
                });
            } catch (e) {
                console.warn('Break form reset error:', e);
            }
        }
        
        // Date 필드를 명시적으로 오늘 날짜로 설정 (비동기 처리)
        setTimeout(() => {
            const dateField = breakForm ? breakForm.querySelector('lightning-input-field[field-name="Date__c"]') : null;
            if (dateField && dateField.value !== todayStr) {
                dateField.value = todayStr;
                this.breakFormData = { Date__c: todayStr };
            }
        }, 200);
        
        this.showToast('알림', '휴식 신청 폼이 초기화되었습니다.', 'info');
    }

    // 내역 조회
    @wire(getMyLeaves, { startDate: '$historyStartDate', endDate: '$historyEndDate' })
    wiredLeaveHistory(result) {
        this.wiredLeaveHistory = result;
        if (result.data) {
            const allHistory = this.decorateLeaveHistory(result.data);
            // 최신 6개만 표시
            this.leaveHistory = allHistory.slice(0, 6);
            this.hasMoreLeaveHistory = allHistory.length > 6;
            
            // 초안 찾기 (가장 최근 초안)
            const draft = result.data.find(l => l.Status__c === 'Draft');
            if (draft) {
                this.currentDraftLeave = draft;
                // 초안이 있으면 폼에 로드 (휴가 신청 탭이 활성화되어 있을 때만)
                if (this.isLeaveTab && !this.leaveRequestId) {
                    this.loadDraftToForm(draft);
                }
            } else {
                this.currentDraftLeave = null;
            }
        } else if (result.error) {
            console.error('Error loading leave history', result.error);
            this.leaveHistory = [];
            this.hasMoreLeaveHistory = false;
            this.currentDraftLeave = null;
        }
    }

    @wire(getMyBreaksHistory, { startDate: '$historyStartDate', endDate: '$historyEndDate' })
    wiredBreakHistory(result) {
        this.wiredBreakHistory = result;
        if (result.data) {
            const allHistory = this.decorateBreakHistory(result.data);
            // 최신 6개만 표시
            this.breakHistory = allHistory.slice(0, 6);
            this.hasMoreBreakHistory = allHistory.length > 6;
        } else if (result.error) {
            console.error('Error loading break history', result.error);
            this.breakHistory = [];
            this.hasMoreBreakHistory = false;
        }
    }

    get historyStartDate() {
        const today = new Date();
        today.setMonth(today.getMonth() - 3);
        return this.formatDateForApex(today);
    }

    get historyEndDate() {
        const today = new Date();
        today.setMonth(today.getMonth() + 3);
        return this.formatDateForApex(today);
    }

    get historyTargetDate() {
        return this.formatDateForApex(new Date());
    }

    formatDateForApex(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    loadHistory() {
        this.isLoadingHistory = true;
        if (this.wiredLeaveHistory) {
            refreshApex(this.wiredLeaveHistory);
        }
        if (this.wiredBreakHistory) {
            refreshApex(this.wiredBreakHistory);
        }
        setTimeout(() => {
            this.isLoadingHistory = false;
        }, 500);
    }

    decorateLeaveHistory(leaves) {
        return (leaves || []).map(leave => {
            // Date 필드가 문자열이거나 Date 객체일 수 있음
            let startDate = leave.Start_Date__c;
            let endDate = leave.End_Date__c;
            
            // Date 객체로 변환
            if (startDate) {
                if (typeof startDate === 'string') {
                    // "2026-01-20" 형식
                    const parts = startDate.split('-');
                    if (parts.length === 3) {
                        startDate = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
                    } else {
                        startDate = new Date(startDate);
                    }
                } else if (!(startDate instanceof Date)) {
                    startDate = new Date(startDate);
                }
            }
            
            if (endDate) {
                if (typeof endDate === 'string') {
                    // "2026-01-20" 형식
                    const parts = endDate.split('-');
                    if (parts.length === 3) {
                        endDate = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
                    } else {
                        endDate = new Date(endDate);
                    }
                } else if (!(endDate instanceof Date)) {
                    endDate = new Date(endDate);
                }
            }
            
            // 취소 가능 여부 결정
            let canCancel = leave.Status__c === 'Draft' || leave.Status__c === 'Submitted' || leave.Status__c === 'Approved';
            
            // 상태가 취소 가능한 경우, 시작 시간이 지났는지 확인
            if (canCancel && startDate && leave.Start_Slot__c) {
                const now = new Date();
                const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
                const startDateOnly = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate());
                
                // 시작 날짜가 오늘보다 이전이면 취소 불가
                if (startDateOnly < today) {
                    canCancel = false;
                } 
                // 시작 날짜가 오늘이면 시작 슬롯 시간이 지났는지 확인
                else if (startDateOnly.getTime() === today.getTime()) {
                    const currentHour = now.getHours();
                    const currentMinute = now.getMinutes();
                    
                    if (leave.Start_Slot__c === 'AM') {
                        // AM 슬롯: 오후 12시(정오) 이후면 취소 불가
                        if (currentHour >= 12) {
                            canCancel = false;
                        }
                    } else if (leave.Start_Slot__c === 'PM') {
                        // PM 슬롯: 오후 6시 이후면 취소 불가
                        if (currentHour >= 18) {
                            canCancel = false;
                        }
                    }
                }
            }
            
            return {
                ...leave,
                startDateLabel: (startDate ? this.formatDate(startDate) : '') + ' ' + (leave.Start_Slot__c || ''),
                endDateLabel: (endDate ? this.formatDate(endDate) : '') + ' ' + (leave.End_Slot__c || ''),
                statusLabel: this.getLeaveStatusLabel(leave.Status__c),
                statusClass: this.getLeaveStatusClass(leave.Status__c),
                canCancel: canCancel,
                status: leave.Status__c
            };
        });
    }

    decorateBreakHistory(breaks) {
        return (breaks || []).map(br => {
            // Date 필드가 문자열이거나 Date 객체일 수 있음
            let date = br.Date__c;
            if (typeof date === 'string') {
                date = new Date(date);
            } else if (!(date instanceof Date)) {
                date = new Date(date);
            }
            
            // 취소 가능 여부 결정
            let canCancel = br.Status__c === 'Draft' || br.Status__c === 'Approved';
            
            // 상태가 취소 가능한 경우, 시작 시간이 지났는지 확인
            if (canCancel && date && br.Start_Time__c) {
                const now = new Date();
                const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
                const breakDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
                
                // 시작 날짜가 오늘보다 이전이면 취소 불가
                if (breakDate < today) {
                    canCancel = false;
                } 
                // 시작 날짜가 오늘이면 시작 시간이 지났는지 확인
                else if (breakDate.getTime() === today.getTime()) {
                    // Start_Time__c를 파싱하여 현재 시간과 비교
                    const startTimeStr = br.Start_Time__c;
                    if (startTimeStr) {
                        // Time 형식 파싱 (예: "15:22:00.000Z" 또는 "15:22:00")
                        let startHour = 0;
                        let startMinute = 0;
                        
                        if (typeof startTimeStr === 'string') {
                            // "HH:mm:ss" 또는 "HH:mm:ss.SSSZ" 형식
                            const timeMatch = startTimeStr.match(/(\d{1,2}):(\d{2})/);
                            if (timeMatch) {
                                startHour = parseInt(timeMatch[1], 10);
                                startMinute = parseInt(timeMatch[2], 10);
                            }
                        } else if (startTimeStr.hour !== undefined) {
                            // Time 객체인 경우
                            startHour = startTimeStr.hour;
                            startMinute = startTimeStr.minute || 0;
                        }
                        
                        const currentHour = now.getHours();
                        const currentMinute = now.getMinutes();
                        
                        // 시작 시간이 지났는지 확인
                        if (currentHour > startHour || (currentHour === startHour && currentMinute >= startMinute)) {
                            canCancel = false;
                        }
                    }
                }
            }
            
            return {
                ...br,
                dateLabel: this.formatDate(date),
                timeLabel: this.formatTime(br.Start_Time__c) + ' ~ ' + this.formatTime(br.End_Time__c),
                statusLabel: this.getBreakStatusLabel(br.Status__c),
                statusClass: this.getBreakStatusClass(br.Status__c),
                canCancel: canCancel
            };
        });
    }

    formatDate(date) {
        if (!date) return '';
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    formatTime(timeValue) {
        if (!timeValue) return '';
        
        // Time 필드는 여러 형식으로 올 수 있음
        let timeString = String(timeValue);
        
        // 이미 HH:mm 형식인 경우
        if (/^\d{2}:\d{2}/.test(timeString)) {
            return timeString.substring(0, 5); // HH:mm만 반환
        }
        
        // 숫자로만 된 경우 (밀리초 등) - Time 필드의 내부 표현
        if (/^\d+$/.test(timeString)) {
            // 숫자를 시간으로 변환 시도
            const num = parseInt(timeString, 10);
            // Time 필드는 자정부터의 밀리초일 수 있음
            const totalSeconds = Math.floor(num / 1000);
            const hours = Math.floor(totalSeconds / 3600);
            const minutes = Math.floor((totalSeconds % 3600) / 60);
            const h = String(hours).padStart(2, '0');
            const m = String(minutes).padStart(2, '0');
            return h + ':' + m;
        }
        
        // ISO 형식 (HH:mm:ss.SSSZ 등)
        if (timeString.includes(':')) {
            const parts = timeString.split(':');
            if (parts.length >= 2) {
                const h2 = String(parts[0]).padStart(2, '0');
                const m2 = String(parts[1]).padStart(2, '0');
                return h2 + ':' + m2;
            }
        }
        
        return timeString;
    }

    getLeaveStatusLabel(status) {
        const labels = {
            'Draft': '초안',
            'Submitted': '제출됨',
            'Approved': '승인됨',
            'Rejected': '반려됨',
            'CancelSubmitted': '취소 요청',
            'Cancelled': '취소됨'
        };
        return labels[status] || status;
    }

    getLeaveStatusClass(status) {
        const classes = {
            'Draft': 'status-badge draft',
            'Submitted': 'status-badge submitted',
            'Approved': 'status-badge approved',
            'Rejected': 'status-badge rejected',
            'CancelSubmitted': 'status-badge cancel-submitted',
            'Cancelled': 'status-badge cancelled'
        };
        return classes[status] || 'status-badge';
    }

    getBreakStatusLabel(status) {
        const labels = {
            'Draft': '초안',
            'Approved': '승인됨',
            'Cancelled': '취소됨'
        };
        return labels[status] || status;
    }

    getBreakStatusClass(status) {
        const classes = {
            'Draft': 'status-badge draft',
            'Approved': 'status-badge approved',
            'Cancelled': 'status-badge cancelled'
        };
        return classes[status] || 'status-badge';
    }

    handleLeaveCancelFromHistory(event) {
        const requestId = event.currentTarget.dataset.id;
        
        // 해당 휴가의 상태 확인
        const leave = this.leaveHistory.find(l => l.Id === requestId);
        if (!leave) {
            this.showToast('오류', '휴가 정보를 찾을 수 없습니다.', 'error');
            return;
        }
        
        // 상태 확인 (status 필드 또는 Status__c 필드 사용)
        const status = leave.status || leave.Status__c;
        
        // 상태에 따라 다른 취소 메서드 호출
        if (status === 'Approved') {
            // 승인된 휴가는 취소 승인 프로세스 시작
            requestCancelAfterApproval({ requestId })
                .then(() => {
                    this.showToast('성공', '휴가 취소 요청이 제출되었습니다. 승인 대기 중입니다.', 'success');
                    this.loadHistory();
                })
                .catch(error => {
                    console.error('취소 승인 프로세스 오류:', error);
                    this.showToast('오류', this.getErrorMessage(error), 'error');
                });
        } else {
            // Draft나 Submitted 상태는 즉시 취소
            cancelLeaveBeforeApproval({ requestId })
                .then(() => {
                    // 취소된 초안이 현재 로드된 초안이면 폼도 초기화
                    if (this.leaveRequestId === requestId) {
                        this.leaveRequestId = null;
                        this.leaveFormData = {};
                        this.leaveDays = null; // 계산된 일수 초기화
                        this.currentDraftLeave = null;
                        this.resetLeaveForm();
                    }
                    this.showToast('성공', '휴가 신청이 취소되었습니다.', 'success');
                    this.loadHistory();
                })
                .catch(error => {
                    console.error('즉시 취소 오류:', error);
                    this.showToast('오류', this.getErrorMessage(error), 'error');
                });
        }
    }

    handleBreakCancelFromHistory(event) {
        const requestId = event.currentTarget.dataset.id;
        cancelBreak({ requestId })
            .then(() => {
                this.showToast('성공', '휴식 신청이 취소되었습니다.', 'success');
                this.loadHistory();
            })
            .catch(error => {
                this.showToast('오류', this.getErrorMessage(error), 'error');
            });
    }

    handleViewAllLeaves() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Leave_Request__c',
                actionName: 'list'
            },
            state: {
                filterName: 'Recent'
            }
        });
    }

    handleViewAllBreaks() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Break_Request__c',
                actionName: 'list'
            },
            state: {
                filterName: 'Recent'
            }
        });
    }

    // 캘린더
    connectedCallback() {
        // Omni-Channel 상태 Id 조회 (Promise 반환)
        this.loadServicePresenceStatus()
            .then(() => {
                // 상태 ID 로드 완료 후 타이머 복원
                this.restoreBreakTimer();
                
                // 주기적으로 활성 휴식 확인 (승인된 휴식 감지)
                this.breakStatusCheckInterval = setInterval(() => {
                    this.restoreBreakTimer();
                }, 5000); // 5초마다 확인
            })
            .catch(error => {
                // eslint-disable-next-line no-console
                console.error('Failed to load service presence status:', error);
                // 상태 ID 로드 실패해도 타이머 복원은 시도 (onBreakId 없으면 경고만)
                this.restoreBreakTimer();
                this.breakStatusCheckInterval = setInterval(() => {
                    this.restoreBreakTimer();
                }, 5000);
            });

        if (this.selectedTab === 'calendar') {
            this.loadCalendar();
        }
        // 휴식 신청 탭이 기본 선택되어 있으면 Date 필드에 오늘 날짜 설정
        if (this.selectedTab === 'break') {
            const today = new Date();
            const todayStr = today.toISOString().split('T')[0];
            this.breakFormData = { Date__c: todayStr };
        }

        // 오늘 날짜의 근무 상태 조회
        this.loadTodayWorkTime();
    }

    // 오늘 날짜의 근무 상태 조회
    loadTodayWorkTime() {
        getTodayWorkTime()
            .then(result => {
                if (result) {
                    this.isOnDuty = result.Status__c === 'On Duty';
                    this.currentWorkTimeId = result.Id;
                    this.workStartTime = result.Work_Start_Time__c;
                    this.workEndTime = result.Work_End_Time__c;
                } else {
                    this.isOnDuty = false;
                    this.currentWorkTimeId = null;
                    this.workStartTime = null;
                    this.workEndTime = null;
                }
            })
            .catch(error => {
                // eslint-disable-next-line no-console
                console.error('Error loading work time:', error);
                this.isOnDuty = false;
                this.currentWorkTimeId = null;
                this.workStartTime = null;
                this.workEndTime = null;
            });
    }

    // 출근/퇴근 토글 핸들러
    handleWorkTimeToggle(event) {
        const isChecked = event.target.checked;
        
        if (isChecked) {
            // 출근 처리
            clockIn()
                .then(result => {
                    this.isOnDuty = true;
                    this.currentWorkTimeId = result.Id;
                    // 서버에서 반환된 최신 출근 시간으로 업데이트
                    this.workStartTime = result.Work_Start_Time__c;
                    // 새로운 출근 시 퇴근 시간은 빈 값으로 설정
                    this.workEndTime = null;
                    
                    // 출근 시 옴니채널 상태를 Online(OK)로 변경
                    this.setOmniAvailableOnClockIn();
                    
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: '출근 처리 완료',
                            message: '출근 시간이 기록되었습니다.',
                            variant: 'success'
                        })
                    );
                })
                .catch(error => {
                    // eslint-disable-next-line no-console
                    console.error('Error clocking in:', error);
                    this.isOnDuty = false;
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: '출근 처리 실패',
                            message: error.body?.message || error.message || '출근 처리 중 오류가 발생했습니다.',
                            variant: 'error'
                        })
                    );
                });
        } else {
            // 퇴근 처리
            clockOut()
                .then(result => {
                    this.isOnDuty = false;
                    // 서버에서 반환된 최신 데이터로 업데이트
                    this.workStartTime = result.Work_Start_Time__c;
                    this.workEndTime = result.Work_End_Time__c;
                    
                    // 퇴근 시 옴니채널 상태를 Offline으로 변경
                    this.setOmniOfflineOnClockOut();
                    
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: '퇴근 처리 완료',
                            message: '퇴근 시간이 기록되었습니다.',
                            variant: 'success'
                        })
                    );
                })
                .catch(error => {
                    // eslint-disable-next-line no-console
                    console.error('Error clocking out:', error);
                    this.isOnDuty = true; // 에러 시 토글 상태 유지
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: '퇴근 처리 실패',
                            message: error.body?.message || error.message || '퇴근 처리 중 오류가 발생했습니다.',
                            variant: 'error'
                        })
                    );
                });
        }
    }

    // Omni-Channel: OnBreak와 Available 상태 Id 조회
    loadServicePresenceStatus() {
        return getServicePresenceStatusId()
            .then(result => {
                if (result != null) {
                    // 중요: 15자리로 substring 필수
                    if (result.onBreakId) {
                        let breakId = result.onBreakId;
                        let breakIdStr = breakId.substring(0, 15);
                        this.onBreakId = breakIdStr;
                        // eslint-disable-next-line no-console
                        console.log('Omni onBreakId loaded (15): ', this.onBreakId);
                    } else {
                        // eslint-disable-next-line no-console
                        console.warn('OnBreak status ID not found. Please create "OnBreak" status in Omni-Channel settings.');
                    }
                    
                    if (result.availableChatId) {
                        let availableId = result.availableChatId;
                        let availableStr = availableId.substring(0, 15);
                        this.availableChatId = availableStr;
                        // eslint-disable-next-line no-console
                        console.log('Omni availableChatId loaded (15): ', this.availableChatId);
                    } else {
                        // eslint-disable-next-line no-console
                        console.warn('Available/OK status ID not found. Please check Omni-Channel settings.');
                    }
                } else {
                    // eslint-disable-next-line no-console
                    console.warn('Omni status IDs not returned from server');
                }
                return result; // Promise 체이닝을 위해 반환
            })
            .catch(error => {
                // eslint-disable-next-line no-console
                console.error('Error loading Omni presence status ids:', error);
                // 에러가 발생해도 Promise는 reject하지 않고 계속 진행 (타이머 복원은 계속)
                return null;
            });
    }

    // Omni-Channel을 OnBreak 상태로 전환 (휴식 시작 시)
    setOmniOnBreak() {
        if (!this.onBreakId) {
            // eslint-disable-next-line no-console
            console.warn('onBreakId is not set. Cannot change Omni status to OnBreak.');
            return;
        }
        
        // 중복 호출 방지
        if (this.lastOmniStatus === 'OnBreak') {
            // eslint-disable-next-line no-console
            console.log('Omni status is already OnBreak, skipping...');
            return;
        }
        
        // 디바운싱: 너무 빠른 연속 호출 방지 (300ms)
        const now = Date.now();
        const DEBOUNCE_MS = 300;
        if (now - this.lastStatusChangeTimestamp < DEBOUNCE_MS) {
            // eslint-disable-next-line no-console
            console.log('Debouncing OnBreak status change...');
            const remainingTime = DEBOUNCE_MS - (now - this.lastStatusChangeTimestamp);
            setTimeout(() => {
                this.setOmniOnBreak();
            }, remainingTime);
            return;
        }
        
        try {
            // 🔑 핵심: 실제 작동하는 코드와 동일한 방식으로 이벤트 디스패치
            // 참고: 실제 작동하는 코드는 bubbles/composed 옵션 없이도 작동함
            const selectedEvent = new CustomEvent('selectedstatus', {
                detail: {
                    statusId: this.onBreakId  // OnBreak 상태 (15자리 ID)
                }
            });
            this.dispatchEvent(selectedEvent);
            // eslint-disable-next-line no-console
            console.log('[LWC] Dispatched OnBreak status event:', this.onBreakId);
            
            this.lastOmniStatus = 'OnBreak';
            this.lastStatusChangeTimestamp = now;
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[LWC] Failed to dispatch Omni OnBreak event:', e);
            // 에러 발생 시 lastOmniStatus를 리셋하여 재시도 가능하도록
            this.lastOmniStatus = null;
        }
    }

    // 퇴근 시 옴니채널 상태를 Offline으로 변경
    setOmniOfflineOnClockOut() {
        // eslint-disable-next-line no-console
        console.log('[Clock-Out] Setting Omni status to Offline...');
        
        try {
            // Visualforce 페이지의 logout 함수를 직접 호출 시도
            if (window.parent && typeof window.parent.logout === 'function') {
                window.parent.logout();
                // eslint-disable-next-line no-console
                console.log('[LWC] Directly called window.parent.logout');
            }
            if (window.top && window.top !== window && typeof window.top.logout === 'function') {
                window.top.logout();
                // eslint-disable-next-line no-console
                console.log('[LWC] Directly called window.top.logout');
            }
            
            // 이벤트를 통한 logout 요청
            const logoutEvent = new CustomEvent('selectedstatus', {
                detail: {
                    cmd: 'logout'
                },
                bubbles: true,
                composed: true
            });
            
            this.dispatchEvent(logoutEvent);
            
            // document 레벨로도 디스패치
            try {
                document.dispatchEvent(new CustomEvent('selectedstatus', {
                    detail: {
                        cmd: 'logout'
                    },
                    bubbles: true,
                    composed: true
                }));
                // eslint-disable-next-line no-console
                console.log('[LWC] Also dispatched logout to document');
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to dispatch logout to document:', e);
            }
            
            // window 레벨로도 디스패치
            try {
                if (window.dispatchEvent) {
                    window.dispatchEvent(new CustomEvent('selectedstatus', {
                        detail: {
                            cmd: 'logout'
                        },
                        bubbles: true,
                        composed: true
                    }));
                    // eslint-disable-next-line no-console
                    console.log('[LWC] Also dispatched logout to window');
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to dispatch logout to window:', e);
            }
            
            // postMessage를 통한 iframe 간 통신 (모든 레벨에서)
            const logoutPostMessageData = {
                type: 'selectedstatus',
                detail: {
                    cmd: 'logout'
                }
            };
            
            try {
                // window.parent로 postMessage
                if (window.parent && window.parent !== window) {
                    window.parent.postMessage(logoutPostMessageData, '*');
                    // eslint-disable-next-line no-console
                    console.log('[LWC] Sent logout postMessage to window.parent:', logoutPostMessageData);
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to send logout postMessage to window.parent:', e);
            }
            
            try {
                // window.top으로 postMessage
                if (window.top && window.top !== window && window.top !== window.parent) {
                    window.top.postMessage(logoutPostMessageData, '*');
                    // eslint-disable-next-line no-console
                    console.log('[LWC] Sent logout postMessage to window.top:', logoutPostMessageData);
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to send logout postMessage to window.top:', e);
            }
            
            try {
                // window.frames를 통한 모든 iframe에 postMessage
                if (window.frames && window.frames.length > 0) {
                    for (let i = 0; i < window.frames.length; i++) {
                        try {
                            window.frames[i].postMessage(logoutPostMessageData, '*');
                            // eslint-disable-next-line no-console
                            console.log('[LWC] Sent logout postMessage to window.frames[' + i + ']');
                        } catch (e) {
                            // eslint-disable-next-line no-console
                            console.warn('[LWC] Failed to send logout postMessage to window.frames[' + i + ']:', e);
                        }
                    }
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to send logout postMessage to window.frames:', e);
            }
            
            // Visualforce 페이지의 logout 함수를 직접 호출 시도 (모든 레벨에서)
            try {
                // window.parent에서 직접 호출
                if (window.parent && window.parent !== window) {
                    if (typeof window.parent.logout === 'function') {
                        window.parent.logout();
                        // eslint-disable-next-line no-console
                        console.log('[LWC] Directly called window.parent.logout');
                    } else {
                        // eslint-disable-next-line no-console
                        console.warn('[LWC] window.parent.logout is not a function');
                    }
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to call window.parent.logout:', e);
            }
            
            try {
                // window.top에서 직접 호출
                if (window.top && window.top !== window && window.top !== window.parent) {
                    if (typeof window.top.logout === 'function') {
                        window.top.logout();
                        // eslint-disable-next-line no-console
                        console.log('[LWC] Directly called window.top.logout');
                    } else {
                        // eslint-disable-next-line no-console
                        console.warn('[LWC] window.top.logout is not a function');
                    }
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to call window.top.logout:', e);
            }
            
            // 모든 iframe에서 함수 호출 시도
            try {
                if (window.frames && window.frames.length > 0) {
                    for (let i = 0; i < window.frames.length; i++) {
                        try {
                            if (window.frames[i] && typeof window.frames[i].logout === 'function') {
                                window.frames[i].logout();
                                // eslint-disable-next-line no-console
                                console.log('[LWC] Directly called window.frames[' + i + '].logout');
                            }
                        } catch (e) {
                            // eslint-disable-next-line no-console
                            console.warn('[LWC] Failed to call window.frames[' + i + '].logout:', e);
                        }
                    }
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to call logout on window.frames:', e);
            }
            
            // eslint-disable-next-line no-console
            console.log('[LWC] Dispatched logout event');
            
            // lastOmniStatus 리셋
            this.lastOmniStatus = null;
            this.lastStatusChangeTimestamp = 0;
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[LWC] Failed to dispatch Omni logout event:', e);
        }
    }

    // 출근 시 옴니채널 상태를 Online(OK)로 변경 (재시도 로직 포함)
    setOmniAvailableOnClockIn(retryCount = 0) {
        const MAX_RETRIES = 3;
        const RETRY_DELAY = 500; // 500ms
        
        if (this.availableChatId) {
            // availableChatId가 있으면 바로 상태 변경 (강제로, lastOmniStatus 체크 무시)
            // eslint-disable-next-line no-console
            console.log('[Clock-In] Setting Omni status to Available (Online)...');
            this.setOmniAvailable(true); // 강제 플래그 전달
            return;
        }
        
        // availableChatId가 없으면 로드 시도
        if (retryCount < MAX_RETRIES) {
            // eslint-disable-next-line no-console
            console.log(`[Clock-In] availableChatId not loaded, attempting to load... (retry ${retryCount + 1}/${MAX_RETRIES})`);
            this.loadServicePresenceStatus()
                .then(() => {
                    if (this.availableChatId) {
                        // eslint-disable-next-line no-console
                        console.log('[Clock-In] availableChatId loaded, setting Omni status to Available...');
                        this.setOmniAvailable(true); // 강제 플래그 전달
                    } else {
                        // 로드했지만 여전히 없으면 재시도
                        setTimeout(() => {
                            this.setOmniAvailableOnClockIn(retryCount + 1);
                        }, RETRY_DELAY);
                    }
                })
                .catch(error => {
                    // eslint-disable-next-line no-console
                    console.warn('[Clock-In] Failed to load service presence status:', error);
                    // 에러 발생 시에도 재시도
                    if (retryCount < MAX_RETRIES - 1) {
                        setTimeout(() => {
                            this.setOmniAvailableOnClockIn(retryCount + 1);
                        }, RETRY_DELAY);
                    }
                });
        } else {
            // eslint-disable-next-line no-console
            console.error('[Clock-In] Failed to load availableChatId after max retries. Omni status may not be updated.');
        }
    }

    // Omni-Channel을 Available 상태로 전환 (휴식 종료 시)
    // force: true일 경우 lastOmniStatus 체크를 무시하고 강제로 상태 변경
    setOmniAvailable(force = false) {
        if (!this.availableChatId) {
            // eslint-disable-next-line no-console
            console.warn('availableChatId is not set. Cannot change Omni status to Available.');
            return;
        }
        
        // 강제 모드가 아닐 때만 중복 호출 방지
        // 하지만 출근 시에는 항상 강제로 변경해야 하므로 force=true로 호출됨
        if (!force && this.lastOmniStatus === 'Available') {
            // eslint-disable-next-line no-console
            console.log('Omni status is already Available, skipping...');
            return;
        }
        
        if (force) {
            // eslint-disable-next-line no-console
            console.log('[Clock-In] Force setting Omni status to Available (ignoring lastOmniStatus check)');
            // 강제 모드일 때는 lastOmniStatus를 리셋하여 확실히 변경되도록 함
            this.lastOmniStatus = null;
        }
        
        // 디바운싱: 너무 빠른 연속 호출 방지 (300ms)
        const now = Date.now();
        const DEBOUNCE_MS = 300;
        if (now - this.lastStatusChangeTimestamp < DEBOUNCE_MS) {
            // eslint-disable-next-line no-console
            console.log('Debouncing Available status change...');
            const remainingTime = DEBOUNCE_MS - (now - this.lastStatusChangeTimestamp);
            setTimeout(() => {
                this.setOmniAvailable();
            }, remainingTime);
            return;
        }
        
        try {
            // 🔑 핵심: 실제 작동하는 코드와 동일한 방식으로 이벤트 디스패치
            // Visualforce 페이지가 이벤트를 받을 수 있도록 bubbles/composed 옵션 사용
            const selectedEvent = new CustomEvent('selectedstatus', {
                detail: {
                    statusId: this.availableChatId  // Available 상태 (15자리 ID)
                },
                bubbles: true,
                composed: true
            });
            
            // 이벤트를 여러 방법으로 디스패치 시도
            this.dispatchEvent(selectedEvent);
            
            // document 레벨로도 디스패치 시도 (Visualforce 페이지가 받을 수 있도록)
            try {
                document.dispatchEvent(new CustomEvent('selectedstatus', {
                    detail: {
                        statusId: this.availableChatId
                    },
                    bubbles: true,
                    composed: true
                }));
                // eslint-disable-next-line no-console
                console.log('[LWC] Also dispatched to document');
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to dispatch to document:', e);
            }
            
            // window 레벨로도 디스패치 시도
            try {
                if (window.dispatchEvent) {
                    window.dispatchEvent(new CustomEvent('selectedstatus', {
                        detail: {
                            statusId: this.availableChatId
                        },
                        bubbles: true,
                        composed: true
                    }));
                    // eslint-disable-next-line no-console
                    console.log('[LWC] Also dispatched to window');
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to dispatch to window:', e);
            }
            
            // postMessage를 통한 iframe 간 통신 시도 (모든 레벨에서)
            const postMessageData = {
                type: 'selectedstatus',
                detail: {
                    statusId: this.availableChatId
                }
            };
            
            try {
                // window.parent로 postMessage
                if (window.parent && window.parent !== window) {
                    window.parent.postMessage(postMessageData, '*');
                    // eslint-disable-next-line no-console
                    console.log('[LWC] Sent postMessage to window.parent:', postMessageData);
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to send postMessage to window.parent:', e);
            }
            
            try {
                // window.top으로 postMessage
                if (window.top && window.top !== window && window.top !== window.parent) {
                    window.top.postMessage(postMessageData, '*');
                    // eslint-disable-next-line no-console
                    console.log('[LWC] Sent postMessage to window.top:', postMessageData);
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to send postMessage to window.top:', e);
            }
            
            try {
                // window.frames를 통한 모든 iframe에 postMessage
                if (window.frames && window.frames.length > 0) {
                    for (let i = 0; i < window.frames.length; i++) {
                        try {
                            window.frames[i].postMessage(postMessageData, '*');
                            // eslint-disable-next-line no-console
                            console.log('[LWC] Sent postMessage to window.frames[' + i + ']');
                        } catch (e) {
                            // eslint-disable-next-line no-console
                            console.warn('[LWC] Failed to send postMessage to window.frames[' + i + ']:', e);
                        }
                    }
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to send postMessage to window.frames:', e);
            }
            
            // Visualforce 페이지의 함수를 직접 호출 시도 (모든 레벨에서)
            try {
                // window.parent에서 직접 호출
                if (window.parent && window.parent !== window) {
                    if (typeof window.parent.setServicePresenceStatus === 'function') {
                        window.parent.setServicePresenceStatus(this.availableChatId);
                        // eslint-disable-next-line no-console
                        console.log('[LWC] Directly called window.parent.setServicePresenceStatus');
                    } else {
                        // eslint-disable-next-line no-console
                        console.warn('[LWC] window.parent.setServicePresenceStatus is not a function');
                    }
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to call window.parent.setServicePresenceStatus:', e);
            }
            
            try {
                // window.top에서 직접 호출
                if (window.top && window.top !== window && window.top !== window.parent) {
                    if (typeof window.top.setServicePresenceStatus === 'function') {
                        window.top.setServicePresenceStatus(this.availableChatId);
                        // eslint-disable-next-line no-console
                        console.log('[LWC] Directly called window.top.setServicePresenceStatus');
                    } else {
                        // eslint-disable-next-line no-console
                        console.warn('[LWC] window.top.setServicePresenceStatus is not a function');
                    }
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to call window.top.setServicePresenceStatus:', e);
            }
            
            // 모든 iframe에서 함수 호출 시도
            try {
                if (window.frames && window.frames.length > 0) {
                    for (let i = 0; i < window.frames.length; i++) {
                        try {
                            if (window.frames[i] && typeof window.frames[i].setServicePresenceStatus === 'function') {
                                window.frames[i].setServicePresenceStatus(this.availableChatId);
                                // eslint-disable-next-line no-console
                                console.log('[LWC] Directly called window.frames[' + i + '].setServicePresenceStatus');
                            }
                        } catch (e) {
                            // eslint-disable-next-line no-console
                            console.warn('[LWC] Failed to call window.frames[' + i + '].setServicePresenceStatus:', e);
                        }
                    }
                }
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('[LWC] Failed to call setServicePresenceStatus on window.frames:', e);
            }
            
            // eslint-disable-next-line no-console
            console.log('[LWC] Dispatched Available status event:', this.availableChatId);
            
            // 상태 변경 성공 시에만 lastOmniStatus 업데이트
            // (실제로는 API 응답을 받아야 하지만, 일단 이벤트 디스패치 후 업데이트)
            this.lastOmniStatus = 'Available';
            this.lastStatusChangeTimestamp = now;
            
            // 추가 확인: 약간의 지연 후 다시 한 번 시도 (Visualforce 페이지가 준비되지 않았을 수 있음)
            setTimeout(() => {
                // Visualforce 페이지의 함수를 다시 한 번 직접 호출
                try {
                    if (window.parent && typeof window.parent.setServicePresenceStatus === 'function') {
                        window.parent.setServicePresenceStatus(this.availableChatId);
                        // eslint-disable-next-line no-console
                        console.log('[LWC] Retry: Directly called window.parent.setServicePresenceStatus after delay');
                    }
                } catch (e) {
                    // eslint-disable-next-line no-console
                    console.warn('[LWC] Retry failed:', e);
                }
            }, 1000); // 1초 후 재시도
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[LWC] Failed to dispatch Omni Available event:', e);
            // 에러 발생 시 lastOmniStatus를 리셋하여 재시도 가능하도록
            this.lastOmniStatus = null;
        }
    }

    renderedCallback() {
        // 휴식 신청 탭이 활성화되어 있을 때 Date 필드 값을 오늘 날짜로 설정
        if (this.selectedTab === 'break') {
            const dateField = this.template.querySelector('lightning-input-field[field-name="Date__c"]');
            if (dateField) {
                const today = new Date();
                const todayStr = today.toISOString().split('T')[0];
                if (dateField.value !== todayStr) {
                    dateField.value = todayStr;
                    if (!this.breakFormData) {
                        this.breakFormData = {};
                    }
                    this.breakFormData.Date__c = todayStr;
                }
            }
        }
    }

    get currentMonthLabel() {
        const monthNames = ['1월', '2월', '3월', '4월', '5월', '6월', 
                           '7월', '8월', '9월', '10월', '11월', '12월'];
        return `${this.currentYear}년 ${monthNames[this.currentMonth]}`;
    }

    get calendarStartDateStr() {
        const firstDay = new Date(this.currentYear, this.currentMonth, 1);
        // 달력 시작일: 해당 월의 첫 번째 일요일
        const dayOfWeek = firstDay.getDay();
        firstDay.setDate(firstDay.getDate() - dayOfWeek);
        return this.formatDateForApex(firstDay);
    }

    get calendarEndDateStr() {
        const lastDay = new Date(this.currentYear, this.currentMonth + 1, 0);
        // 달력 종료일: 해당 월의 마지막 토요일
        const dayOfWeek = lastDay.getDay();
        lastDay.setDate(lastDay.getDate() + (6 - dayOfWeek));
        return this.formatDateForApex(lastDay);
    }

    get calendarStartDate() {
        // Date 객체로 변환 (Apex에서 자동 변환되지만 명시적으로)
        const str = this.calendarStartDateStr;
        if (!str) return null;
        const parts = str.split('-');
        return new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
    }

    get calendarEndDate() {
        const str = this.calendarEndDateStr;
        if (!str) return null;
        const parts = str.split('-');
        return new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
    }

    @wire(getMyLeaves, { startDate: '$calendarStartDate', endDate: '$calendarEndDate' })
    wiredCalendarLeaves(result) {
        this.wiredCalendarLeaves = result;
        if (result.data) {
            this.calendarLeaves = result.data || [];
            this.buildCalendar();
        }
    }

    @wire(getMyBreaksRange, { startDate: '$calendarStartDate', endDate: '$calendarEndDate' })
    wiredCalendarBreaks(result) {
        this.wiredCalendarBreaks = result;
        if (result.data) {
            this.calendarBreaks = result.data || [];
            this.buildCalendar();
        }
    }

    loadCalendar() {
        this.isLoadingCalendar = true;
        if (this.wiredCalendarLeaves) {
            refreshApex(this.wiredCalendarLeaves);
        }
        if (this.wiredCalendarBreaks) {
            refreshApex(this.wiredCalendarBreaks);
        }
        setTimeout(() => {
            this.isLoadingCalendar = false;
        }, 500);
    }

    buildCalendar() {
        const days = [];
        const firstDay = new Date(this.currentYear, this.currentMonth, 1);
        const lastDay = new Date(this.currentYear, this.currentMonth + 1, 0);
        const startDate = new Date(firstDay);
        startDate.setDate(startDate.getDate() - startDate.getDay()); // 첫 번째 일요일
        
        const endDate = new Date(lastDay);
        endDate.setDate(endDate.getDate() + (6 - endDate.getDay())); // 마지막 토요일
        
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        
        // 휴가 데이터를 날짜별로 매핑(종일/오전/오후)
        // 규칙:
        // - 같은 날짜: AM~PM = 종일, AM~AM = 오전, PM~PM = 오후
        // - 여러 날짜:
        //   - 시작일: Start_Slot=PM이면 오후(반차), AM이면 종일
        //   - 종료일: End_Slot=AM이면 오전(반차), PM이면 종일
        //   - 중간 날짜: 종일
        const leaveCoverageMap = new Map(); // dateKey -> { full:boolean, am:boolean, pm:boolean }
        (this.calendarLeaves || []).forEach(leave => {
            if (!(leave.Status__c === 'Approved' || leave.Status__c === 'CancelSubmitted')) return;
            const start = this.parseDate(leave.Start_Date__c);
            const end = this.parseDate(leave.End_Date__c);
            if (!start || !end) return;
            start.setHours(0, 0, 0, 0);
            end.setHours(0, 0, 0, 0);

            for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
                const dateKey = this.getDateKey(d);
                const cov = this.getLeaveCoverageForDate(leave, d, start, end);
                if (!cov) continue;

                const cur = leaveCoverageMap.get(dateKey) || { full: false, am: false, pm: false };
                if (cov === 'FULL') {
                    cur.full = true;
                    cur.am = false;
                    cur.pm = false;
                } else if (!cur.full && cov === 'AM') {
                    cur.am = true;
                } else if (!cur.full && cov === 'PM') {
                    cur.pm = true;
                }
                leaveCoverageMap.set(dateKey, cur);
            }
        });
        
        // 휴식 데이터를 날짜별로 매핑
        const breakMap = new Map();
        (this.calendarBreaks || []).forEach(br => {
            const dateKey = this.getDateKey(this.parseDate(br.Date__c));
            if (!breakMap.has(dateKey)) {
                breakMap.set(dateKey, []);
            }
            breakMap.get(dateKey).push(br);
        });
        
        // 달력 날짜 생성
        for (let d = new Date(startDate); d <= endDate; d.setDate(d.getDate() + 1)) {
            const dateKey = this.getDateKey(d);
            const isCurrentMonth = d.getMonth() === this.currentMonth;
            const isToday = this.getDateKey(today) === dateKey;
            const leaveCov = leaveCoverageMap.get(dateKey) || null;
            const hasLeaveFull = !!(leaveCov && leaveCov.full);
            const hasLeaveAM = !!(leaveCov && leaveCov.am);
            const hasLeavePM = !!(leaveCov && leaveCov.pm);
            const hasLeave = hasLeaveFull || hasLeaveAM || hasLeavePM;
            const breaks = breakMap.get(dateKey) || [];
            
            const hasMorningBreak = breaks.some(b => b.Break_Type__c === 'Morning Break');
            const hasAfternoonBreak = breaks.some(b => b.Break_Type__c === 'Afternoon Break');
            
            const leaveClass = hasLeaveFull ? 'leave-full' : (hasLeaveAM ? 'leave-am' : (hasLeavePM ? 'leave-pm' : ''));
            days.push({
                key: dateKey,
                dayNumber: d.getDate(),
                dayClass: `calendar-day ${isCurrentMonth ? 'current-month' : 'other-month'} ${isToday ? 'today' : ''} ${hasLeave ? 'has-leave' : ''} ${leaveClass}`,
                hasLeave: hasLeave,
                hasLeaveFull: hasLeaveFull,
                hasLeaveAM: hasLeaveAM,
                hasLeavePM: hasLeavePM,
                hasMorningBreak: hasMorningBreak,
                hasAfternoonBreak: hasAfternoonBreak
            });
        }
        
        this.calendarDays = days;
    }

    // 특정 날짜의 휴가 커버리지(FULL/AM/PM) 계산
    getLeaveCoverageForDate(leave, dayDate, startDate, endDate) {
        if (!leave || !dayDate || !startDate || !endDate) return null;
        const dayKey = this.getDateKey(dayDate);
        const startKey = this.getDateKey(startDate);
        const endKey = this.getDateKey(endDate);
        const startSlot = (leave.Start_Slot__c || '').toString();
        const endSlot = (leave.End_Slot__c || '').toString();

        if (startKey === endKey) {
            if (startSlot === 'AM' && endSlot === 'PM') return 'FULL';
            if (startSlot === 'AM' && endSlot === 'AM') return 'AM';
            if (startSlot === 'PM' && endSlot === 'PM') return 'PM';
            // fallback
            return 'FULL';
        }

        if (dayKey === startKey) {
            return startSlot === 'PM' ? 'PM' : 'FULL';
        }
        if (dayKey === endKey) {
            return endSlot === 'AM' ? 'AM' : 'FULL';
        }
        return 'FULL';
    }

    parseDate(dateValue) {
        if (!dateValue) return null;
        if (typeof dateValue === 'string') {
            return new Date(dateValue);
        }
        if (dateValue instanceof Date) {
            return dateValue;
        }
        return new Date(dateValue);
    }

    getDateKey(date) {
        if (!date) return '';
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    handlePrevMonth() {
        if (this.currentMonth === 0) {
            this.currentMonth = 11;
            this.currentYear--;
        } else {
            this.currentMonth--;
        }
        this.loadCalendar();
    }

    handleNextMonth() {
        if (this.currentMonth === 11) {
            this.currentMonth = 0;
            this.currentYear++;
        } else {
            this.currentMonth++;
        }
        this.loadCalendar();
    }


    // 유틸리티
    getErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return '알 수 없는 오류가 발생했습니다.';
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable' // 자동으로 사라지는 모드
        });
        this.dispatchEvent(evt);
    }

    // 휴식 타이머 관련 메서드
    startBreakTimer(remainingSeconds = null) {
        // 기존 타이머가 있으면 정리 (상태 변경 없이)
        this.stopBreakTimer(false);

        // 타이머 시작 시 Omni-Channel을 OnBreak 상태로 전환
        this.setOmniOnBreak();
        
        // 남은 시간이 지정되지 않으면 15분 = 900초로 시작
        if (remainingSeconds === null || remainingSeconds <= 0) {
            this.breakTimerSeconds = 15 * 60;
        } else {
            this.breakTimerSeconds = remainingSeconds;
        }
        this.showBreakTimer = true;
        
        // 1초마다 카운트다운
        this.breakTimerInterval = setInterval(() => {
            this.breakTimerSeconds--;
            
            if (this.breakTimerSeconds <= 0) {
                this.stopBreakTimer();
            }
        }, 1000);
    }

    // 서버에서 남은 시간 계산하여 타이머 복원
    restoreBreakTimer() {
        getActiveBreak()
            .then(activeBreak => {
                if (!activeBreak || !activeBreak.Start_Time__c || !activeBreak.End_Time__c) {
                    // 활성 휴식이 없으면 타이머 중지
                    if (this.showBreakTimer) {
                        this.stopBreakTimer();
                    }
                    return;
                }
                
                // 승인된 휴식이 있고, Morning Break, Afternoon Break, 또는 Lunch인 경우 상태 변경
                // 단, 타이머가 이미 시작된 경우는 제외 (타이머 시작 시 이미 상태 변경됨)
                // 또한 최근에 상태 변경을 시도한 경우도 제외 (디바운싱)
                const now = Date.now();
                const shouldChangeStatus = activeBreak.Status__c === 'Approved' && 
                    (activeBreak.Break_Type__c === 'Morning Break' || 
                     activeBreak.Break_Type__c === 'Afternoon Break' ||
                     activeBreak.Break_Type__c === 'Lunch') &&
                    !this.showBreakTimer && 
                    this.onBreakId &&
                    this.lastOmniStatus !== 'OnBreak' &&
                    (now - this.lastStatusChangeTimestamp > 2000); // 최근 2초 이내 상태 변경 시도가 없을 때만
                
                if (shouldChangeStatus) {
                    // 타이머가 시작되지 않았고, 상태가 아직 OnBreak가 아닌 경우에만 상태 변경
                    this.setOmniOnBreak();
                }
                
                // calculateRemainingSeconds 메서드를 사용하여 남은 시간 계산
                const remainingSeconds = this.calculateRemainingSeconds(
                    activeBreak.Start_Time__c,
                    activeBreak.End_Time__c
                );
                
                // Morning Break 또는 Afternoon Break인 경우 타이머 시작
                if ((activeBreak.Break_Type__c === 'Morning Break' || 
                     activeBreak.Break_Type__c === 'Afternoon Break') &&
                    remainingSeconds > 0 && remainingSeconds <= 900) {
                    this.startBreakTimer(remainingSeconds);
                } else if (activeBreak.Break_Type__c === 'Lunch' && 
                          remainingSeconds > 0 && remainingSeconds <= 3600) {
                    // Lunch는 최대 1시간까지 허용
                    this.startBreakTimer(remainingSeconds);
                } else if (remainingSeconds <= 0) {
                    // 시간이 지났으면 타이머 중지
                    this.stopBreakTimer();
                }
            })
            .catch(error => {
                console.error('Error restoring break timer:', error);
            });
    }

    stopBreakTimer(changeStatusToAvailable = true) {
        if (this.breakTimerInterval) {
            clearInterval(this.breakTimerInterval);
            this.breakTimerInterval = null;
        }
        
        // 타이머 종료 시 Omni-Channel 상태를 Available로 복귀
        // 단, startBreakTimer에서 호출할 때는 상태 변경을 건너뜀 (바로 OnBreak로 변경되므로)
        if (this.showBreakTimer && changeStatusToAvailable) {
            this.setOmniAvailable();
        }
        
        this.showBreakTimer = false;
        this.breakTimerSeconds = 0;
        
        // 상태 초기화는 상태 변경을 할 때만 (Available로 변경할 때만)
        if (changeStatusToAvailable) {
            this.lastOmniStatus = null;
            this.lastStatusChangeTimestamp = 0;
        }
    }

    // Start_Time__c와 End_Time__c를 사용하여 남은 시간(초) 계산
    calculateRemainingSeconds(startTime, endTime) {
        if (!startTime || !endTime) return 0;
        
        const now = new Date();
        const currentTimeSeconds = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds();
        
        // End_Time__c를 초로 변환
        const endTimeStr = String(endTime);
        let endTimeSeconds = 0;
        
        if (/^\d+$/.test(endTimeStr)) {
            // 밀리초 형식
            const totalSeconds = Math.floor(parseInt(endTimeStr, 10) / 1000);
            endTimeSeconds = totalSeconds % 86400; // 하루를 초로 나눈 나머지
        } else if (endTimeStr.includes(':')) {
            // HH:mm 또는 HH:mm:ss 형식
            const parts = endTimeStr.split(':');
            endTimeSeconds = parseInt(parts[0], 10) * 3600 + parseInt(parts[1], 10) * 60;
            if (parts.length >= 3) {
                endTimeSeconds += parseInt(parts[2], 10);
            }
        } else if (endTime.hour !== undefined) {
            // Time 객체 형식
            endTimeSeconds = endTime.hour * 3600 + (endTime.minute || 0) * 60 + (endTime.second || 0);
        }
        
        // 남은 시간 계산
        let remainingSeconds = endTimeSeconds - currentTimeSeconds;
        
        // 자정을 넘어가는 경우 처리
        if (remainingSeconds < 0) {
            remainingSeconds += 86400; // 하루 추가
        }
        
        return remainingSeconds;
    }

    get breakTimerDisplay() {
        const minutes = Math.floor(this.breakTimerSeconds / 60);
        const seconds = this.breakTimerSeconds % 60;
        return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
    }

    disconnectedCallback() {
        // 컴포넌트 언마운트 시 타이머 정리
        this.stopBreakTimer();
        if (this.breakStatusCheckInterval) {
            clearInterval(this.breakStatusCheckInterval);
            this.breakStatusCheckInterval = null;
        }
    }
}