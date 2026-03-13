# 롤백 백업 문서
## 통합 작업 전 상태 (2026-03-12)

### 현재 구조
- **chatFlashAura**: Aura 컴포넌트로 Flash 기능만 담당
- **utilityChat**: LWC 컴포넌트로 채팅 UI 및 Platform Event 구독 담당
- 두 컴포넌트가 별도로 Utility Bar에 등록되어 있음

### 주요 파일 위치
1. `force-app/main/default/aura/chatFlashAura/chatFlashAura.cmp`
2. `force-app/main/default/aura/chatFlashAura/chatFlashAura.cmp-meta.xml`
3. `force-app/main/default/lwc/utilityChat/utilityChat.js`
4. `force-app/main/default/lwc/utilityChat/utilityChat.js-meta.xml`

### 롤백 방법
1. chatFlashAura.cmp를 원래 상태로 복원 (LWC 포함 제거)
2. chatFlashAura.cmp-meta.xml에서 lightning__UtilityBar 타겟 제거
3. utilityChat.js의 Platform Event 구독 코드 복원
4. utilityChat.js-meta.xml은 그대로 유지 (Utility Bar 타겟 유지)

### 변경 전 주요 코드

#### chatFlashAura.cmp
- UI: 디버그 메시지만 표시
- Flash 기능만 담당
- Utility Bar 타겟 없음

#### utilityChat.js
- handleSubscribe(): Platform Event 구독
- handleUnsubscribe(): Platform Event 구독 해제
- messageCallback: 이벤트 처리 로직 포함

---

## utilityRequestOmniStatus 통합 작업 전 상태 (2026-03-12)

### 현재 구조
- **utilityRequestOmniStatus**: Aura App (`.app` 파일)로 존재
- **utilityRequest**: LWC 컴포넌트로 Request UI 담당
- 두 컴포넌트가 별도로 Utility Bar에 등록되어 있음

### 주요 파일 위치
1. `force-app/main/default/aura/utilityRequestOmniStatus/utilityRequestOmniStatus.app`
2. `force-app/main/default/aura/utilityRequestOmniStatus/utilityRequestOmniStatus.app-meta.xml`
3. `force-app/main/default/lwc/utilityRequest/utilityRequest.js`
4. `force-app/main/default/lwc/utilityRequest/utilityRequest.js-meta.xml`

### 변경 전 주요 코드

#### utilityRequestOmniStatus.app
```xml
<aura:application access="global" extends="ltng:outApp">
    <aura:dependency resource="c:utilityRequest"/>
</aura:application>
```

#### utilityRequestOmniStatus.app-meta.xml
```xml
<?xml version="1.0" encoding="UTF-8"?>
<AuraDefinitionBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>65.0</apiVersion>
    <description>Aura App for loading utilityRequest LWC component with Omni-Channel status integration</description>
</AuraDefinitionBundle>
```

### 롤백 방법
1. 새로 생성된 `utilityRequestOmniStatus.cmp` 파일 삭제
2. 새로 생성된 `utilityRequestOmniStatusController.js` 파일 삭제
3. `utilityRequestOmniStatus.cmp-meta.xml` 파일 삭제
4. `utilityRequestOmniStatus.app` 파일 복원
5. `utilityRequestOmniStatus.app-meta.xml` 파일 복원
