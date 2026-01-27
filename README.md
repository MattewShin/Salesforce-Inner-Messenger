# Salesforce Inner Messenger - 완전 배포 가이드

**프로젝트**: Salesforce Inner Messenger (사내 실시간 메신저 + 휴가/휴무 관리 + 근무 시간 관리)  
**버전**: 1.0.0  
**배포 메인 파일**: `manifest/package.xml`

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
- [ ] 테스트 사용자로 Chat 기능 확인
- [ ] Platform Event 실시간 알림 테스트

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

## 🔧 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| Chat 유틸리티 아이콘 비활성화 | Permission Set 미할당 | Setup → Users → Permission Set 할당 |
| 실시간 메시지 미수신 | My Domain 미배포 | Setup → My Domain → Deploy |
| 플래시 알림 작동 안 함 | chatFlashAura 미배치 | Lightning App Builder에서 배치 |
| Leave Approval 작동 안 함 | Approval Process 미생성 | Process Automation에서 생성 |
| Platform Event 구독 오류 | API 권한 부족 | Permission Set에서 ApiEnabled 확인 |

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

## 📚 추가 리소스

- **Salesforce CLI**: https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference
- **Platform Events**: https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events
- **LWC**: https://developer.salesforce.com/docs/component-library/documentation/lwc
- **Approval Processes**: https://help.salesforce.com/s/articleView?id=sf.approval_process_overview.htm

---

**문서 작성**: 2026-01-27  
**최종 수정**: 2026-01-27  
**상태**: ✅ 배포 준비 완료
