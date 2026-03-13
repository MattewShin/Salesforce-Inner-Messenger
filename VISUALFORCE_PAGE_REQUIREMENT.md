# Visualforce Page와 LWC 통합 구조

## ✅ 통합 완료: Visualforce Page에 LWC 포함

`utilityRequestOmniStatus.page` Visualforce 페이지에 `utilityRequest` LWC 컴포넌트가 포함되어 **하나의 통합된 컴포넌트**로 작동합니다.

### 왜 Visualforce Page가 필요한가?

1. **API 제약사항**: `sforce.console.presence.setServicePresenceStatus()`는 Visualforce Page 컨텍스트에서만 사용 가능
2. **LWC 제약사항**: LWC는 `sforce.console.presence` API를 직접 호출할 수 없음
3. **해결책**: Visualforce Page 내에 LWC를 포함시켜 하나로 통합

### 통합 구조

#### 1. Visualforce Page (`utilityRequestOmniStatus.page`)
- **역할**: 
  - LWC 컴포넌트를 포함하는 컨테이너
  - `sforce.console.presence` API를 사용하여 옴니채널 상태 변경 처리
- **기술**: Lightning Out을 사용하여 LWC 포함

#### 2. LWC 컴포넌트 (`utilityRequest`)
- **역할**: 사용자 인터페이스 제공 (휴가/휴무 신청, 캘린더 등)
- **위치**: Visualforce Page 내에 포함됨

#### 3. 통신 방식
- LWC에서 `CustomEvent('selectedstatus')` 발생
- Visualforce Page의 이벤트 리스너가 감지
- Visualforce Page에서 `sforce.console.presence.setServicePresenceStatus()` 호출

### 작동 방식

1. **Visualforce Page 로드**
   - Lightning Out을 통해 LWC 컴포넌트 초기화
   - 이벤트 리스너 등록

2. **사용자 인터랙션**
   - 사용자가 LWC UI에서 휴가/휴무 신청
   - LWC가 옴니채널 상태 변경 필요 시 `selectedstatus` 이벤트 발생

3. **옴니채널 상태 변경**
   - Visualforce Page의 이벤트 리스너가 이벤트 감지
   - `sforce.console.presence.setServicePresenceStatus()` 호출
   - 상태 변경 완료

### 배포 및 설정

#### Utility Bar 설정
- Setup → App Manager → Lightning App → Edit
- Utility Items에서 `utilityRequestOmniStatus` (Visualforce Page) 선택
- **Panel Height**: 600px (권장)
- **Panel Width**: 500px (권장)

#### 포함된 컴포넌트
- ✅ `utilityRequestOmniStatus.page` (Visualforce Page)
- ✅ `utilityRequest` (LWC - Visualforce Page 내에 포함)
- ✅ `utilityRequestApp` (Lightning Out 앱)

### 장점

1. **하나의 통합 컴포넌트**: Visualforce Page 하나로 모든 기능 제공
2. **사용자 경험**: LWC의 모던한 UI 제공
3. **기능 완전성**: 옴니채널 상태 변경 기능 포함
4. **유지보수**: 하나의 컴포넌트만 관리

### 참고사항

- Aura 컴포넌트 `utilityRequestOmniStatus`는 호환성을 위해 유지되지만, Visualforce Page를 직접 사용하는 것이 권장됩니다.
- Lightning Out을 사용하므로 보안 정책 설정이 필요할 수 있습니다.
