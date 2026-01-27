# 배포 체크리스트 및 설정 가이드

**대상 Org**: ________________________________________  
**배포 담당자**: _______________  
**배포 일시**: _______________

---

## 📋 Step 1: 배포 전 확인 (체크리스트)

- [ ] 대상 Org에 Admin 또는 배포 권한 있는 사용자로 로그인 확인
- [ ] Salesforce CLI 최신 버전 설치 확인
  ```bash
  sf --version
  ```
- [ ] Git 클론 및 프로젝트 다운로드 완료
  ```bash
  git clone <repo-url>
  cd Salesforce-Inner-Messenger
  ```

---

## 📋 Step 2: My Domain 설정 (필수)

**상태**: ☐ 미완료 / ☐ 진행 중 / ☐ 완료

### 2-1. My Domain 활성화
```
Setup 검색창에서 "My Domain" 검색
→ Setup > Company Settings > My Domain
```

**현재 상태:**
- [ ] My Domain 이미 활성화됨
- [ ] My Domain 미활성화 (활성화 필요)

### 2-2. My Domain 도메인명 기록
```
예: mycompany.my.salesforce.com
또는: mycompany--c.my.salesforce.com (sandbox)
```

**기록된 도메인명**: _________________________________

### 2-3. Deploy (Production의 경우)
```
My Domain 페이지 → "Deploy to Production" 클릭
→ 완료 대기 (약 5-10분)
```

**Deploy 상태:**
- [ ] 이미 배포됨
- [ ] 지금 배포 (소요시간: 5-10분)

---

## 📋 Step 3: Org 로그인

**상태**: ☐ 미완료 / ☐ 진행 중 / ☐ 완료

### 3-1. 대상 Org 로그인
```bash
sf org login web -a target-org
```

**로그인 확인:**
- [ ] 브라우저에서 로그인 완료
- [ ] Org 선택 후 "Allow" 클릭
- [ ] 터미널에서 성공 메시지 확인

---

## 📋 Step 4: 메타데이터 배포 (핵심)

**상태**: ☐ 미완료 / ☐ 진행 중 / ☐ 완료

### 4-1. 배포 명령 실행
```bash
sf project deploy start \
  --target-org target-org \
  --manifest manifest/package.xml \
  --test-level RunLocalTests
```

**배포 결과:**
- [ ] 성공 (배포 ID: __________________)
- [ ] 실패 (오류 내용 기록: __________________)

### 4-2. 배포 로그 확인
```bash
sf project deploy report -i <deploy-id> --target-org target-org
```

**확인 항목:**
- [ ] 모든 메타데이터 배포 성공
- [ ] 테스트 커버리지 75% 이상
- [ ] 오류 없음

---

## 📋 Step 5: Permission Set 할당 (필수)

**상태**: ☐ 미완료 / ☐ 진행 중 / ☐ 완료

### 5-1. 할당할 사용자 목록
```
다음 사용자들에게 Permission Set을 할당합니다.
(각 사용자별로 체크)
```

| # | 사용자명 | 직책 | 할당 항목 | 상태 |
|---|---------|------|----------|------|
| 1 | | | Internal_Chat_Permission_Set | ☐ |
| 2 | | | Internal_Chat_Permission_Set | ☐ |
| 3 | | | Internal_Chat_Permission_Set + Leave_Break_Manager | ☐ |
| 4 | | | Internal_Chat_Permission_Set + Leave_Break_Employee | ☐ |
| 5 | | | Internal_Chat_Permission_Set + Leave_Break_Employee | ☐ |

### 5-2. 할당 절차
```
Setup > Users > [사용자명] > Permission Set Assignments > "Edit"
→ 해당 Permission Set 선택 > "Save"
```

---

## 📋 Step 6: Lightning App 설정 (필수)

**상태**: ☐ 미완료 / ☐ 진행 중 / ☐ 완료

### 6-1. Chat 컴포넌트를 Utility Bar에 배치

**대상 App**: _________________________

```
Setup > App Manager > [App명] > "Edit"
→ Utility Items 섹션 > "Add" 클릭
→ "utilityChat" 검색 후 선택
```

**Utility Bar 설정값:**

| 설정항목 | 값 |
|---------|-----|
| Label | Chat (또는 원하는 이름) |
| Component | utilityChat |
| Height | 480 |
| Width | 340 |
| Icon | utility:chat |

**확인:**
- [ ] utilityChat이 Utility Bar에 추가됨
- [ ] 설정값 저장 완료

---

## 📋 Step 7: 플래시 알림 배치 (권장)

**상태**: ☐ 미완료 / ☐ 진행 중 / ☐ 완료

### 7-1. Home Page 또는 Custom Page에 배치

```
Setup > Lightning App Builder
→ "New" > "App Page" (또는 기존 Page 편집)
→ "chatFlashAura" 검색 후 드래그
→ "Save" > "Activate"
```

**배치 위치:**
- [ ] Home Page
- [ ] Custom App Page (페이지명: __________________)
- [ ] 기타 (설명: __________________)

---

## 📋 Step 8: Leave Management 설정 (필수)

**상태**: ☐ 미완료 / ☐ 진행 중 / ☐ 완료

### 8-1. OWD (Organization-Wide Defaults) 설정

```
Setup > Object Manager > Leave_Request__c
→ Sharing Settings > Organization-Wide Defaults
→ "Default Internal Access" = "Private"
→ "Save"
```

**확인:**
- [ ] OWD = Private 설정 완료

### 8-2. Approval Process 생성 (#1)

**프로세스 이름**: Leave Request Approval

```
Setup > Process Automation > Approval Processes
→ "Create New" 클릭
```

**기본 정보:**
- [ ] Object: Leave_Request__c
- [ ] Name: Leave Request Approval
- [ ] Unique Name: Leave_Request_Approval

**Entry Criteria:**
- [ ] Criteria: `Status__c = 'Submitted'`

**Approval Step:**
- [ ] Step Name: Manager Approval
- [ ] Approver Field: Approver__c
- [ ] Approval Assignment Email Template: (기본값)

**Final Approval Actions:**
- [ ] Field Update: Status__c → "Approved"

**Final Rejection Actions:**
- [ ] Field Update: Status__c → "Rejected"

**활성화:**
- [ ] Approval Process 활성화 완료

### 8-3. Approval Process 생성 (#2)

**프로세스 이름**: Leave Cancel Approval

```
Setup > Process Automation > Approval Processes
→ "Create New" 클릭
```

**기본 정보:**
- [ ] Object: Leave_Request__c
- [ ] Name: Leave Cancel Approval
- [ ] Unique Name: Leave_Cancel_Approval

**Entry Criteria:**
- [ ] Criteria: `Status__c = 'CancelSubmitted'`

**Approval Step:**
- [ ] Step Name: Manager Cancellation Approval
- [ ] Approver Field: Approver__c

**Final Approval Actions:**
- [ ] Field Update: Status__c → "Cancelled"

**Final Rejection Actions:**
- [ ] Field Update: Status__c → "Approved" (복귀)

**활성화:**
- [ ] Approval Process 활성화 완료

---

## 📋 Step 9: Permission Set 추가 할당 (Leave 관리자)

**상태**: ☐ 미완료 / ☐ 진행 중 / ☐ 완료

### 9-1. 매니저용 Permission Set

**할당 사용자:**

| 매니저명 | Permission Set | 상태 |
|---------|----------------|------|
| | Leave_Break_Manager_Permission_Set | ☐ |
| | Leave_Break_Manager_Permission_Set | ☐ |

```
Setup > Users > [사용자명] > Permission Set Assignments
→ "Edit" > "Leave_Break_Manager_Permission_Set" 선택 > "Save"
```

### 9-2. 직원용 Permission Set

**할당 사용자:**

| 직원명 | Permission Set | 상태 |
|-------|----------------|------|
| | Leave_Break_Employee_Permission_Set | ☐ |
| | Leave_Break_Employee_Permission_Set | ☐ |

---

## 📋 Step 10: 배포 후 테스트

**상태**: ☐ 미완료 / ☐ 진행 중 / ☐ 완료

### 10-1. Chat 기능 테스트

**테스트 시나리오:**

1. **유틸리티 바 표시 확인**
   - [ ] 사용자 A가 로그인
   - [ ] 유틸리티 바에 "Chat" 아이콘 표시 확인
   - [ ] Chat 클릭 시 메인 채팅 화면 열림

2. **1:1 메시지 송수신**
   - [ ] 사용자 A가 사용자 B에게 메시지 전송
   - [ ] 사용자 B의 화면에 실시간 메시지 수신 확인
   - [ ] 사용자 B가 회신
   - [ ] 실시간 알림 플래시 확인 (chatFlashAura 배치된 경우)

3. **그룹 채팅 생성**
   - [ ] 사용자 A가 그룹 채팅 생성 (+3명 초대)
   - [ ] 그룹 채팅 목록에 표시 확인
   - [ ] 초대된 사용자들이 채팅 참여 확인

4. **채팅방 관리**
   - [ ] 채팅방 이름 변경 테스트
   - [ ] 읽음/말음/고정 기능 테스트
   - [ ] 채팅방 나가기 테스트

### 10-2. Leave Request 테스트

**테스트 시나리오:**

1. **휴가 신청**
   - [ ] 직원이 휴가 신청 (Status: Submitted)
   - [ ] 신청 내용 저장 확인

2. **승인 알림**
   - [ ] 매니저에게 승인 알림 수신 확인

3. **승인 처리**
   - [ ] 매니저가 승인 (Status: Approved)
   - [ ] 상태 변경 확인

4. **캘린더 연동**
   - [ ] 승인 후 캘린더에 Event 자동 생성 확인

5. **취소 프로세스**
   - [ ] 승인 후 취소 요청 (Status: CancelSubmitted)
   - [ ] 매니저 승인 후 상태 = "Cancelled" 확인

---

## ✅ 최종 배포 완료 확인

### 배포 완료 체크리스트

- [ ] 모든 Step 완료
- [ ] 테스트 시나리오 통과
- [ ] 사용자 접근 권한 확인
- [ ] 기능 동작 정상 확인
- [ ] 오류 또는 문제점 없음

### 배포 완료 서명

| 항목 | 내용 |
|------|------|
| 배포 담당자 | __________________ |
| 배포 일시 | __________________ |
| 최종 확인 | ☐ 완료 |

---

## 📞 배포 후 지원

**문제 발생 시:**
1. 콘솔 로그 확인 (Browser DevTools > Console)
2. Salesforce Debug Logs 확인 (Setup > Monitoring > Debug Logs)
3. 해당 컴포넌트 재배포 시도

**연락처**: ____________________________________

---

**문서 작성**: 2026-01-27  
**상태**: ✅ 배포 준비 완료
