# 조직간 배포 시 재지정 필요 항목

**목적**: 다른 Salesforce 조직에 배포할 때 변경해야 하는 값들을 정리  
**작성일**: 2026-01-27

---

## 📌 요약표

| 구분 | 항목 | 기존값 | 변경필요 | 대체 방법 |
|------|------|--------|---------|---------|
| **고정값** | Platform Event 채널명 | `/event/Inner_Chat_Notification__e` | ❌ 불필요 | 변경 금지 |
| **고정값** | API 이름들 | `Inner_Chat_*` | ❌ 불필요 | 변경 금지 |
| **Org 고유값** | User ID (Approver) | (dynamic) | ✅ 필수 | 데이터 마이그레이션 |
| **Org 고유값** | User ID (Requester) | (현재 사용자) | ✅ 자동 | 수동 입력 불필요 |
| **설정값** | Utility Bar 위치 | Sales App 등 | ⚠️ 필요시 | 각 App 구조별 설정 |
| **설정값** | Approval Process Approver | Approver__c lookup | ✅ 필수 | Approval Process 재설정 |
| **설정값** | OWD (Organization-Wide Defaults) | Private | ✅ 필수 | 각 조직 정책별 설정 |
| **설정값** | Presence Status Values | Available/Away/Offline | ✅ 필수 | 조직별 정의 재설정 |

---

## 🔴 변경 금지 항목 (절대 변경하면 안 됨)

### 1. Platform Event 채널명
```
❌ 변경 금지: /event/Inner_Chat_Notification__e
```

**이유**: 
- Apex 코드에 하드코딩됨
- LWC에 하드코딩됨
- 변경 시 EMP API 구독 실패

**코드 위치:**
- `ChatController.cls`: Line 68, 261, 424, 576, 643, 794, 1027
- `utilityChat.js`: Line 68, 1114

---

### 2. Custom Object API 이름
```
❌ 변경 금지:
- Inner_Chat_Session__c
- Inner_Chat_Message__c
- Inner_Chat_Participant__c
- Inner_Chat_Notification__e (Platform Event)
- Leave_Request__c
- Leave_Entitlement__c
- Break_Request__c
- Work_Time__c
```

**이유**: 모든 Apex/LWC에서 직접 참조됨

**변경 시 발생 오류:**
```
INVALID_FIELD_REFERENCE: No such column 'Inner_Chat_Session__c' on entity 'Inner_Chat_Message__c'
```

---

### 3. Apex 클래스명 및 메서드명
```
❌ 변경 금지:
- ChatController
- ChatController_Test
- LeaveService
- LeaveRequestController
- ... (모든 Apex 클래스)
```

**이유**: `@AuraEnabled` 데코레이터로 메서드가 LWC에 expose되어 있음

---

## 🟡 필요시 변경 항목 (조직 정책에 따라)

### 1. Lightning App 할당 위치

**변동 원인**: 다른 조직은 다른 앱 구조를 가질 수 있음

**현재 설정:**
```
Example: Sales Cloud App의 Utility Bar에 배치
```

**다른 조직에서 변경 가능:**
- [ ] Service Cloud App의 Utility Bar
- [ ] Custom Lightning App의 Utility Bar
- [ ] Omnichannel Utility Bar

**변경 방법:**
```
Setup > App Manager > [App명] > Edit > Utility Items
→ utilityChat 추가 또는 이동
```

---

### 2. Approval Process 설정

**변동 원인**: 다른 조직의 승인자 구조/정책이 다를 수 있음

#### 2-1. Approver 필드 변경

**현재:**
```
Approver__c (User lookup)
```

**변경 시나리오:**
- 조직이 Role hierarchy 기반 승인 원함
- 조직이 Queue 기반 승인 원함
- 조직이 다중 승인 단계 원함

**변경 방법:**

```
Setup > Process Automation > Approval Processes
→ Leave_Request_Approval 편집
→ Approval Step에서 Approver 변경
```

#### 2-2. Approval Actions 변경

**현재:**
```
Final Approval: Status__c = 'Approved'
Final Rejection: Status__c = 'Rejected'
```

**변경 시나리오:**
- 승인 시 추가 이메일 발송
- 승인 시 특정 필드 자동 업데이트
- 승인 시 Flow 트리거

---

### 3. OWD (Organization-Wide Defaults)

**변동 원인**: 조직의 데이터 보안 정책이 다를 수 있음

**현재 설정:**
```
Leave_Request__c: Default Internal Access = Private
```

**변경 시나리오:**

| 조직 정책 | 설정값 | 이유 |
|---------|--------|------|
| 높은 보안 (기본) | Private | 최소 권한 원칙 |
| 중간 보안 | Read Only | 모두 조회 가능 |
| 낮은 보안 | Read/Write | 모두 수정 가능 |

**변경 방법:**
```
Setup > Object Manager > Leave_Request__c
→ Sharing Settings > Organization-Wide Defaults
→ "Default Internal Access" 변경
```

---

### 4. Permission Set 권한 레벨

**변동 원인**: 조직이 더 엄격하거나 더 느슨한 권한 정책을 원할 수 있음

**현재:**
```
Internal_Chat_Permission_Set:
  - Inner_Chat_Message__c: CRUD (Create, Read, Edit)
  - Inner_Chat_Session__c: CRUD
  - ...
```

**변경 시나리오:**

**시나리오 1: 더 엄격한 권한**
```
변경 후:
  - Inner_Chat_Message__c: R (Read Only)
  - Inner_Chat_Session__c: CR (Create, Read)
```

**시나리오 2: 더 느슨한 권한**
```
변경 후:
  - Inner_Chat_Message__c: CRUDS (모든 권한 + System Admin 필드)
  - Inner_Chat_Session__c: CRUDS
```

**변경 방법:**
```
Setup > Permission Sets > Internal_Chat_Permission_Set > Edit
→ Object Permissions 섹션에서 권한 조정
```

---

### 5. Presence Status 값 (⚠️ 조직별 커스터마이징)

**변동 원인**: 다른 조직은 다른 Presence Status 값을 정의할 수 있음

**현재 기본값:**
```
Available (이용 가능)
Away (자리 비움)
Offline (오프라인)
```

**Presence Status가 사용되는 곳:**

#### 5-1. OmniPresenceHelper.cls
```apex
// OmniPresenceHelper.cls - 라인 약 45-65
public class OmniPresenceHelper {
    // Presence Status 값을 관리하는 메서드
    public static void updateUserPresence(Id userId, String statusValue) {
        // statusValue 예시: 'Available', 'Away', 'Offline'
        // 조직별로 정의된 Presence Status API 이름 사용
    }
}
```

**변경 시나리오:**

조직 A (기본값):
```
Available (API: Available)
Away (API: Away)
Offline (API: Offline)
```

조직 B (커스텀 값):
```
Online (API: Online) - "Available" 대체
Break (API: Break) - "Away" 대체
DND (Do Not Disturb) (API: DND)
Offline (API: Offline)
```

**변경 방법:**

```
Setup > Feature Settings > Omnichannel > Presence
→ Presence Status 목록 확인
→ API Name 확인 후 코드에서 참조하는 값 변경
```

**코드 변경 예시:**

기존:
```apex
// OmniPresenceHelper.cls
public class OmniPresenceHelper {
    public static final String STATUS_AVAILABLE = 'Available'; // ← 기존값
    public static final String STATUS_AWAY = 'Away';
    public static final String STATUS_OFFLINE = 'Offline';
}
```

조직 B 변경 후:
```apex
// OmniPresenceHelper.cls
public class OmniPresenceHelper {
    public static final String STATUS_AVAILABLE = 'Online'; // ← 변경됨
    public static final String STATUS_AWAY = 'Break';
    public static final String STATUS_OFFLINE = 'Offline';
}
```

**주의사항:**
```
❌ 틀림: Presence Status 값을 하드코딩한 후 변경 안 함
✅ 맞음: 상수(Constant)로 정의하고, 조직별로 변경

예시 (나쁜 예):
    if (status == 'Available') { ... } // 변경 어려움

예시 (좋은 예):
    public static final String STATUS_AVAILABLE = 'Available';
    if (status == STATUS_AVAILABLE) { ... } // 변경 쉬움
```

---

## 🟢 자동 처리 항목 (변경 불필요)

### 1. User ID (현재 사용자)

```javascript
// utilityChat.js
currentUserId = USER_ID; // @salesforce/user/Id 자동 주입
```

**설명**: 각 사용자가 로그인하면 자동으로 현재 사용자 ID 할당  
**재설정 불필요**: ✅

---

### 2. Record ID (Lookup Fields)

```apex
// ChatController.cls
Inner_Chat_Session__c session = new Inner_Chat_Session__c();
insert session; // ID 자동 생성
```

**설명**: 레코드 생성 시 Salesforce가 자동으로 ID 할당  
**재설정 불필요**: ✅

---

### 3. Timestamps

```apex
System.now() // 현재 날짜/시간 자동
DateTime.now() // 현재 날짜/시간 자동
```

**설명**: 각 조직의 타임존에 맞게 자동 처리  
**재설정 불필요**: ✅

---

## 🔵 재지정 가능 상수/설정 항목 (코드에서 변경 필요)

### 1. OmniPresenceHelper.cls - Presence Status 상수

**파일 위치**: `force-app/main/default/classes/OmniPresenceHelper.cls`

**현재 코드:**
```apex
public class OmniPresenceHelper {
    /**
     * @description Presence Status 상수 정의
     * 조직별로 다를 수 있음 - 배포 후 재설정 필요
     */
    public static final String STATUS_AVAILABLE = 'Available';
    public static final String STATUS_AWAY = 'Away';
    public static final String STATUS_OFFLINE = 'Offline';
    
    /**
     * @description 사용자 Presence 상태를 업데이트
     * @param userId 대상 사용자 ID
     * @param statusValue Presence Status API 이름
     * @note Org에 정의된 Presence Status 값을 사용해야 함
     *       Setup > Omnichannel > Presence Status에서 확인
     */
    public static void updateUserPresence(Id userId, String statusValue) {
        // 구현부...
        // statusValue는 조직의 Presence Status API Name과 일치해야 함
    }
}
```

**변경 예시:**

기본 Org:
```apex
public static final String STATUS_AVAILABLE = 'Available';
public static final String STATUS_AWAY = 'Away';
public static final String STATUS_OFFLINE = 'Offline';
```

커스텀 Org:
```apex
// 변경 후: 조직의 Presence Status에 맞게 수정
public static final String STATUS_AVAILABLE = 'Online'; // ← 변경
public static final String STATUS_AWAY = 'Break'; // ← 변경
public static final String STATUS_OFFLINE = 'Offline'; // ← 그대로
```

---

### 2. ChatController.cls - Platform Event 채널명

**파일 위치**: `force-app/main/default/classes/ChatController.cls`

**주석 추가 부분:**
```apex
/**
 * @description Chat Controller - 사내 메신저 컨트롤러
 * @note Platform Event 채널명은 절대 변경하면 안 됨
 *       모든 참조가 하드코딩되어 있음
 */
public with sharing class ChatController {
    
    /**
     * @description Platform Event 채널명
     * ⚠️ 중요: 이 값을 변경하면 EMP API 구독이 실패합니다
     * 다른 Org에 배포할 때도 이 값은 그대로 유지하세요
     * 
     * 관련 코드:
     *   - Line 261: EventBus.publish(notif)
     *   - Line 424: EventBus.publish(notif)
     *   - Line 576: EventBus.publish(notif)
     */
    private static final String CHANNEL_NAME = '/event/Inner_Chat_Notification__e';
}
```

---

### 3. utilityChat.js - Platform Event 구독

**파일 위치**: `force-app/main/default/lwc/utilityChat/utilityChat.js`

**주석 추가 부분:**
```javascript
export default class UtilityChat extends NavigationMixin(LightningElement) {
    /**
     * @description Platform Event 구독 채널명
     * ⚠️ 중요: 이 값을 변경하면 안 됩니다
     * Apex ChatController와 동일해야 함
     * 
     * 채널명 형식: /event/[Platform_Event_API_Name]__e
     * 현재값: /event/Inner_Chat_Notification__e
     * 
     * 다른 Org 배포 시 재지정 불필요
     */
    channelName = '/event/Inner_Chat_Notification__e';
    
    /**
     * @description Platform Event 구독 처리
     * @note handleSubscribe() 메서드는 조직별 커스터마이징 필요 없음
     *       Platform Event API는 자동으로 조직에 맞게 처리됨
     */
    handleSubscribe() {
        // 구현부...
        subscribe(this.channelName, -1, messageCallback).then(response => {
            this.subscription = response;
        });
    }
}
```

---

### 4. 조직별 변경 필요 항목 정리

**요청받은 사항별 코드 위치:**

| 조직별 설정 항목 | Apex 파일 | 메서드/상수 | 변경 필요 |
|----------------|---------|----------|---------|
| Presence Status | OmniPresenceHelper.cls | STATUS_AVAILABLE, STATUS_AWAY | ✅ 필수 |
| Chat 채널명 | ChatController.cls | CHANNEL_NAME (상수) | ❌ 금지 |
| User Approver | LeaveRequestController.cls | Approver__c lookup | ✅ 필수 (데이터) |
| Leave Status | LeaveService.cls | STATUS_* 상수 | ⚠️ 필요시 |

---

## 🔵 데이터 마이그레이션 시 필요한 매핑

### 1. User Lookup 재매핑

**상황**: 기존 Org의 데이터를 새로운 Org로 이관

```
기존 Org:
  Approver__c = "0051X00000....... (Manager User ID)"

새 Org:
  Approver__c = "0051Y00000....... (다른 ID)"
```

**해결 방법:**

**방법 1: Data Loader 사용**
```
1. 기존 Org에서 Leave_Request__c export
2. User ID 매핑 테이블 작성
3. 새 Org의 User ID로 변환
4. Data Loader로 import
```

**방법 2: SOQL 기반 업데이트**
```sql
-- 기존 Org에서 User 정보 export
SELECT Id, Name, Email FROM User WHERE IsActive = true

-- 새 Org에서 이름/이메일로 User 검색
SELECT Id, Name, Email FROM User WHERE Name = '...'

-- ID 매핑 테이블 생성 후 업데이트
```

**매핑 테이블 예시:**

| 기존 Org User Name | 기존 Org ID | 새 Org User Name | 새 Org ID |
|------------------|-----------|-----------------|----------|
| john.doe | 0051X123456 | john.doe | 0051Y789012 |
| jane.smith | 0051X234567 | jane.smith | 0051Y890123 |

---

### 2. Calendar Event 연동 재설정 (Leave 관리)

**상황**: 캘린더 시스템이 다를 수 있음

```
기존 Org: Google Calendar 통합
새 Org: Outlook Calendar 통합
```

**변경 필요 항목:**

| 항목 | 기존값 | 변경 필요 |
|------|--------|---------|
| Event 생성 Object | CalendarEvent | 조직에 맞게 변경 |
| 외부 캘린더 API | Google Calendar API | 조직에 맞게 변경 |
| Event 동기화 설정 | (코드에서 처리) | Apex 수정 필요 |

---

## 📋 조직별 체크리스트

### Org A (기존 Org)에서 Org B (새 Org)로 이관 시

```
Org B 배포 전:
[ ] Org A의 User 목록 export (ID, Name, Email)
[ ] Org A의 Leave_Request__c 데이터 export (필요시)
[ ] Org A의 Approver__c lookup 확인

Org B 배포 후:
[ ] Org B의 User 목록 확인
[ ] User ID 매핑 테이블 작성
[ ] Data Loader로 Leave_Request__c import
[ ] Approver__c lookup 재매핑
[ ] Approval Process에서 Approver 재설정
[ ] 테스트: Leave Request 신청 → 승인 프로세스 동작 확인
```

---

## ⚠️ 주의사항

### 1. Org 간 ID 호환성 없음
```
❌ 틀림: Org A의 ID = Org B의 ID
✅ 맞음: 각 Org마다 고유한 ID 체계

예시:
  Org A: User ID = 0051X000001...
  Org B: User ID = 0051Y000001... (다른 ID)
```

### 2. Permission Set 이름은 같지만 ID는 다름
```
❌ 틀림: 같은 이름 = 같은 권한
✅ 맞음: 각 Org에서 독립적으로 생성/할당

단계:
  1. Org A에서 "Internal_Chat_Permission_Set" 배포
  2. Org B에서 "Internal_Chat_Permission_Set" 자동 생성 (다른 ID)
  3. Org B에서 사용자에게 할당
```

### 3. My Domain이 다름
```
Org A: company.my.salesforce.com
Org B: company-prod.my.salesforce.com (또는 다른 도메인)

→ Platform Event 구독 시 각 Org의 My Domain 필요
```

---

## 🔧 문제 해결

### Q: 새 Org에서 "Approver not found" 오류 발생
**A**: Approver__c lookup이 기존 Org ID로 설정됨  
**해결**: Data Loader로 새 Org의 User ID로 재매핑

### Q: 승인 프로세스가 작동하지 않음
**A**: Approval Process가 새 Org에서 생성되지 않았을 수 있음  
**해결**: Setup > Process Automation > Approval Processes에서 수동 생성

### Q: Platform Event 구독 실패 ("channel does not exist")
**A**: My Domain이 활성화되지 않았거나 배포되지 않음  
**해결**: Setup > My Domain > Deploy to Production

---

## 📞 추가 참고자료

- **User ID Format**: 15자리 또는 18자리 고유 ID
- **Salesforce Data Import**: https://help.salesforce.com/s/articleView?id=sf.importing_data.htm
- **Data Loader**: https://developer.salesforce.com/docs/atlas.en-us.dataLoader.meta/dataLoader
- **Approval Processes**: https://help.salesforce.com/s/articleView?id=sf.approval_process_overview.htm

---

**문서 작성**: 2026-01-27  
**상태**: ✅ 완료
