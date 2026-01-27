# 배포 후 필수 수동 작업 가이드

## 🔴 필수 작업 (반드시 수행해야 함)

### 1. Omni-Channel Presence Status 확인 및 생성

옴니채널 상태가 Org에 존재하는지 확인하고, 없으면 생성해야 합니다.

#### 확인 방법:
1. Setup → **Omni-Channel** → **Service Presence Statuses** 이동
2. 다음 상태들이 존재하는지 확인:
   - **OnBreak** (또는 DeveloperName: `OnBreak`)
   - **Available** 또는 **OK** (DeveloperName: `Available` 또는 `OK`)

#### 상태가 없는 경우 생성:
1. Setup → **Omni-Channel** → **Service Presence Statuses** → **New**
2. **OnBreak** 상태 생성:
   - **Label**: `On Break` (또는 원하는 라벨)
   - **Developer Name**: `OnBreak` (반드시 이 이름이어야 함)
   - **Status Type**: `Away` 또는 적절한 타입 선택
3. **Available** 또는 **OK** 상태 확인:
   - 일반적으로 기본 상태로 존재함
   - 없으면 생성 (DeveloperName: `Available` 또는 `OK`)

#### 중요:
- `OmniPresenceHelper.cls`는 `DeveloperName = 'OnBreak'` 또는 `MasterLabel = 'OnBreak'`로 조회합니다
- `Available` 또는 `OK` 상태도 동일하게 조회합니다
- 상태가 없으면 휴식 신청 시 옴니채널 상태 변경이 작동하지 않습니다

---

### 2. Visualforce Page를 Omni-Channel Console에 추가

`sforce.console.presence` API는 Visualforce Page 컨텍스트에서만 작동하므로, Visualforce Page를 Omni-Channel Console에 탭으로 추가해야 합니다.

#### 방법 1: Omni-Channel Console에 탭으로 추가 (권장)
1. Setup → **Omni-Channel** → **Omni-Channel Settings** 이동
2. 사용 중인 **Omni-Channel Configuration** 선택
3. **Utility Items** 또는 **Console Layout** 섹션에서:
   - **Add Utility Item** 또는 **Add Tab** 클릭
   - **Visualforce Page** 선택
   - `utilityRequestOmniStatus` 선택
   - 적절한 라벨 설정 (예: "Request Omni Status")
   - **Save**

#### 방법 2: Utility Bar에 Visualforce Page 추가 (대안)
1. Setup → **App Manager** → 사용 중인 Lightning App 선택 → **Edit**
2. **Utility Items** 섹션에서:
   - **Add Utility Item** 클릭
   - **Visualforce Page** 선택
   - `utilityRequestOmniStatus` 선택
   - **Save**

#### ⚠️ "No Visualforce pages available" 에러 해결 방법

만약 "No Visualforce pages available" 에러가 발생하면 다음을 확인하세요:

1. **Visualforce Page 배포 확인**:
   ```bash
   # Visualforce Page만 다시 배포
   sf project deploy start --source-dir force-app/main/default/pages --target-org <your-org-alias>
   ```

2. **Visualforce Page 직접 접근 테스트**:
   - 브라우저에서 다음 URL로 직접 접근:
     ```
     https://<your-instance>.salesforce.com/apex/utilityRequestOmniStatus
     ```
   - 페이지가 정상적으로 로드되는지 확인
   - 컴파일 에러가 있으면 에러 메시지 확인

3. **Setup에서 Visualforce Page 목록 확인**:
   - Setup → **Custom Code** → **Visualforce Pages** 이동
   - `utilityRequestOmniStatus`가 목록에 있는지 확인
   - 없으면 배포가 실패한 것

4. **Visualforce Page 메타데이터 확인**:
   - `utilityRequestOmniStatus.page-meta.xml` 파일이 올바른지 확인
   - API 버전이 Org에서 지원하는 버전인지 확인

5. **권한 확인**:
   - 현재 사용자에게 Visualforce Page 접근 권한이 있는지 확인
   - Profile 또는 Permission Set에서 Visualforce Page 접근 권한 확인

#### 중요:
- Visualforce Page가 열려 있어야 `sforce.console.presence` API가 작동합니다
- Visualforce Page는 백그라운드에서 실행되어도 이벤트를 리스닝할 수 있습니다
- 하지만 최소한 한 번은 열어야 이벤트 리스너가 등록됩니다

---

### 3. Visualforce Page의 integration.js 버전 확인

현재 Visualforce Page는 `/support/console/60.0/integration.js`를 사용합니다.

#### API 버전 확인 방법:
1. **Setup에서 확인**:
   - Setup → **Company Information** → **Organization Edition** 확인
   - 또는 Setup → **Custom Code** → **Visualforce Pages**에서 다른 페이지들의 API 버전 확인

2. **Visualforce Page API 버전 확인**:
   - Setup → **Custom Code** → **Visualforce Pages** 이동
   - `utilityRequestOmniStatus`의 API 버전 확인 (현재 65.0)
   - `integration.js` 버전은 일반적으로 Visualforce Page API 버전과 같거나 낮은 버전 사용 가능

3. **integration.js 버전 수정** (필요 시):
   - `force-app/main/default/pages/utilityRequestOmniStatus.page` 파일 수정
   - `/support/console/60.0/integration.js`를 Org에서 지원하는 버전으로 변경
   - 일반적으로 60.0 또는 65.0 사용 가능

---

## 🟡 권장 작업 (기능 최적화를 위해)

### 4. 테스트 및 검증

배포 후 다음 시나리오를 테스트하세요:

1. **휴식 신청 시 상태 변경 테스트**:
   - `utilityRequest` LWC에서 휴식 신청 (Morning Break 또는 Afternoon Break)
   - Omni-Channel 상태가 `OnBreak`로 변경되는지 확인
   - 브라우저 콘솔에서 로그 확인

2. **타이머 종료 시 상태 복귀 테스트**:
   - 휴식 타이머가 종료되면
   - Omni-Channel 상태가 `Available` 또는 `OK`로 복귀하는지 확인

3. **에러 확인**:
   - 브라우저 개발자 도구 콘솔에서 에러 메시지 확인
   - `onBreakId` 또는 `availableChatId`가 로드되지 않으면 상태가 존재하지 않는 것

---

## 🔵 선택 작업 (문제 발생 시)

### 5. 문제 해결

#### 문제: 상태가 변경되지 않음
- **원인 1**: `OnBreak` 또는 `Available` 상태가 Org에 없음
  - **해결**: 위의 "1. Omni-Channel Presence Status 확인 및 생성" 참조

- **원인 2**: Visualforce Page가 열려 있지 않음
  - **해결**: Visualforce Page를 최소한 한 번은 열어야 이벤트 리스너가 등록됨

- **원인 3**: integration.js 버전 불일치
  - **해결**: 위의 "3. Visualforce Page의 integration.js 버전 확인" 참조

#### 문제: 콘솔에 에러 메시지
- 브라우저 개발자 도구 콘솔 확인
- `OmniPresenceHelper.getServicePresenceStatusId()` 결과 확인
- Apex Debug Log에서 SOQL 쿼리 결과 확인

---

## 📝 체크리스트

배포 후 다음 항목을 확인하세요:

- [ ] `OnBreak` 상태가 Omni-Channel에 존재하는가?
- [ ] `Available` 또는 `OK` 상태가 Omni-Channel에 존재하는가?
- [ ] Visualforce Page (`utilityRequestOmniStatus`)가 Omni-Channel Console 또는 Utility Bar에 추가되었는가?
- [ ] Visualforce Page를 최소한 한 번 열었는가?
- [ ] 휴식 신청 시 옴니채널 상태가 변경되는가?
- [ ] 타이머 종료 시 옴니채널 상태가 복귀하는가?
- [ ] 브라우저 콘솔에 에러가 없는가?

---

## ⚠️ 중요 참고사항

1. **Visualforce Page는 반드시 열려 있어야 함**:
   - `sforce.console.presence` API는 Visualforce Page 컨텍스트에서만 작동합니다
   - Visualforce Page를 백그라운드 탭으로 열어두면 이벤트를 계속 리스닝할 수 있습니다

2. **상태 이름은 대소문자 구분**:
   - `OnBreak` (O, B 대문자)
   - `Available` 또는 `OK`

3. **15자리 ID 사용**:
   - 코드에서 자동으로 15자리로 substring 처리하므로 걱정하지 마세요
