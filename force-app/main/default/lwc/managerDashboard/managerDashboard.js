import { LightningElement, wire, track } from 'lwc';
import getTodayStatus from '@salesforce/apex/ManagerDashboardController.getTodayStatus';
import getTeamBreakRequests from '@salesforce/apex/ManagerDashboardController.getTeamBreakRequests';
import getTeamLeaveRequests from '@salesforce/apex/ManagerDashboardController.getTeamLeaveRequests';
import getTeamWorkTimes from '@salesforce/apex/ManagerDashboardController.getTeamWorkTimes';
import cancelBreakByManager from '@salesforce/apex/BreakRequestController.cancelByManager';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ManagerDashboard extends LightningElement {
    @track agentStatuses = [];
    @track error;
    isLoading = true;
    refreshInterval;
    wiredResult;
    
    // 탭 관리
    @track selectedTab = 'status'; // 'status', 'breaks', 'leaves', or 'worktime'
    
    // 휴식 신청 관리
    @track breakRequests = [];
    @track isLoadingBreaks = false;
    @track breakStartDate;
    @track breakEndDate;
    @track breakStatusFilter = 'All';
    @track breakAgentFilter = 'All';
    @track breakCurrentPage = 1;
    breakPageSize = 5;
    @track teamMembers = []; // 팀원 목록
    
    // 휴가 신청 관리
    @track leaveRequests = [];
    @track isLoadingLeaves = false;
    @track leaveStartDate;
    @track leaveEndDate;
    @track leaveStatusFilter = 'All';
    @track leaveAgentFilter = 'All';
    @track leaveCurrentPage = 1;
    leavePageSize = 5;
    
    // 근무 시간 관리
    @track workTimes = [];
    @track isLoadingWorkTimes = false;
    @track workTimeStartDate;
    @track workTimeEndDate;
    @track workTimeAgentFilter = 'All';
    @track workTimeStatusFilter = 'All';
    @track workTimeCurrentPage = 1;
    workTimePageSize = 5;

    @wire(getTodayStatus)
    wiredStatus(result) {
        this.wiredResult = result;
        if (result.data) {
            this.agentStatuses = this.decorateStatuses(result.data);
            // 팀원 목록 추출 (상담사 필터용)
            this.teamMembers = result.data.map(agent => ({
                label: agent.userName,
                value: agent.userId
            }));
            this.error = undefined;
            this.isLoading = false;
        } else if (result.error) {
            this.error = result.error?.body?.message || '데이터를 불러오는 중 오류가 발생했습니다.';
            this.agentStatuses = [];
            this.teamMembers = [];
            this.isLoading = false;
        }
    }

    connectedCallback() {
        // 자동 새로고침(상담사 현황 탭): 더 빠르게 반영되도록 단축
        this.refreshInterval = setInterval(() => {
            if (this.selectedTab === 'status' && this.wiredResult) {
                refreshApex(this.wiredResult);
            }
        }, 5000);
        
        // 시작/종료 날짜를 오늘 날짜로 초기화
        const today = new Date();
        const todayStr = today.toISOString().split('T')[0];
        this.breakStartDate = todayStr;
        this.breakEndDate = todayStr;
        this.workTimeStartDate = todayStr;
        this.workTimeEndDate = todayStr;
    }

    disconnectedCallback() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
    }

    decorateStatuses(rawData) {
        return (rawData || []).map(agent => {
            return {
                ...agent,
                leaveStatusLabel: this.getLeaveStatusLabel(agent.leaveStatus),
                leaveStatusClass: this.getLeaveStatusClass(agent.leaveStatus),
                morningBreakLabel: this.getBreakStatusLabelForDashboard(agent.morningBreak),
                morningBreakClass: this.getBreakStatusClass(agent.morningBreak),
                lunchLabel: this.getBreakStatusLabelForDashboard(agent.lunch),
                lunchClass: this.getBreakStatusClass(agent.lunch),
                afternoonBreakLabel: this.getBreakStatusLabelForDashboard(agent.afternoonBreak),
                afternoonBreakClass: this.getBreakStatusClass(agent.afternoonBreak)
            };
        });
    }

    getLeaveStatusLabel(status) {
        if (status === 'On Leave') return '휴가중';
        if (status === 'Available') return '해당없음';
        return status || '해당없음';
    }

    getLeaveStatusClass(status) {
        if (status === 'On Leave') return 'status-badge on-leave';
        return 'status-badge available';
    }

    getBreakStatusLabel(status) {
        if (status === 'Used') return '사용 완료';
        // 요구사항: '예정' 제거 → 바로 '사용 완료' 표기
        if (status === 'Scheduled') return '사용 완료';
        return '사용 가능';
    }

    getBreakStatusLabelForDashboard(status) {
        if (status === 'Used') return '사용 완료';
        if (status === 'Scheduled') return '사용 완료';
        return '사용 가능';
    }

    getBreakStatusClass(status) {
        if (status === 'Used') return 'status-badge used';
        // '예정' 제거에 맞춰 스타일도 used로 통일
        if (status === 'Scheduled') return 'status-badge used';
        return 'status-badge available';
    }

    get hasData() {
        return this.agentStatuses && this.agentStatuses.length > 0;
    }

    get hasBreakRequests() {
        return this.breakRequests && this.breakRequests.length > 0;
    }

    // 휴식 신청 페이징
    get paginatedBreakRequests() {
        if (!this.breakRequests || this.breakRequests.length === 0) return [];
        const start = (this.breakCurrentPage - 1) * this.breakPageSize;
        const end = start + this.breakPageSize;
        return this.breakRequests.slice(start, end);
    }

    get breakTotalPages() {
        if (!this.breakRequests || this.breakRequests.length === 0) return 0;
        return Math.ceil(this.breakRequests.length / this.breakPageSize);
    }

    get breakPaginationInfo() {
        if (!this.breakRequests || this.breakRequests.length === 0) return '0 / 0';
        const start = (this.breakCurrentPage - 1) * this.breakPageSize + 1;
        const end = Math.min(this.breakCurrentPage * this.breakPageSize, this.breakRequests.length);
        return `${start}-${end} / ${this.breakRequests.length}`;
    }

    // 휴식 신청 페이징
    get paginatedBreakRequests() {
        if (!this.breakRequests || this.breakRequests.length === 0) return [];
        const start = (this.breakCurrentPage - 1) * this.breakPageSize;
        const end = start + this.breakPageSize;
        return this.breakRequests.slice(start, end);
    }

    get breakTotalPages() {
        if (!this.breakRequests || this.breakRequests.length === 0) return 0;
        return Math.ceil(this.breakRequests.length / this.breakPageSize);
    }

    get breakPaginationInfo() {
        if (!this.breakRequests || this.breakRequests.length === 0) return '0 / 0';
        const start = (this.breakCurrentPage - 1) * this.breakPageSize + 1;
        const end = Math.min(this.breakCurrentPage * this.breakPageSize, this.breakRequests.length);
        return `${start}-${end} / ${this.breakRequests.length}`;
    }

    get hasBreakPagination() {
        return this.breakTotalPages > 1;
    }

    // 탭 전환
    handleTabChange(event) {
        const tab = event.currentTarget.dataset.tab;
        this.selectedTab = tab;
        if (tab === 'breaks') {
            // 필터를 'All'로 초기화
            this.breakAgentFilter = 'All';
            this.breakStatusFilter = 'All';
            // 날짜가 설정되지 않았으면 오늘 날짜로 초기화
            if (!this.breakStartDate || !this.breakEndDate) {
                const today = new Date();
                const todayStr = today.toISOString().split('T')[0];
                this.breakStartDate = todayStr;
                this.breakEndDate = todayStr;
            }
            this.loadBreakRequests();
        } else if (tab === 'leaves') {
            // 필터를 'All'로 초기화
            this.leaveAgentFilter = 'All';
            this.leaveStatusFilter = 'All';
            // 날짜가 설정되지 않았으면 오늘 날짜로 초기화
            if (!this.leaveStartDate || !this.leaveEndDate) {
                const today = new Date();
                const todayStr = today.toISOString().split('T')[0];
                this.leaveStartDate = todayStr;
                this.leaveEndDate = todayStr;
            }
            this.loadLeaveRequests();
        } else if (tab === 'status') {
            // 상담사 현황 탭인 경우 데이터 새로고침
            if (this.wiredResult) {
                refreshApex(this.wiredResult);
            }
        } else if (tab === 'worktime') {
            // 필터를 'All'로 초기화
            this.workTimeAgentFilter = 'All';
            this.workTimeStatusFilter = 'All';
            // 날짜가 설정되지 않았으면 오늘 날짜로 초기화
            if (!this.workTimeStartDate || !this.workTimeEndDate) {
                const today = new Date();
                const todayStr = today.toISOString().split('T')[0];
                this.workTimeStartDate = todayStr;
                this.workTimeEndDate = todayStr;
            }
            this.loadWorkTimes();
        }
    }

    // 새로고침 핸들러
    handleRefresh() {
        if (this.selectedTab === 'status') {
            // 상담사 현황 탭
            if (this.wiredResult) {
                refreshApex(this.wiredResult);
            }
        } else if (this.selectedTab === 'worktime') {
            // 근무 관리 탭
            this.loadWorkTimes();
        } else if (this.selectedTab === 'breaks') {
            // 휴식 신청 관리 탭
            this.loadBreakRequests();
        } else if (this.selectedTab === 'leaves') {
            // 휴가 신청 관리 탭
            this.loadLeaveRequests();
        }
        this.showToast('알림', '데이터를 새로고침했습니다.', 'success');
    }

    // 휴식 신청 목록 로드
    loadBreakRequests() {
        this.isLoadingBreaks = true;
        const today = new Date();
        const todayStr = today.toISOString().split('T')[0];
        // 날짜가 없으면 오늘 날짜로 설정
        const startDate = this.breakStartDate || todayStr;
        const endDate = this.breakEndDate || todayStr;
        const statusFilter = this.breakStatusFilter === 'All' ? null : this.breakStatusFilter;
        const agentFilter = this.breakAgentFilter === 'All' ? null : this.breakAgentFilter;
        
        getTeamBreakRequests({ 
            startDate: startDate, 
            endDate: endDate, 
            statusFilter: statusFilter,
            agentFilter: agentFilter
        })
        .then(result => {
            // 취소 가능 여부 추가 (Approved 상태만 취소 가능) 및 포맷팅
            this.breakRequests = (result || []).map(br => {
                const startTime = this.formatTime(br.startTime);
                const endTime = this.formatTime(br.endTime);
                return {
                    id: br.id,
                    name: br.name,
                    requesterId: br.requesterId,
                    requesterName: br.requesterName,
                    dateValue: br.dateValue,
                    breakType: br.breakType,
                    startTime: br.startTime,
                    endTime: br.endTime,
                    durationMinutes: br.durationMinutes,
                    status: br.status,
                    reason: br.reason || '', // Reason 필드 명시적으로 포함
                    createdDate: br.createdDate,
                    canCancel: br.status === 'Approved',
                    dateLabel: this.formatDate(br.dateValue),
                    timeLabel: startTime && endTime ? `${startTime} ~ ${endTime}` : '',
                    statusLabel: this.getBreakStatusLabel(br.status),
                    durationLabel: br.durationMinutes ? br.durationMinutes + '분' : ''
                };
            });
            // 페이지 초기화
            this.breakCurrentPage = 1;
            this.isLoadingBreaks = false;
        })
        .catch(error => {
            console.error('Error loading break requests:', error);
            this.showToast('오류', this.getErrorMessage(error), 'error');
            this.isLoadingBreaks = false;
        });
    }

    // 날짜 필터 변경 (휴식)
    handleDateChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        if (field === 'startDate') {
            this.breakStartDate = value;
        } else if (field === 'endDate') {
            this.breakEndDate = value;
        }
        if (this.selectedTab === 'breaks') {
            this.loadBreakRequests();
        }
    }

    // 날짜 필터 변경 (휴가)
    handleLeaveDateChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        if (field === 'startDate') {
            this.leaveStartDate = value;
        } else if (field === 'endDate') {
            this.leaveEndDate = value;
        }
        if (this.selectedTab === 'leaves') {
            this.loadLeaveRequests();
        }
    }

    // 상태 필터 변경 (휴식)
    handleStatusFilterChange(event) {
        this.breakStatusFilter = event.detail.value;
        if (this.selectedTab === 'breaks') {
            this.loadBreakRequests();
        }
    }

    // 상담사 필터 변경 (휴식)
    handleBreakAgentFilterChange(event) {
        this.breakAgentFilter = event.detail.value;
        if (this.selectedTab === 'breaks') {
            this.loadBreakRequests();
        }
    }

    // 상태 필터 변경 (휴가)
    handleLeaveStatusFilterChange(event) {
        this.leaveStatusFilter = event.detail.value;
        if (this.selectedTab === 'leaves') {
            this.loadLeaveRequests();
        }
    }

    // 상담사 필터 변경 (휴가)
    handleLeaveAgentFilterChange(event) {
        this.leaveAgentFilter = event.detail.value;
        if (this.selectedTab === 'leaves') {
            this.loadLeaveRequests();
        }
    }

    // 근무 시간 목록 로드
    loadWorkTimes() {
        this.isLoadingWorkTimes = true;
        const today = new Date();
        const todayStr = today.toISOString().split('T')[0];
        // 날짜가 없으면 오늘 날짜로 설정
        const startDate = this.workTimeStartDate || todayStr;
        const endDate = this.workTimeEndDate || todayStr;
        const agentFilter = this.workTimeAgentFilter === 'All' ? null : this.workTimeAgentFilter;
        const statusFilter = this.workTimeStatusFilter === 'All' ? null : this.workTimeStatusFilter;
        
        getTeamWorkTimes({ 
            startDate: startDate, 
            endDate: endDate,
            agentFilter: agentFilter,
            statusFilter: statusFilter
        })
        .then(result => {
            // 포맷팅
            this.workTimes = (result || []).map(wt => {
                const startTime = wt.workStartTime ? this.formatTime(wt.workStartTime) : null;
                // 요구사항: 근무 중(On Duty)에는 퇴근 시간이 보이면 안 됨(데이터에 값이 남아있어도 숨김)
                const endTime = (wt.status === 'On Duty') ? null : (wt.workEndTime ? this.formatTime(wt.workEndTime) : null);
                return {
                    id: wt.id,
                    name: wt.name,
                    userId: wt.userId,
                    userName: wt.userName,
                    workDate: wt.workDate,
                    workStartTime: wt.workStartTime,
                    // On Duty일 때는 UI에서 End Time을 숨기므로 null로 정규화
                    workEndTime: (wt.status === 'On Duty') ? null : wt.workEndTime,
                    status: wt.status,
                    createdDate: wt.createdDate,
                    dateLabel: this.formatDate(wt.workDate),
                    startTimeLabel: startTime || '-',
                    endTimeLabel: endTime || '-',
                    statusLabel: wt.status === 'On Duty' ? '근무중' : (wt.status === 'Off Duty' ? '퇴근' : ''),
                    statusClass: wt.status === 'On Duty' ? 'status-badge on-duty' : 'status-badge off-duty'
                };
            });
            // 페이지 초기화
            this.workTimeCurrentPage = 1;
            this.isLoadingWorkTimes = false;
        })
        .catch(error => {
            console.error('Error loading work times:', error);
            this.showToast('오류', this.getErrorMessage(error), 'error');
            this.isLoadingWorkTimes = false;
        });
    }

    // 날짜 필터 변경 (근무 시간)
    handleWorkTimeDateChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        if (field === 'startDate') {
            this.workTimeStartDate = value;
        } else if (field === 'endDate') {
            this.workTimeEndDate = value;
        }
        if (this.selectedTab === 'worktime') {
            this.loadWorkTimes();
        }
    }

    // 상담사 필터 변경 (근무 시간)
    handleWorkTimeAgentFilterChange(event) {
        this.workTimeAgentFilter = event.detail.value;
        if (this.selectedTab === 'worktime') {
            this.loadWorkTimes();
        }
    }

    // 상태 필터 변경 (근무 시간)
    handleWorkTimeStatusFilterChange(event) {
        this.workTimeStatusFilter = event.detail.value;
        if (this.selectedTab === 'worktime') {
            this.loadWorkTimes();
        }
    }

    // 관리자 취소
    handleCancelBreak(event) {
        const breakId = event.currentTarget.dataset.id;
        if (!breakId) return;
        
        if (!confirm('이 휴식 신청을 취소(롤백)하시겠습니까?')) {
            return;
        }
        
        cancelBreakByManager({ requestId: breakId })
        .then(() => {
            this.showToast('성공', '휴식 신청이 취소되었습니다.', 'success');
            this.loadBreakRequests();
            // 상태 대시보드도 새로고침
            if (this.wiredResult) {
                refreshApex(this.wiredResult);
            }
        })
        .catch(error => {
            console.error('Error canceling break:', error);
            this.showToast('오류', this.getErrorMessage(error), 'error');
        });
    }

    // 페이징 핸들러 (휴식)
    handleBreakPageChange(event) {
        const page = parseInt(event.currentTarget.dataset.page, 10);
        if (page >= 1 && page <= this.breakTotalPages) {
            this.breakCurrentPage = page;
        }
    }

    handleBreakPrevPage() {
        if (this.breakCurrentPage > 1) {
            this.breakCurrentPage--;
        }
    }

    handleBreakNextPage() {
        if (this.breakCurrentPage < this.breakTotalPages) {
            this.breakCurrentPage++;
        }
    }

    // 페이징 핸들러 (휴가)
    handleLeavePageChange(event) {
        const page = parseInt(event.currentTarget.dataset.page, 10);
        if (page >= 1 && page <= this.leaveTotalPages) {
            this.leaveCurrentPage = page;
        }
    }

    handleLeavePrevPage() {
        if (this.leaveCurrentPage > 1) {
            this.leaveCurrentPage--;
        }
    }

    handleLeaveNextPage() {
        if (this.leaveCurrentPage < this.leaveTotalPages) {
            this.leaveCurrentPage++;
        }
    }

    // 페이징 핸들러 (근무 시간)
    handleWorkTimePageChange(event) {
        const page = parseInt(event.currentTarget.dataset.page, 10);
        if (page >= 1 && page <= this.workTimeTotalPages) {
            this.workTimeCurrentPage = page;
        }
    }

    handleWorkTimePrevPage() {
        if (this.workTimeCurrentPage > 1) {
            this.workTimeCurrentPage--;
        }
    }

    handleWorkTimeNextPage() {
        if (this.workTimeCurrentPage < this.workTimeTotalPages) {
            this.workTimeCurrentPage++;
        }
    }

    // 페이지 번호 배열 생성 (첫 페이지, 중간 페이지들, 마지막 페이지 포함)
    get breakPageNumbers() {
        const pages = [];
        const total = this.breakTotalPages;
        const current = this.breakCurrentPage;
        
        if (total <= 7) {
            // 총 페이지가 7개 이하면 모두 표시
            for (let i = 1; i <= total; i++) {
                pages.push({
                    value: i,
                    label: String(i),
                    variant: current === i ? 'brand' : 'neutral',
                    isNumber: true,
                    isEllipsis: false
                });
            }
        } else {
            // 첫 페이지
            pages.push({
                value: 1,
                label: '1',
                variant: current === 1 ? 'brand' : 'neutral',
                isNumber: true,
                isEllipsis: false
            });
            
            // 현재 페이지 주변 계산
            let start = Math.max(2, current - 1);
            let end = Math.min(total - 1, current + 1);
            
            // 첫 페이지와 중간 사이에 생략 표시
            if (start > 2) {
                pages.push({
                    value: null,
                    label: '...',
                    variant: 'neutral',
                    isNumber: false,
                    isEllipsis: true
                });
            }
            
            // 중간 페이지들
            for (let i = start; i <= end; i++) {
                pages.push({
                    value: i,
                    label: String(i),
                    variant: current === i ? 'brand' : 'neutral',
                    isNumber: true,
                    isEllipsis: false
                });
            }
            
            // 중간과 마지막 사이에 생략 표시
            if (end < total - 1) {
                pages.push({
                    value: null,
                    label: '...',
                    variant: 'neutral',
                    isNumber: false,
                    isEllipsis: true
                });
            }
            
            // 마지막 페이지
            pages.push({
                value: total,
                label: String(total),
                variant: current === total ? 'brand' : 'neutral',
                isNumber: true,
                isEllipsis: false
            });
        }
        return pages;
    }

    get leavePageNumbers() {
        const pages = [];
        const total = this.leaveTotalPages;
        const current = this.leaveCurrentPage;
        
        if (total <= 7) {
            // 총 페이지가 7개 이하면 모두 표시
            for (let i = 1; i <= total; i++) {
                pages.push({
                    value: i,
                    label: String(i),
                    variant: current === i ? 'brand' : 'neutral',
                    isNumber: true,
                    isEllipsis: false
                });
            }
        } else {
            // 첫 페이지
            pages.push({
                value: 1,
                label: '1',
                variant: current === 1 ? 'brand' : 'neutral',
                isNumber: true,
                isEllipsis: false
            });
            
            // 현재 페이지 주변 계산
            let start = Math.max(2, current - 1);
            let end = Math.min(total - 1, current + 1);
            
            // 첫 페이지와 중간 사이에 생략 표시
            if (start > 2) {
                pages.push({
                    value: null,
                    label: '...',
                    variant: 'neutral',
                    isNumber: false,
                    isEllipsis: true
                });
            }
            
            // 중간 페이지들
            for (let i = start; i <= end; i++) {
                pages.push({
                    value: i,
                    label: String(i),
                    variant: current === i ? 'brand' : 'neutral',
                    isNumber: true,
                    isEllipsis: false
                });
            }
            
            // 중간과 마지막 사이에 생략 표시
            if (end < total - 1) {
                pages.push({
                    value: null,
                    label: '...',
                    variant: 'neutral',
                    isNumber: false,
                    isEllipsis: true
                });
            }
            
            // 마지막 페이지
            pages.push({
                value: total,
                label: String(total),
                variant: current === total ? 'brand' : 'neutral',
                isNumber: true,
                isEllipsis: false
            });
        }
        return pages;
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
            variant: variant
        });
        this.dispatchEvent(evt);
    }

    // 날짜 포맷
    formatDate(dateValue) {
        if (!dateValue) return '';
        const date = new Date(dateValue);
        return date.toLocaleDateString('ko-KR');
    }

    // 시간 포맷
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

    // 휴가 신청 목록 로드
    loadLeaveRequests() {
        this.isLoadingLeaves = true;
        const today = new Date();
        const todayStr = today.toISOString().split('T')[0];
        // 날짜가 없으면 오늘 날짜로 설정
        const startDate = this.leaveStartDate || todayStr;
        const endDate = this.leaveEndDate || todayStr;
        const statusFilter = this.leaveStatusFilter === 'All' ? null : this.leaveStatusFilter;
        const agentFilter = this.leaveAgentFilter === 'All' ? null : this.leaveAgentFilter;
        
        getTeamLeaveRequests({ 
            startDate: startDate, 
            endDate: endDate, 
            statusFilter: statusFilter,
            agentFilter: agentFilter
        })
        .then(result => {
            // 포맷팅
            this.leaveRequests = (result || []).map(lr => {
                return {
                    ...lr,
                    startDateLabel: this.formatDate(lr.startDate),
                    endDateLabel: this.formatDate(lr.endDate),
                    dateRangeLabel: this.formatDateRange(lr.startDate, lr.endDate, lr.startSlot, lr.endSlot),
                    statusLabel: this.getLeaveRequestStatusLabel(lr.status),
                    daysLabel: lr.days ? lr.days + '일' : ''
                };
            });
            // 페이지 초기화
            this.leaveCurrentPage = 1;
            this.isLoadingLeaves = false;
        })
        .catch(error => {
            console.error('Error loading leave requests:', error);
            this.showToast('오류', this.getErrorMessage(error), 'error');
            this.isLoadingLeaves = false;
        });
    }

    // 날짜 범위 포맷
    formatDateRange(startDate, endDate, startSlot, endSlot) {
        if (!startDate || !endDate) return '';
        // Leave 신청 폼과 동일한 형태로 표기(YYYY-MM-DD + 필요 시 AM/PM)
        const start = (startDate || '').toString();
        const end = (endDate || '').toString();
        const sSlot = (startSlot || '').toString();
        const eSlot = (endSlot || '').toString();

        const isFullDayEdge = (sSlot === 'AM' && eSlot === 'PM');
        const isSameDate = start === end;

        // 종일(AM~PM)인 경우 슬롯 표기 불필요
        if (isFullDayEdge) {
            return isSameDate ? start : `${start} ~ ${end}`;
        }

        // 반차/부분일(슬롯이 AM/PM으로 의미가 있을 때): 신청한 양식 그대로 노출
        // - 같은 날 AM~AM 또는 PM~PM: "YYYY-MM-DD AM|PM"
        // - 기간: "YYYY-MM-DD AM|PM ~ YYYY-MM-DD AM|PM"
        if (isSameDate) {
            if (sSlot && sSlot === eSlot) return `${start} ${sSlot}`;
            if (sSlot && eSlot) return `${start} ${sSlot} ~ ${end} ${eSlot}`;
            return start;
        }

        if (sSlot && eSlot) return `${start} ${sSlot} ~ ${end} ${eSlot}`;
        return `${start} ~ ${end}`;
    }

    // 슬롯 라벨
    getSlotLabel(slot) {
        if (slot === 'AM') return '오전';
        if (slot === 'PM') return '오후';
        return slot || '';
    }

    // 상태 라벨
    getBreakStatusLabel(status) {
        const labels = {
            'Draft': '초안',
            'Approved': '승인됨',
            'Cancelled': '취소됨'
        };
        return labels[status] || status;
    }

    getLeaveRequestStatusLabel(status) {
        const labels = {
            'Draft': '초안',
            'Submitted': '제출됨',
            'Approved': '승인됨',
            'Rejected': '반려됨',
            'Cancelled': '취소됨',
            'CancelSubmitted': '취소 요청됨'
        };
        return labels[status] || status;
    }

    get isStatusTab() {
        return this.selectedTab === 'status';
    }

    get isBreaksTab() {
        return this.selectedTab === 'breaks';
    }

    get isLeavesTab() {
        return this.selectedTab === 'leaves';
    }
    
    // 탭 링크용 클래스 (현재 탭 강조)
    get statusTabClass() {
        return `slds-tabs_default__link tab-link ${this.isStatusTab ? 'tab-active' : ''}`;
    }

    get leavesTabClass() {
        return `slds-tabs_default__link tab-link ${this.isLeavesTab ? 'tab-active' : ''}`;
    }

    get breaksTabClass() {
        return `slds-tabs_default__link tab-link ${this.isBreaksTab ? 'tab-active' : ''}`;
    }

    get isWorkTimeTab() {
        return this.selectedTab === 'worktime';
    }

    get workTimeTabClass() {
        return `slds-tabs_default__link tab-link ${this.isWorkTimeTab ? 'tab-active' : ''}`;
    }

    get hasLeaveRequests() {
        return this.leaveRequests && this.leaveRequests.length > 0;
    }

    get hasWorkTimes() {
        return this.workTimes && this.workTimes.length > 0;
    }

    // 근무 시간 페이징
    get paginatedWorkTimes() {
        if (!this.workTimes || this.workTimes.length === 0) return [];
        const start = (this.workTimeCurrentPage - 1) * this.workTimePageSize;
        const end = start + this.workTimePageSize;
        return this.workTimes.slice(start, end);
    }

    get workTimeTotalPages() {
        if (!this.workTimes || this.workTimes.length === 0) return 0;
        return Math.ceil(this.workTimes.length / this.workTimePageSize);
    }

    get workTimePaginationInfo() {
        if (!this.workTimes || this.workTimes.length === 0) return '0 / 0';
        const start = (this.workTimeCurrentPage - 1) * this.workTimePageSize + 1;
        const end = Math.min(this.workTimeCurrentPage * this.workTimePageSize, this.workTimes.length);
        return `${start}-${end} / ${this.workTimes.length}`;
    }

    get hasWorkTimePagination() {
        return this.workTimeTotalPages > 1;
    }

    get isWorkTimeFirstPage() {
        return this.workTimeCurrentPage === 1;
    }

    get isWorkTimeLastPage() {
        return this.workTimeCurrentPage === this.workTimeTotalPages;
    }

    get workTimePageNumbers() {
        if (!this.hasWorkTimePagination) return [];
        const pages = [];
        const total = this.workTimeTotalPages;
        const current = this.workTimeCurrentPage;
        
        if (total <= 7) {
            for (let i = 1; i <= total; i++) {
                pages.push({ value: i, label: String(i), variant: i === current ? 'brand' : 'neutral', isNumber: true, isEllipsis: false });
            }
        } else {
            if (current <= 3) {
                for (let i = 1; i <= 4; i++) {
                    pages.push({ value: i, label: String(i), variant: i === current ? 'brand' : 'neutral', isNumber: true, isEllipsis: false });
                }
                pages.push({ value: null, label: '...', variant: 'neutral', isNumber: false, isEllipsis: true });
                pages.push({ value: total, label: String(total), variant: 'neutral', isNumber: true, isEllipsis: false });
            } else if (current >= total - 2) {
                pages.push({ value: 1, label: '1', variant: 'neutral', isNumber: true, isEllipsis: false });
                pages.push({ value: null, label: '...', variant: 'neutral', isNumber: false, isEllipsis: true });
                for (let i = total - 3; i <= total; i++) {
                    pages.push({ value: i, label: String(i), variant: i === current ? 'brand' : 'neutral', isNumber: true, isEllipsis: false });
                }
            } else {
                pages.push({ value: 1, label: '1', variant: 'neutral', isNumber: true, isEllipsis: false });
                pages.push({ value: null, label: '...', variant: 'neutral', isNumber: false, isEllipsis: true });
                for (let i = current - 1; i <= current + 1; i++) {
                    pages.push({ value: i, label: String(i), variant: i === current ? 'brand' : 'neutral', isNumber: true, isEllipsis: false });
                }
                pages.push({ value: null, label: '...', variant: 'neutral', isNumber: false, isEllipsis: true });
                pages.push({ value: total, label: String(total), variant: 'neutral', isNumber: true, isEllipsis: false });
            }
        }
        return pages;
    }

    // 휴가 신청 페이징
    get paginatedLeaveRequests() {
        if (!this.leaveRequests || this.leaveRequests.length === 0) return [];
        const start = (this.leaveCurrentPage - 1) * this.leavePageSize;
        const end = start + this.leavePageSize;
        return this.leaveRequests.slice(start, end);
    }

    get leaveTotalPages() {
        if (!this.leaveRequests || this.leaveRequests.length === 0) return 0;
        return Math.ceil(this.leaveRequests.length / this.leavePageSize);
    }

    get leavePaginationInfo() {
        if (!this.leaveRequests || this.leaveRequests.length === 0) return '0 / 0';
        const start = (this.leaveCurrentPage - 1) * this.leavePageSize + 1;
        const end = Math.min(this.leaveCurrentPage * this.leavePageSize, this.leaveRequests.length);
        return `${start}-${end} / ${this.leaveRequests.length}`;
    }

    get hasBreakPagination() {
        return this.breakTotalPages > 1;
    }

    get hasLeavePagination() {
        return this.leaveTotalPages > 1;
    }

    // 페이징 상태 getter (휴식)
    get isBreakFirstPage() {
        return this.breakCurrentPage === 1;
    }

    get isBreakLastPage() {
        return this.breakCurrentPage === this.breakTotalPages;
    }

    // 페이징 상태 getter (휴가)
    get isLeaveFirstPage() {
        return this.leaveCurrentPage === 1;
    }

    get isLeaveLastPage() {
        return this.leaveCurrentPage === this.leaveTotalPages;
    }

    get statusFilterOptions() {
        return [
            { label: '전체', value: 'All' },
            { label: '승인됨', value: 'Approved' },
            { label: '취소됨', value: 'Cancelled' },
            { label: '초안', value: 'Draft' }
        ];
    }

    get leaveStatusFilterOptions() {
        return [
            { label: '전체', value: 'All' },
            { label: '초안', value: 'Draft' },
            { label: '제출됨', value: 'Submitted' },
            { label: '승인됨', value: 'Approved' },
            { label: '반려됨', value: 'Rejected' },
            { label: '취소됨', value: 'Cancelled' },
            { label: '취소 요청됨', value: 'CancelSubmitted' }
        ];
    }

    get breakAgentFilterOptions() {
        const options = [{ label: '전체', value: 'All' }];
        if (this.teamMembers && this.teamMembers.length > 0) {
            options.push(...this.teamMembers);
        }
        return options;
    }

    get leaveAgentFilterOptions() {
        const options = [{ label: '전체', value: 'All' }];
        if (this.teamMembers && this.teamMembers.length > 0) {
            options.push(...this.teamMembers);
        }
        return options;
    }

    get workTimeAgentFilterOptions() {
        const options = [{ label: '전체', value: 'All' }];
        if (this.teamMembers && this.teamMembers.length > 0) {
            options.push(...this.teamMembers);
        }
        return options;
    }

    get workTimeStatusFilterOptions() {
        return [
            { label: '전체', value: 'All' },
            { label: '근무중', value: 'On Duty' },
            { label: '퇴근', value: 'Off Duty' }
        ];
    }
}
