# Salesforce Inner Messenger (Utility Chat) 배포 가이드

이 레포는 **유틸리티 바 기반 사내 메신저(Platform Event 실시간 포함)**를 다른 Org로 배포하기 위한 Salesforce DX 프로젝트입니다.

## 포함 메타데이터(배포 최소셋)

배포는 `manifest/package.xml` 기준으로 진행합니다.

- **Apex**: `ChatController`, `ChatController_Test`
- **LWC(Utility Bar)**: `utilityChat`
- **Aura(플래시/알림)**: `chatFlashAura`
- **CustomObject**
  - `Chat_Session__c`
  - `Chat_Message__c`
  - `Chat_Participant__c`
  - `Chat_Notification__e` (Platform Event)
- **PermissionSet**: `Internal_Chat_Permission_Set`

## 배포 방법(Sales App 메타는 미포함)

1) 대상 Org에 로그인(예시)

```bash
sf org login web -a target
```

2) 배포(테스트 포함)

```bash
sf project deploy start --target-org target --manifest manifest/package.xml --test-level RunLocalTests
```

운영/제한된 배포 정책에서 “지정 테스트만”으로 실행하고 싶으면(조직 정책에 따라 불가할 수 있음):

```bash
sf project deploy start --target-org target --manifest manifest/package.xml --test-level RunSpecifiedTests --tests ChatController_Test
```

## 배포 후 수동으로 해야 하는 작업(중요)

이 프로젝트는 **Sales App(앱/페이지 배치) 메타데이터는 의도적으로 포함하지 않습니다.**  
따라서 아래 작업은 대상 Org에서 수동 설정이 필요합니다.

### 1) 권한 부여(필수)

- **Permission Set 할당**: `Internal_Chat_Permission_Set`
  - Setup → Users → 해당 사용자 → Permission Set Assignments
  - 이 Permission Set에는 Chat 오브젝트 CRUD/FLS와 Platform Event/Streaming 관련 권한이 포함되어 있습니다.

### 2) Utility Bar에 `utilityChat` 배치(필수)

- Setup → App Manager → (사용할 Lightning App) → **Edit**
- **Utility Items**에서 `utilityChat`(LWC) 추가
  - `utilityChat.js-meta.xml`에 정의된 height/width 기본값을 참고해서 크기 조정

### 3) 실시간 “플래시 알림”을 쓰려면 `chatFlashAura`도 어디엔가 올려야 함(권장)

`chatFlashAura`는 UI가 아니라 **백그라운드에서 Platform Event를 구독하고 유틸리티를 하이라이트**하는 용도입니다.

- Lightning App Builder에서 (항상 열리는) Home/App Page 등에 `chatFlashAura` 컴포넌트를 한 번 배치
  - 배치 위치/페이지 메타는 이 레포에 포함하지 않았기 때문에 “어디에 둘지”는 운영 환경에 맞게 선택해야 합니다.

### 4) EMP API(Platform Event) 동작 전제 조건(필수)

- **My Domain이 활성화/Deploy**되어 있어야 `lightning:empApi`/Platform Event 구독이 정상 동작합니다.
  - Setup → Company Settings → My Domain

### 5) 파일 첨부 기능을 쓸 경우(선택)

현재 채팅은 `ContentDocumentLink`로 파일을 메시지에 연결합니다.

- 사용자에게 **Files 관련 접근 권한**이 필요할 수 있습니다(조직 보안 정책/프로파일에 따라 상이).
- 업로드/미리보기에서 권한 문제가 발생하면, 프로파일/퍼미션셋의 Files 관련 권한을 추가로 점검하세요.

## 참고

- 실시간 채널: `/event/Chat_Notification__e`
- 테스트 클래스: `ChatController_Test` (배포 시 75%+ 커버리지 충족 목적)
