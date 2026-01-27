# 금주 개인 업무 실적 : 휴가/휴식 관리 시스템

## 1. 휴가 신청 관리 (상담사)

### 1.1 신청 및 초안 관리
•	초안 저장/수정 (1건만 유지, 새 초안 생성 시 기존 초안 자동 삭제)
•	휴가 신청 제출 (Manager 자동 할당, Approval Process 자동 시작)
•	실시간 일수 계산 (주말 제외, AM/PM 슬롯 지원)
•	중복 기간 검증 (동일 사용자의 겹치는 휴가 신청 차단)
•	승인 전 즉시 취소 (Draft/Submitted 상태)
•	승인 후 취소 요청 (CancelSubmitted 상태로 전환, 매니저 승인 필요)

### 1.2 내역 조회
•	날짜 범위별 휴가 내역 조회 (최근 3개월 ~ 향후 3개월)
•	상태별 필터링 (Draft, Submitted, Approved, Rejected, Cancelled 등)
•	무한 스크롤 페이징 (추가 로드 기능)
•	정렬 (생성일 기준 내림차순)

### 1.3 캘린더 뷰
•	월별 캘린더 표시 (휴가/휴식 통합)
•	월 이동 기능 (이전/다음 달)
•	승인된 휴가 시각화 (날짜별 색상 구분)
•	다일 휴가 표시 (시작일~종료일 범위)

### 1.4 잔여 휴가 조회
•	연도별 잔여 휴가 조회
•	사용/잔여 일수 표시
•	모달 팝업으로 상세 정보 표시

### 1.5 알림 기능
•	최종 휴가 승인 완료 시 벨 알림 (Custom Notification)
•	최종 휴가 취소 승인 완료 시 벨 알림
•	레코드 페이지로 자동 이동

## 2. 휴식 신청 관리 (상담사)

### 2.1 신청 및 자동 승인
•	휴식 타입 선택 (Morning Break, Lunch, Afternoon Break)
•	날짜 및 시간 입력 (또는 자동 설정)
•	시간 범위 검증 (Morning Break: 8-12시, Afternoon Break: 13-18시)
•	중복 휴식 검증 (동일 날짜/타입 중복 신청 차단)
•	자동 승인 (제출 시 즉시 Approved 상태)
•	초안 저장 기능

### 2.2 실시간 타이머
•	승인된 휴식 자동 감지 및 타이머 시작
•	남은 시간 실시간 표시 (초 단위)
•	타이머 자동 복원 (페이지 새로고침 시에도 유지)
•	타이머 종료 시 자동 정리

### 2.3 Omni-Channel 상태 연동
•	Morning Break/Afternoon Break/Lunch 승인 시 자동 상태 변경 (Online → Busy)
•	타이머 종료 시 자동 상태 복원 (Busy → Online)
•	Offline 상태일 때는 상태 변경 제외
•	Visualforce Page 기반 `sforce.console.presence` API 연동
•	상태 변경 큐잉 및 재시도 로직 (안정성 향상)
•	디바운싱 로직 (중복 상태 변경 방지)

### 2.4 내역 조회
•	날짜 범위별 휴식 내역 조회 (최근 3개월 ~ 향후 3개월)
•	상태별 필터링 (Draft, Approved, Cancelled)
•	무한 스크롤 페이징
•	정렬 (생성일 기준 내림차순)

### 2.5 캘린더 뷰
•	월별 캘린더 표시 (휴가와 통합)
•	승인된 휴식 시각화 (날짜별 표시)
•	시간 정보 포함 표시

## 3. 매니저 대시보드

### 3.1 팀원 상태 조회
•	당일 기준 팀원 상태 실시간 조회
•	휴가 상태 표시 (On Leave / Available)
•	휴식 상태 표시 (Morning Break, Lunch, Afternoon Break)
•	상태별 구분 (Used / Scheduled / Available)
•	30초 간격 자동 새로고침
•	팀원 이름순 정렬

### 3.2 휴가 신청 관리
•	팀원 휴가 신청 목록 조회 (날짜 범위 필터)
•	상태별 필터링 (All, Submitted, Approved, Rejected, Cancelled 등)
•	상담사별 필터링 (특정 팀원만 조회)
•	페이징 기능 (5건씩 표시)
•	상세 정보 표시 (날짜, 슬롯, 일수, 사유 등)
•	승인/반려 기능 (Approval Process 연동)
•	취소된 휴가 신청은 승인 불가 (시스템 차단)

### 3.3 휴식 신청 관리
•	팀원 휴식 신청 목록 조회 (날짜 범위 필터)
•	상태별 필터링 (All, Draft, Approved, Cancelled)
•	상담사별 필터링 (특정 팀원만 조회)
•	페이징 기능 (5건씩 표시)
•	상세 정보 표시 (날짜, 타입, 시간, 사유 등)
•	관리자 롤백 기능 (승인된 휴식 취소)
•	Reason 필드 표시

### 3.4 UI/UX 개선
•	탭 기반 인터페이스 (상태 / 휴식 관리 / 휴가 관리)
•	활성 탭 시각적 강조 (파란색 밑줄, 볼드)
•	일관된 테이블 스타일링 (간격 통일)
•	새로고침 버튼 (수동 새로고침)
•	로딩 상태 표시

## 4. 시스템 통합 기능

### 4.1 Approval Process 연동
•	휴가 신청 승인 프로세스 (1단계: Manager)
•	휴가 취소 승인 프로세스 (1단계: Manager)
•	자동 Approver 할당 (Requester의 ManagerId)
•	상태 자동 업데이트 (Approved/Rejected/Cancelled)

### 4.2 캘린더 이벤트 연동
•	휴가 승인 시 자동 Event 생성 (WhatId로 Leave_Request__c 연결)
•	휴가 취소 요청 시 Event 자동 삭제 (숨김)
•	취소 반려 시 Event 재생성
•	CalendarEventId__c 필드에 Event Id 저장

### 4.3 권한 관리
•	Permission Set 기반 접근 제어
•	상담사 권한 (Leave_Break_Employee_Permission_Set)
•	매니저 권한 (Leave_Break_Manager_Permission_Set)
•	OWD 설정 (Private 기본값)
•	매니저는 팀원 레코드만 조회 가능 (Read-only)

### 4.4 데이터 검증
•	휴가 중복 기간 검증 (LeaveService)
•	휴식 중복 검증 (BreakService)
•	시간 범위 검증 (Break Type별 허용 시간)
•	Duration 자동 계산 (주말 제외, AM/PM 슬롯 고려)

## 5. UI/UX 개선

### 5.1 탭 인터페이스
•	상담사: 휴가 신청 / 휴식 신청 / 내 신청 내역 / 캘린더
•	매니저: 팀원 상태 / 휴식 신청 관리 / 휴가 신청 관리
•	활성 탭 시각적 강조 (파란색 밑줄, 볼드 텍스트)
•	탭 전환 시 폼 데이터 초기화

### 5.2 폼 기능
•	실시간 일수 계산 (휴가)
•	실시간 Duration 계산 (휴식)
•	초안 자동 로드 (휴가)
•	제출 성공 시 폼 초기화 및 성공 메시지
•	에러 메시지 표시

### 5.3 테이블 스타일링
•	일관된 간격 및 정렬
•	상태별 배지 표시 (색상 구분)
•	날짜/시간 포맷팅
•	빈 데이터 메시지

### 5.4 반응형 디자인
•	Utility Bar 최적화
•	모달 팝업 (잔여 휴가 조회)
•	무한 스크롤 (내역 조회)

## 6. 기술 구현

### 6.1 Apex 클래스
•	LeaveRequestController (휴가 CRUD, Approval Process)
•	BreakRequestController (휴식 CRUD, 자동 승인, 타이머 복원)
•	ManagerDashboardController (팀원 상태, 팀원 신청 목록)
•	LeaveService (일수 계산, 중복 검증)
•	BreakService (Duration 계산, 시간 범위 검증, 중복 검증)
•	LeaveBalanceController (잔여 휴가 조회)
•	OmniPresenceHelper (Omni-Channel 상태 ID 조회)
•	LeaveRequestTriggerHandler (캘린더 연동, 알림, Sharing)
•	BreakRequestTriggerHandler (캘린더 연동)

### 6.2 Lightning Web Components
•	utilityRequest (상담사용 통합 컴포넌트)
•	managerDashboard (매니저용 대시보드)

### 6.3 Visualforce Page
•	utilityRequestOmniStatus (Omni-Channel 상태 변경용, 최소화된 UI)

### 6.4 통합 API
•	`sforce.console.presence` API (Omni-Channel 상태 변경)
•	Custom Events (LWC ↔ Visualforce 통신)
•	Platform Events (실시간 알림, 향후 확장 가능)

## 7. Git 연동
•	코드 버전 관리
•	사내 Git 연동 준비 (이전 작업 예정)
