# Salesforce Inner Messenger - 완전 배포 가이드

**프로젝트**: Salesforce Inner Messenger (사내 실시간 메신저 + 휴가/휴무 관리 + 근무 시간 관리)  
**버전**: 2.0.0  
**배포 메인 파일**: `manifest/package.xml`

---

## 🆕 버전 2.0.0 주요 변경사항 (2025-03-13)

### **데이터 보관 정책 개선**
- ✅ **2단계 보관 정책 도입**: 3개월 아카이브 → 1년 삭제
- ✅ **아카이브 기능 추가**: 오래된 메시지를 JSON 형식으로 저장
- ✅ **데이터 용량 절감**: 레코드 수 대폭 감소로 저장 비용 절감
- ✅ **자동화된 배치 작업**: 아카이브 및 삭제 배치 자동 실행

### **새로운 기능**
- ✅ **아카이브 메시지 조회**: 오래된 메시지도 자동으로 조회 가능
- ✅ **청크 단위 저장**: 메시지를 청크 단위로 분할하여 저장
- ✅ **세션 메타데이터 관리**: 활성/아카이브 메시지 수 자동 추적

### **새로운 객체 및 클래스**
- ✅ `Inner_Chat_Message_Archive__c`: 아카이브 메시지 저장 객체
- ✅ `ChatMessageArchiveBatch`: 아카이브 배치 클래스
- ✅ `ChatMessageArchiveScheduler`: 아카이브 스케줄러
- ✅ `ChatMessageCleanupBatch`: 업데이트 (아카이브 청크 삭제 기능 추가)

### **개선 사항**
- ✅ `ChatController`: 아카이브 메시지 조회 로직 추가
- ✅ `Inner_Chat_Session__c`: 아카이브 관련 필드 추가
- ✅ 배치 작업 모니터링 및 관리 기능 강화

---

## 📋 프로젝트 개요

### **채팅 기록 데이터 보관 정책 (2단계 보관 정책)**

채팅 메시지는 **2단계 보관 정책**을 따릅니다:

```
┌─────────────────────────────────────────┐
│ 0 ~ 3개월: 활성 메시지 (개별 레코드)    │
│ Inner_Chat_Message__c                   │
│ → 빠른 조회, 실시간 페이징              │
└─────────────────────────────────────────┘
           ↓ (ChatMessageArchiveBatch)
           매일 오전 3시 실행
┌─────────────────────────────────────────┐
│ 3개월 ~ 1년: 아카이브 메시지 (JSON)     │
│ Inner_Chat_Message_Archive__c           │
│ → 필요시에만 조회, 데이터 용량 절감      │
└─────────────────────────────────────────┘
           ↓ (ChatMessageCleanupBatch)
           매일 오전 2시 실행
┌─────────────────────────────────────────┐
│ 1년 이상: 최종 삭제                     │
│ (활성 메시지 + 아카이브 청크 모두 삭제) │
└─────────────────────────────────────────┘
```

#### **1단계: 아카이브 (3개월 이상)**
- **배치 클래스**: `ChatMessageArchiveBatch`
- **실행 시간**: 매일 오전 3시
- **동작**: 3개월 이상 된 활성 메시지를 JSON 형식으로 변환하여 `Inner_Chat_Message_Archive__c`에 저장
- **효과**: 레코드 수 대폭 감소, 데이터 용량 절감
- **특징**: 
  - 청크 단위 저장 (최대 100개 메시지/청크)
  - 세션별 메타데이터 자동 업데이트
  - 기존 메시지 레코드 삭제

#### **2단계: 최종 삭제 (1년 이상)**
- **배치 클래스**: `ChatMessageCleanupBatch`
- **실행 시간**: 매일 오전 2시
- **동작**: 
  - 1년 이상 된 활성 메시지 삭제
  - 1년 이상 된 아카이브 청크 삭제
  - 첨부 파일(ContentDocument)도 함께 삭제
- **효과**: 장기 저장 비용 절감, 데이터 정리

#### **스케줄러 설정 방법**

**방법 1: Anonymous Apex로 설정 (권장)**

```apex
// 아카이브 스케줄러 등록 (매일 오전 3시)
ChatMessageArchiveScheduler.scheduleDailyArchive();

// 삭제 스케줄러 등록 (매일 오전 2시)
ChatMessageCleanupScheduler.scheduleDailyCleanup();
```

**방법 2: Setup에서 수동 설정**

1. Setup → Apex → Scheduled Jobs
2. "Schedule Apex" 클릭
3. 다음 정보 입력:

**아카이브 배치:**
- **Apex Class**: `ChatMessageArchiveScheduler`
- **Job Name**: `Chat Message Archive - Daily`
- **Cron Expression**: `0 0 3 * * ?` (매일 새벽 3시)

**삭제 배치:**
- **Apex Class**: `ChatMessageCleanupScheduler`
- **Job Name**: `Chat Message Cleanup - Daily`
- **Cron Expression**: `0 0 2 * * ?` (매일 새벽 2시)

4. Save 클릭

**Cron Expression 형식 설명:**
```
초 분 시 일 월 요일 [연도]
0  0  2  *  *  ?
```

**기본 설정:**
- `0 0 2 * * ?` - 매일 새벽 2시 정각 (삭제 배치)
- `0 0 3 * * ?` - 매일 새벽 3시 정각 (아카이브 배치)

**다른 시간대 설정 예시:**
- `0 0 1 * * ?` - 매일 새벽 1시
- `0 0 4 * * ?` - 매일 새벽 4시
- `0 30 2 * * ?` - 매일 새벽 2시 30분
- `0 0 2 ? * MON-FRI` - 평일만 새벽 2시 (월~금)
- `0 0 2 1 * ?` - 매월 1일 새벽 2시
- `0 0 2 * * SUN` - 매주 일요일 새벽 2시

**Cron Expression 필드 설명:**
- **초 (0-59)**: `0` = 정각
- **분 (0-59)**: `0` = 정각
- **시 (0-23)**: `2` = 새벽 2시
- **일 (1-31)**: `*` = 매일
- **월 (1-12 또는 JAN-DEC)**: `*` = 매월
- **요일 (1-7 또는 SUN-SAT)**: `?` = 특정 요일 지정 안 함

#### **수동 배치 실행**

**아카이브 배치 실행:**
```apex
ChatMessageArchiveBatch batch = new ChatMessageArchiveBatch();
Database.executeBatch(batch, 200);
```

**삭제 배치 실행:**
```apex
ChatMessageCleanupBatch batch = new ChatMessageCleanupBatch();
Database.executeBatch(batch, 200);
```

#### **아카이브 메시지 조회**

아카이브된 메시지는 `ChatController.getMessagesPaged()` 메서드에서 자동으로 조회됩니다:
- 활성 메시지가 부족할 때 아카이브 메시지도 함께 조회
- 페이징 시 오래된 메시지가 필요하면 아카이브에서 자동 로드
- UI에서는 활성 메시지와 아카이브 메시지가 구분 없이 표시됨

---

## 📋 프로젝트 개요

이 프로젝트는 Salesforce 조직에 다음 기능을 제공합니다:

### 1. **Inner Chat (사내 실시간 메신저)**
- 유틸리티 바 기반 LWC 채팅 인터페이스
- Platform Event 기반 실시간 알림
- 메시지 송수신, 파일 첨부, 메시지 인용(Reply)
- 채팅방 생성/이름 변경/초대/나가기
- 읽음 표시, 말음/고정 기능
- Aura 플래시 백그라운드 알림
- **아카이브 메시지 조회**: 오래된 메시지도 자동으로 조회 가능
- **2단계 데이터 보관**: 3개월 아카이브 → 1년 삭제 정책

### 2. **Leave Management (휴가 관리)**
- 휴가 신청 (일/반차)
- 매니저 승인 워크플로우
- 캘린더 Event 자동 연동
- 휴가 잔여일 관리

### 3. **Break Request (휴무 신청)**
- 휴무 신청 및 승인
- 시간 단위 휴무 관리

### 4. **Work Time (근무 시간 관리)**
- 일일 근무 시간 기록
- 근무 현황 대시보드

---

## 🚀 배포 순서 및 유의점

### **Step 1: 사전 준비 (배포 전)**

#### 1-1. My Domain 활성화 (필수)
```
Setup → Company Settings → My Domain
1. 도메인 설정 (예: mycompany.my.salesforce.com)
2. "Deploy to Production" 클릭
3. 완료 대기 (5-10분)
```
**이유**: Platform Event 실시간 구독(`lightning:empApi`)이 My Domain을 필요로 합니다.

#### 1-2. 대상 Org 로그인
```bash
sf org login web -a target-org
# 또는
sfdx force:auth:web:login -a target-org
```

---

### **Step 2: 메타데이터 배포 (핵심)**

#### 2-1. 통합 배포 (권장)
```bash
sf project deploy start \
  --target-org target-org \
  --manifest manifest/package.xml \
  --test-level RunLocalTests
```

**포함 항목:**
- ✅ Chat 기능 (Apex, LWC, Aura, Objects, Permission Set)
  - 활성 메시지 객체 (`Inner_Chat_Message__c`)
  - 아카이브 메시지 객체 (`Inner_Chat_Message_Archive__c`)
  - 아카이브 배치 클래스 (`ChatMessageArchiveBatch`, `ChatMessageArchiveScheduler`)
  - 삭제 배치 클래스 (`ChatMessageCleanupBatch`, `ChatMessageCleanupScheduler`)
- ✅ Leave 관리 (Apex, Objects, Permission Set)
- ✅ Break 관리 (Apex, Objects)
- ✅ Work Time 관리 (Apex, Objects)

#### 2-2 배포 상태 확인
```bash
sf project deploy report -i <deploy-id> --target-org target-org
```

---

### **Step 3: 배포 후 필수 수동 설정**

#### 3-1. Permission Set 할당 (필수)
```
Setup → Users → [사용자명] → Permission Set Assignments
```

**할당 대상 Permission Set:**
- `Internal_Chat_Permission_Set` (모든 채팅 사용자)
- `Leave_Break_Employee_Permission_Set` (직원)
- `Leave_Break_Manager_Permission_Set` (매니저)

#### 3-2. Utility Bar에 Chat 컴포넌트 배치 (필수)
```
Setup → App Manager → [Lightning App명] → Edit
```

**Utility Items 추가:**
1. `utilityChat` (LWC) 추가
   - Label: "Chat" 또는 원하는 이름
   - Height: 480 (기본값)
   - Width: 340 (기본값)
   - Icon: utility:chat (또는 원하는 아이콘)

#### 3-3. 플래시 알림 컴포넌트 배치 (권장)
```
Setup → Lightning App Builder
```

**선택 사항 (항상 로드되어야 하는 페이지에 배치):**
1. Home 또는 사용자 정의 앱 페이지 열기
2. `chatFlashAura` 컴포넌트 추가
3. 저장 및 활성화

**목적**: 백그라운드에서 Platform Event를 구독하여 메시지 수신 시 유틸리티 바 하이라이트

---

#### 3-4. Leave Management 설정 (필수)

**A) OWD (Organization-Wide Defaults) 설정**
```
Setup → Object Manager → Leave_Request__c → Sharing Settings
```
- **Default Internal Access**: Private
- 저장

**B) Approval Process 생성**

**프로세스 #1: Leave Request Approval**
```
Setup → Process Automation → Approval Processes
Object: Leave_Request__c
Entry Criteria: Status__c = 'Submitted'
Approver: Approver__c (lookup to User)
Final Approval: Status__c = 'Approved'
Final Rejection: Status__c = 'Rejected'
```

**프로세스 #2: Leave Cancel Approval**
```
Object: Leave_Request__c
Entry Criteria: Status__c = 'CancelSubmitted'
Approver: Approver__c
Final Approval: Status__c = 'Cancelled'
Final Rejection: Status__c = 'Approved'
```

**C) 레코드 페이지에 버튼 추가 (권장)**
```
Setup → Object Manager → Leave_Request__c → Lightning Record Pages
또는 Flow Screen으로 UI 구성
```

---

## ⚙️ 배포 후 변동되는 값 재지정

### **1. Salesforce Org 고유 값 (자동 생성되지 않는 항목)**

#### 1-1. User Lookup Fields
| 필드명 | 객체 | 설명 | 재지정 필요 |
|--------|------|------|-----------|
| `Approver__c` | Leave_Request__c | 휴가 승인자 | ✅ 필수 |
| `Requester__c` | Leave_Request__c | 휴가 신청자 | ✅ 자동 (현재 사용자) |
| `Sender__c` | Inner_Chat_Message__c | 메시지 송신자 | ✅ 자동 (현재 사용자) |
| `User__c` | Inner_Chat_Participant__c | 채팅 참여자 | ✅ 자동 (선택된 사용자) |

**재지정 방법:**
```
각 조직마다 사용자 구조가 다르므로, 데이터 마이그레이션 시
변환 매핑(Mapping) 파일을 별도로 작성하여 ID 재매핑
```

#### 1-2. Custom Metadata / Settings
| 항목 | 현재 값 | 변동 가능성 | 조치 |
|------|--------|-----------|------|
| Channel Name | `/event/Inner_Chat_Notification__e` | ❌ 고정 | 재지정 불필요 |
| API Version | 65.0 | ⚠️ 필요시 | 더 높은 버전 권장 |

---

### **2. Platform Event 및 API 이름 (고정, 재지정 불필요)**

| 항목 | API Name | 이유 |
|------|----------|------|
| Chat Notification Event | `Inner_Chat_Notification__e` | 코드에 하드코딩됨 (변경 불가) |
| Chat Session | `Inner_Chat_Session__c` | Apex/LWC에 참조됨 |
| Chat Message | `Inner_Chat_Message__c` | Apex/LWC에 참조됨 |
| Chat Participant | `Inner_Chat_Participant__c` | Apex/LWC에 참조됨 |

---

### **3. 조직별로 재설정이 필요한 항목**

#### 3-1. Lightning App 할당
```
다른 Org에서는 Utility Bar 배치 위치가 다를 수 있음:
- Sales Cloud App
- Service Cloud App
- Custom App
→ 각 Org의 앱 구조에 맞게 수동 설정
```

#### 3-2. Approval Process Approver
```
각 조직마다 승인자 구조가 다름:
- 예시 Org: Manager는 ID "0051X000..."
- 타겟 Org: Manager는 ID "0051Y000..."
→ Approval Process 에서 Approver lookup 재설정
```

#### 3-3. Calendar Event Integration (Leave)
```
기본값: Google Calendar 또는 Salesforce Calendar
→ 조직의 캘린더 통합 방식에 따라 조정 필요
```

---

## 📝 배포 체크리스트

### **배포 전:**
- [ ] My Domain 활성화 및 배포 완료
- [ ] 대상 Org에 Sandbox/Org 로그인 준비
- [ ] 배포 대상자 (Developer, Admin) 권한 확인

### **배포 중:**
- [ ] `sf project deploy start` 명령 실행
- [ ] 테스트 커버리지 75% 이상 확인
- [ ] 배포 로그 검토 (오류 없음)

### **배포 후:**
- [ ] Permission Set 할당 (필수)
- [ ] Utility Bar에 `utilityChat` 배치 (필수)
- [ ] `chatFlashAura` 컴포넌트 배치 (권장)
- [ ] Leave Management Approval Process 생성 (필수)
- [ ] OWD 설정 (필수)
- [ ] **아카이브 스케줄러 등록** (권장)
  ```apex
  ChatMessageArchiveScheduler.scheduleDailyArchive();
  ```
- [ ] **삭제 스케줄러 등록** (권장)
  ```apex
  ChatMessageCleanupScheduler.scheduleDailyCleanup();
  ```
- [ ] 테스트 사용자로 Chat 기능 확인
- [ ] Platform Event 실시간 알림 테스트
- [ ] 아카이브 메시지 조회 기능 테스트

---

## 🔍 배포 후 테스트 시나리오

### **Chat 기능 테스트**
```
1. 두 사용자 로그인 (A, B)
2. A가 B에게 메시지 전송
3. B의 유틸리티 바에 실시간 알림 확인
4. B가 회신
5. A의 읽음 표시 확인
```

### **아카이브 기능 테스트**
```
1. 3개월 이상 된 메시지가 있는 채팅방 확인
2. 아카이브 배치 수동 실행:
   ChatMessageArchiveBatch batch = new ChatMessageArchiveBatch();
   Database.executeBatch(batch, 200);
3. 배치 완료 후 확인:
   - Inner_Chat_Message__c에서 오래된 메시지 삭제 확인
   - Inner_Chat_Message_Archive__c에 JSON 청크 생성 확인
   - Inner_Chat_Session__c의 Archived_Message_Count__c 업데이트 확인
4. 채팅방에서 오래된 메시지 조회 테스트 (페이징)
5. 1년 이상 된 아카이브 청크 삭제 테스트:
   ChatMessageCleanupBatch batch = new ChatMessageCleanupBatch();
   Database.executeBatch(batch, 200);
```

### **Leave Request 테스트**
```
1. 직원이 휴가 신청 (Status: Submitted)
2. 매니저에게 승인 알림 확인
3. 매니저가 승인 (Status: Approved)
4. 캘린더 Event 자동 생성 확인
```

---

## ⚠️ 주의사항

### **1. My Domain 미활성화 시**
```
오류: "The channel you requested to subscribe to does not exist"
해결: Setup → Company Settings → My Domain → Deploy
```

### **2. Permission Set 미할당 시**
```
오류: "You do not have permission to access this component"
해결: Setup → Users → Permission Set Assignments
```

### **3. Platform Event 채널명 변경 금지**
```
❌ 절대 변경하지 마세요:
- /event/Inner_Chat_Notification__e
  (Apex, LWC 코드에 하드코딩됨)
```

### **4. Approval Process 미설정 시**
```
Leave Request가 Submitted 상태에서 진행되지 않음
→ Approval Process 필수 생성
```

### **5. 데이터 마이그레이션 시**
```
기존 Org의 User ID와 다른 Org의 User ID가 다름
→ 마이그레이션 전 ID 매핑 파일 준비
```

---

## 📈 아카이브 모니터링 및 관리

### **아카이브 상태 확인**

**세션별 아카이브 상태 조회:**
```apex
// SOQL로 확인
SELECT Id, Name, Active_Message_Count__c, Archived_Message_Count__c, 
       Archive_Storage_Type__c, Last_Archive_Date__c
FROM Inner_Chat_Session__c
WHERE Archived_Message_Count__c > 0
ORDER BY Last_Archive_Date__c DESC
```

**아카이브 청크 조회:**
```apex
SELECT Id, Inner_Chat_Session__c, Chunk_Index__c, Message_Count__c,
       First_Message_Date__c, Last_Message_Date__c
FROM Inner_Chat_Message_Archive__c
ORDER BY Inner_Chat_Session__c, Chunk_Index__c
```

### **배치 작업 상태 확인**

**최근 실행된 배치 작업 조회:**
```apex
// 아카이브 배치 상태
AsyncApexJob archiveJob = [
    SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CreatedDate
    FROM AsyncApexJob
    WHERE ApexClass.Name = 'ChatMessageArchiveBatch'
    ORDER BY CreatedDate DESC
    LIMIT 1
];

// 삭제 배치 상태
AsyncApexJob cleanupJob = [
    SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CreatedDate
    FROM AsyncApexJob
    WHERE ApexClass.Name = 'ChatMessageCleanupBatch'
    ORDER BY CreatedDate DESC
    LIMIT 1
];
```

### **아카이브 데이터 통계**

**전체 아카이브 통계 조회:**
```apex
// 세션별 아카이브 통계
AggregateResult[] stats = [
    SELECT Inner_Chat_Session__c sessionId,
           COUNT(Id) chunkCount,
           SUM(Message_Count__c) totalMessages
    FROM Inner_Chat_Message_Archive__c
    GROUP BY Inner_Chat_Session__c
];

// 전체 아카이브 메시지 수
AggregateResult total = [
    SELECT SUM(Message_Count__c) total
    FROM Inner_Chat_Message_Archive__c
];
```

## 🔧 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| Chat 유틸리티 아이콘 비활성화 | Permission Set 미할당 | Setup → Users → Permission Set 할당 |
| 실시간 메시지 미수신 | My Domain 미배포 | Setup → My Domain → Deploy |
| 플래시 알림 작동 안 함 | chatFlashAura 미배치 | Lightning App Builder에서 배치 |
| Leave Approval 작동 안 함 | Approval Process 미생성 | Process Automation에서 생성 |
| Platform Event 구독 오류 | API 권한 부족 | Permission Set에서 ApiEnabled 확인 |
| 아카이브 배치 미실행 | 스케줄러 미등록 | `ChatMessageArchiveScheduler.scheduleDailyArchive()` 실행 |
| 아카이브 메시지 조회 안 됨 | 아카이브 데이터 없음 | 3개월 이상 된 메시지가 있어야 아카이브 생성 |
| 배치 작업 실패 | 데이터 용량 초과 | 청크 크기 조정 또는 배치 크기 감소 |

---

## 📞 지원 및 문의

- **플랫폼**: Salesforce Org
- **API 버전**: 65.0+
- **최소 요구사항**: Lightning Experience, Streaming API 활성화

---

## 🔐 보안 고려사항

1. **CRUD & FLS 체크**: ChatController에서 구현됨 (필수)
2. **데이터 격리**: Organization-Wide Defaults 설정 권장
3. **권한 제어**: Permission Set으로 세밀한 접근 제어
4. **감사 로그**: Platform Events는 감사 로그 미포함 (Org 정책에 따라)

---

## 📊 데이터 모델 (업데이트)

### **Chat 관련 객체**

#### **활성 메시지 객체**
- **Inner_Chat_Message__c**: 최근 3개월 이내 메시지
  - `Content__c`: 메시지 내용
  - `Sender__c`: 발신자
  - `Reply_To__c`: 답장 대상 메시지
  - `Reply_Preview__c`: 답장 미리보기
  - `Inner_Chat_Session__c`: 채팅방 (Master-Detail)

#### **아카이브 메시지 객체**
- **Inner_Chat_Message_Archive__c**: 3개월 이상 된 메시지 (JSON 형식)
  - `Inner_Chat_Session__c`: 채팅방 (Master-Detail)
  - `Chunk_Index__c`: 청크 순서 (0, 1, 2, ...)
  - `Messages_JSON__c`: 메시지 JSON 배열 (최대 100개/청크)
  - `Message_Count__c`: 청크 내 메시지 수
  - `First_Message_Date__c`: 첫 메시지 시간
  - `Last_Message_Date__c`: 마지막 메시지 시간

#### **채팅방 객체 (업데이트)**
- **Inner_Chat_Session__c**: 채팅방 정보
  - `Name`: 채팅방 이름
  - `Type__c`: Direct/Group
  - `Last_Message_At__c`: 마지막 메시지 시간
  - **신규 필드**:
    - `Active_Message_Count__c`: 활성 메시지 수
    - `Archived_Message_Count__c`: 아카이브된 메시지 수
    - `Archive_Storage_Type__c`: 아카이브 저장 타입 (JSON/BigObject)
    - `Last_Archive_Date__c`: 마지막 아카이브 날짜

#### **기타 객체**
- **Inner_Chat_Participant__c**: 참여자 정보
- **Inner_Chat_Notification__e**: Platform Event (실시간 알림)

## 🔄 배치 클래스 상세

### **ChatMessageArchiveBatch**
- **목적**: 3개월 이상 된 활성 메시지를 JSON으로 아카이브
- **실행 주기**: 매일 오전 3시 (스케줄러)
- **처리 방식**:
  1. 3개월 이상 된 메시지 조회
  2. 세션별로 그룹화
  3. 청크 단위로 분할 (최대 100개/청크)
  4. JSON 형식으로 변환
  5. `Inner_Chat_Message_Archive__c`에 저장
  6. 기존 메시지 레코드 삭제
  7. 세션 메타데이터 업데이트

### **ChatMessageCleanupBatch**
- **목적**: 1년 이상 된 활성 메시지 및 아카이브 청크 삭제
- **실행 주기**: 매일 오전 2시 (스케줄러)
- **처리 방식**:
  1. 1년 이상 된 활성 메시지 삭제
  2. 1년 이상 된 아카이브 청크 삭제
  3. 첨부 파일(ContentDocument) 삭제
  4. 세션 메타데이터 업데이트

## 📚 추가 리소스

- **Salesforce CLI**: https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference
- **Platform Events**: https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events
- **LWC**: https://developer.salesforce.com/docs/component-library/documentation/lwc
- **Approval Processes**: https://help.salesforce.com/s/articleView?id=sf.approval_process_overview.htm
- **Batch Apex**: https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_batch_interface.htm

---

**문서 작성**: 2026-01-27  
**최종 수정**: 2025-03-13  
**버전**: 2.0.0  
**상태**: ✅ 배포 준비 완료 (2단계 보관 정책 포함)
