/**
 * ===========================================================================================
 * @description       : Controller for Break Request operations (CRUD, auto-approval, timer restoration)
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Break request CRUD operations, auto-approval, and active break timer restoration
 */
public without sharing class BreakRequestController {
    public class BreakRequestException extends Exception {}

    /**
     * 초안 저장/수정 (자동 승인 전 단계)
     */
    @AuraEnabled
    public static Break_Request__c upsertDraft(Break_Request__c draft) {
        if (draft == null) throw new BreakRequestException('Draft is required.');
        Id me = UserInfo.getUserId();
        if (draft.Requester__c == null) draft.Requester__c = me;
        if (draft.Status__c == null) draft.Status__c = 'Draft';
        if (draft.Requester__c != me) {
            throw new BreakRequestException('You can only create/edit your own break request.');
        }

        // 시간이 없으면 현재 시간부터 Break Type에 따라 자동 설정
        if (draft.Start_Time__c == null || draft.End_Time__c == null) {
            DateTime now = DateTime.now();
            draft.Start_Time__c = Time.newInstance(now.hour(), now.minute(), now.second(), now.millisecond());
            // Break Type에 따라 Duration 결정
            Integer durationMinutes = BreakService.getExpectedDuration(draft.Break_Type__c);
            DateTime endDateTime = now.addMinutes(durationMinutes);
            // End_Time__c는 초와 밀리초를 0으로 설정하여 정확한 duration 유지
            draft.End_Time__c = Time.newInstance(endDateTime.hour(), endDateTime.minute(), 0, 0);
        }

        // Duration 계산
        if (draft.Start_Time__c != null && draft.End_Time__c != null) {
            draft.Duration_Minutes__c = BreakService.calculateDuration(
                draft.Start_Time__c, 
                draft.End_Time__c
            );
        }

        // 검증 (시간 범위 + 중복)
        BreakService.validateBreakRequest(draft);

        upsert draft;
        return draft;
    }

    /**
     * 제출 (자동 승인)
     * 시간이 없으면 현재 시간부터 15분 후로 자동 설정
     */
    @AuraEnabled
    public static Break_Request__c submit(Id requestId) {
        if (requestId == null) throw new BreakRequestException('Request ID is required.');
        
        Break_Request__c req = [
            SELECT Id, Requester__c, Date__c, Break_Type__c, Start_Time__c, End_Time__c, Status__c
            FROM Break_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];
        
        Id me = UserInfo.getUserId();
        if (req.Requester__c != me) {
            throw new BreakRequestException('Only requester can submit.');
        }
        if (req.Status__c != 'Draft') {
            throw new BreakRequestException('Only Draft can be submitted.');
        }

        // 시간이 없으면 현재 시간부터 Break Type에 따라 자동 설정
        // 단, Break Type의 허용 시간 범위 내에서만 설정
        if (req.Start_Time__c == null || req.End_Time__c == null) {
            DateTime now = DateTime.now();
            Map<String, Integer> allowedRange = BreakService.getAllowedTimeRange(req.Break_Type__c);
            Integer startHour = allowedRange.get('startHour');
            Integer startMinute = allowedRange.get('startMinute');
            Integer endHour = allowedRange.get('endHour');
            Integer endMinute = allowedRange.get('endMinute');
            
            // 현재 시간을 분 단위로 변환
            Integer nowMinutes = (now.hour() * 60) + now.minute();
            Integer allowedStartMinutes = startHour * 60 + startMinute;
            Integer allowedEndMinutes = endHour * 60 + endMinute;
            
            // Lunch 타입인 경우: 현재 시간이 12:30을 넘었는지 확인
            if (req.Break_Type__c == BreakService.TYPE_LUNCH) {
                if (nowMinutes > allowedEndMinutes) {
                    // 12:30을 넘었으면 오류 메시지
                    throw new BreakRequestException(
                        'Lunch는 11시 30분부터 12시 30분 사이에만 신청 가능합니다. 현재 시간이 12시 30분을 넘었습니다.'
                    );
                }
            }
            
            // 현재 시간이 허용 범위 내에 있는지 확인
            Time startTime;
            if (nowMinutes >= allowedStartMinutes && nowMinutes <= allowedEndMinutes) {
                // 허용 범위 내: 현재 시간 사용 (12:30 포함)
                startTime = Time.newInstance(now.hour(), now.minute(), now.second(), now.millisecond());
            } else {
                // 허용 범위 밖: 허용 범위의 시작 시간 사용
                startTime = Time.newInstance(startHour, startMinute, 0, 0);
            }
            
            req.Start_Time__c = startTime;
            
            // Break Type에 따라 Duration 결정
            Integer durationMinutes = BreakService.getExpectedDuration(req.Break_Type__c);
            
            // End Time 계산 (허용 범위를 넘지 않도록)
            Integer startTimeMinutes = BreakService.timeToMinutes(startTime);
            Integer endTimeMinutes = startTimeMinutes + durationMinutes;
            
            // End Time이 허용 범위를 넘지 않도록 조정
            if (endTimeMinutes > allowedEndMinutes) {
                // 허용 범위의 끝 시간 사용
                req.End_Time__c = Time.newInstance(endHour, endMinute, 0, 0);
            } else {
            // 정상 범위 내: 계산된 End Time 사용 (초와 밀리초는 0으로 설정하여 정확한 duration 유지)
            DateTime startDateTime = DateTime.newInstance(Date.today(), startTime);
            DateTime endDateTime = startDateTime.addMinutes(durationMinutes);
            req.End_Time__c = Time.newInstance(endDateTime.hour(), endDateTime.minute(), 0, 0);
            }
        }

        // Duration 재계산
        if (req.Start_Time__c != null && req.End_Time__c != null) {
            req.Duration_Minutes__c = BreakService.calculateDuration(
                req.Start_Time__c, 
                req.End_Time__c
            );
        }

        // 최종 검증
        BreakService.validateBreakRequest(req);

        // 자동 승인
        req.Status__c = 'Approved';
        update req;

        return req;
    }

    /**
     * 취소 (신청자 본인만)
     */
    @AuraEnabled
    public static void cancel(Id requestId) {
        if (requestId == null) return;
        Break_Request__c req = [
            SELECT Id, Requester__c, Status__c 
            FROM Break_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];
        Id me = UserInfo.getUserId();
        if (req.Requester__c != me) {
            throw new BreakRequestException('Only requester can cancel.');
        }
        // 이미 취소된 경우 조용히 성공 처리 (중복 취소 방지)
        if (req.Status__c == 'Cancelled') {
            return; // 이미 취소되었으므로 성공으로 처리
        }
        req.Status__c = 'Cancelled';
        update req;
    }

    /**
     * 관리자 전용 취소 (롤백)
     * 관리자는 자신의 팀원의 휴식 신청을 취소할 수 있음
     */
    @AuraEnabled
    public static void cancelByManager(Id requestId) {
        if (requestId == null) {
            throw new BreakRequestException('Request ID is required.');
        }
        
        Break_Request__c req = [
            SELECT Id, Requester__c, Status__c, Date__c, Break_Type__c
            FROM Break_Request__c 
            WHERE Id = :requestId 
            LIMIT 1
        ];
        
        if (req == null) {
            throw new BreakRequestException('Break request not found.');
        }
        
        Id me = UserInfo.getUserId();
        
        // 관리자 권한 확인: Requester의 ManagerId가 현재 사용자인지 확인
        User requester = [
            SELECT Id, ManagerId 
            FROM User 
            WHERE Id = :req.Requester__c 
            LIMIT 1
        ];
        
        if (requester.ManagerId != me) {
            throw new BreakRequestException('Only the requester\'s manager can cancel this break request.');
        }
        
        // 이미 취소된 경우 조용히 성공 처리
        if (req.Status__c == 'Cancelled') {
            return;
        }
        
        req.Status__c = 'Cancelled';
        update req;
    }

    /**
     * 특정 날짜의 내 휴식 조회
     */
    @AuraEnabled(cacheable=true)
    public static List<Break_Request__c> getMyBreaks(Date targetDate) {
        if (targetDate == null) targetDate = Date.today();
        Id me = UserInfo.getUserId();
        return [
            SELECT Id, Name, Date__c, Break_Type__c, Start_Time__c, End_Time__c, 
                   Duration_Minutes__c, Status__c, Reason__c, CalendarEventId__c
            FROM Break_Request__c
            WHERE Requester__c = :me
              AND Date__c = :targetDate
            ORDER BY Start_Time__c ASC
        ];
    }

    /**
     * 날짜 범위의 내 휴식 조회 (내역용 - 모든 상태)
     */
    @AuraEnabled(cacheable=true)
    public static List<Break_Request__c> getMyBreaksHistory(Date startDate, Date endDate) {
        if (startDate == null) startDate = Date.today().addMonths(-3);
        if (endDate == null) endDate = Date.today().addMonths(3);
        Id me = UserInfo.getUserId();
        return [
            SELECT Id, Name, Date__c, Break_Type__c, Start_Time__c, End_Time__c, 
                   Duration_Minutes__c, Status__c, Reason__c, CalendarEventId__c
            FROM Break_Request__c
            WHERE Requester__c = :me
              AND Date__c >= :startDate
              AND Date__c <= :endDate
            ORDER BY CreatedDate DESC, Date__c DESC, Start_Time__c DESC
        ];
    }

    /**
     * 날짜 범위의 내 휴식 조회 (캘린더용)
     */
    @AuraEnabled(cacheable=true)
    public static List<Break_Request__c> getMyBreaksRange(Date startDate, Date endDate) {
        if (startDate == null) startDate = Date.today();
        if (endDate == null) endDate = startDate.addDays(30);
        Id me = UserInfo.getUserId();
        return [
            SELECT Id, Name, Date__c, Break_Type__c, Start_Time__c, End_Time__c, 
                   Duration_Minutes__c, Status__c, Reason__c, CalendarEventId__c
            FROM Break_Request__c
            WHERE Requester__c = :me
              AND Date__c >= :startDate
              AND Date__c <= :endDate
              AND Status__c = 'Approved'
            ORDER BY Date__c ASC, Start_Time__c ASC
        ];
    }

    /**
     * 현재 진행 중인 휴식 신청 조회 (타이머 복원용)
     * 오늘 날짜의 Approved 상태이고, End_Time__c가 아직 지나지 않은 휴식을 반환
     */
    @AuraEnabled(cacheable=false)
    public static Break_Request__c getActiveBreak() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        DateTime now = DateTime.now();
        Time currentTime = Time.newInstance(now.hour(), now.minute(), now.second(), now.millisecond());
        
        List<Break_Request__c> activeBreaks = [
            SELECT Id, Break_Type__c, Start_Time__c, End_Time__c, Date__c, Status__c
            FROM Break_Request__c
            WHERE Requester__c = :me
              AND Date__c = :today
              AND Status__c = 'Approved'
              AND End_Time__c > :currentTime
              AND (Break_Type__c = 'Morning Break' OR Break_Type__c = 'Afternoon Break' OR Break_Type__c = 'Lunch')
            ORDER BY Start_Time__c DESC
            LIMIT 1
        ];
        
        if (activeBreaks.isEmpty()) {
            return null;
        }
        return activeBreaks[0];
    }
    
}