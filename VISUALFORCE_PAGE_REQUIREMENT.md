# Visualforce Page 필수 요구사항

## ⚠️ 중요: Visualforce Page는 제거할 수 없습니다

`sforce.console.presence` API는 **Visualforce Page가 Omni-Channel Console의 직접적인 컨텍스트에 있어야만** 작동합니다.

### 왜 Visualforce Page가 필요한가?

1. **API 제약사항**: `sforce.console.presence.setServicePresenceStatus()`는 Visualforce Page 컨텍스트에서만 사용 가능
2. **LWC 제약사항**: LWC는 `sforce.console.presence` API를 직접 호출할 수 없음
3. **iframe 제약사항**: iframe으로 포함된 Visualforce Page도 작동하지 않음 (부모 창이 Omni-Channel Console이어야 함)

### 해결 방법: Visualforce Page 최소화

Visualforce Page를 Utility Bar에 유지하되, 최소한의 크기로 설정하여 사용자가 보지 않도록 할 수 있습니다:

#### 1. Utility Bar 설정에서 최소화
- Setup → App Manager → Lightning App → Edit
- Utility Items에서 `utilityRequestOmniStatus` 선택
- **Panel Height**: 최소값 (예: 50px)
- **Panel Width**: 최소값 (예: 50px)
- 또는 **Icon Only** 모드 사용 (가능한 경우)

#### 2. Visualforce Page 스타일 최소화
현재 `utilityRequestOmniStatus.page`는 이미 최소화되어 있습니다:
- `showHeader="false"` - 헤더 숨김
- `sidebar="false"` - 사이드바 숨김
- 투명 배경
- 이벤트 리스너만 작동

#### 3. 사용자 경험
- Visualforce Page는 Utility Bar에 작은 아이콘으로만 표시
- 사용자는 "Request" (LWC)만 사용
- Visualforce Page는 백그라운드에서 이벤트만 리스닝

### 현재 작동 방식

1. **LWC** (`utilityRequest`): 사용자가 실제로 사용하는 컴포넌트
2. **Visualforce Page** (`utilityRequestOmniStatus`): 백그라운드에서 이벤트 리스닝만 수행
3. **이벤트 흐름**:
   - LWC에서 `setOmniOnBreak()` 또는 `setOmniAvailable()` 호출
   - `window.dispatchEvent()`로 전역 이벤트 발생
   - Visualforce Page의 전역 이벤트 리스너가 감지
   - Visualforce Page에서 `sforce.console.presence.setServicePresenceStatus()` 호출

### 권장 사항

**Visualforce Page를 Utility Bar에 유지하되, 최소화하세요:**
- Utility Bar 설정에서 크기를 최소화
- 사용자는 "Request" (LWC)만 사용
- Visualforce Page는 백그라운드에서만 작동

이것이 현재 기술적 제약사항 하에서 가장 현실적인 해결책입니다.
