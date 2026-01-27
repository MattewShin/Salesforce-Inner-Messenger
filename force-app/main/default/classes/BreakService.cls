/**
 * ===========================================================================================
 * @description       : Service class for Break Request business logic (validation, duration calculation, time range validation)
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Break type validation, duration calculation, time range validation, and duplicate prevention
 */
public with sharing class BreakService {
    public class BreakValidationException extends Exception {}

    // Break Type 상수
    public static final String TYPE_MORNING_BREAK = 'Morning Break';
    public static final String TYPE_LUNCH = 'Lunch';
    public static final String TYPE_AFTERNOON_BREAK = 'Afternoon Break';

    // 시간 범위 정의 (시:분)
    public static final Integer MORNING_START_HOUR = 8;
    public static final Integer MORNING_END_HOUR = 12;
    public static final Integer LUNCH_START_HOUR = 11;
    public static final Integer LUNCH_START_MINUTE = 30;
    public static final Integer LUNCH_END_HOUR = 12;
    public static final Integer LUNCH_END_MINUTE = 30;
    public static final Integer AFTERNOON_START_HOUR = 13;
    public static final Integer AFTERNOON_END_HOUR = 18;

    // Duration (분)
    public static final Integer DURATION_MORNING_BREAK = 10;
    public static final Integer DURATION_LUNCH = 60;
    public static final Integer DURATION_AFTERNOON_BREAK = 10;

    /**
     * Break Type에 따른 예상 Duration 반환
     */
    public static Integer getExpectedDuration(String breakType) {
        if (breakType == TYPE_MORNING_BREAK) return DURATION_MORNING_BREAK;
        if (breakType == TYPE_LUNCH) return DURATION_LUNCH;
        if (breakType == TYPE_AFTERNOON_BREAK) return DURATION_AFTERNOON_BREAK;
        throw new BreakValidationException('Invalid break type: ' + breakType);
    }

    /**
     * Break Type에 따른 허용 시간 범위 반환 (시:분 단위)
     */
    public static Map<String, Integer> getAllowedTimeRange(String breakType) {
        Map<String, Integer> range = new Map<String, Integer>();
        if (breakType == TYPE_MORNING_BREAK) {
            range.put('startHour', MORNING_START_HOUR);
            range.put('startMinute', 0);
            range.put('endHour', MORNING_END_HOUR);
            range.put('endMinute', 0);
        } else if (breakType == TYPE_LUNCH) {
            range.put('startHour', LUNCH_START_HOUR);
            range.put('startMinute', LUNCH_START_MINUTE);
            range.put('endHour', LUNCH_END_HOUR);
            range.put('endMinute', LUNCH_END_MINUTE);
        } else if (breakType == TYPE_AFTERNOON_BREAK) {
            range.put('startHour', AFTERNOON_START_HOUR);
            range.put('startMinute', 0);
            range.put('endHour', AFTERNOON_END_HOUR);
            range.put('endMinute', 0);
        } else {
            throw new BreakValidationException('Invalid break type: ' + breakType);
        }
        return range;
    }

    /**
     * Time 필드를 분 단위로 변환 (자정 기준)
     */
    public static Integer timeToMinutes(Time t) {
        if (t == null) return 0;
        return (t.hour() * 60) + t.minute();
    }

    /**
     * 분 단위를 Time으로 변환
     */
    public static Time minutesToTime(Integer minutes) {
        if (minutes == null || minutes < 0) return null;
        Integer hours = minutes / 60;
        Integer mins = minutes - (hours * 60);
        return Time.newInstance(hours, mins, 0, 0);
    }

    /**
     * Duration 계산 (분 단위)
     */
    public static Integer calculateDuration(Time startTime, Time endTime) {
        if (startTime == null || endTime == null) {
            throw new BreakValidationException('Start time and end time are required.');
        }
        Integer startMinutes = timeToMinutes(startTime);
        Integer endMinutes = timeToMinutes(endTime);
        if (endMinutes < startMinutes) {
            throw new BreakValidationException('End time must be after start time.');
        }
        return endMinutes - startMinutes;
    }

    /**
     * Break Type과 시간 범위 검증
     */
    public static void validateTimeRange(String breakType, Time startTime, Time endTime) {
        if (String.isBlank(breakType)) {
            throw new BreakValidationException('Break type is required.');
        }
        if (startTime == null || endTime == null) {
            throw new BreakValidationException('Start time and end time are required.');
        }

        Map<String, Integer> allowedRange = getAllowedTimeRange(breakType);
        Integer startHour = allowedRange.get('startHour');
        Integer startMinute = allowedRange.get('startMinute');
        Integer endHour = allowedRange.get('endHour');
        Integer endMinute = allowedRange.get('endMinute');

        // 시작 시간을 분 단위로 변환
        Integer startTimeMinutes = timeToMinutes(startTime);
        Integer allowedStartMinutes = startHour * 60 + startMinute;
        Integer allowedEndMinutes = endHour * 60 + endMinute;

        // 시작 시간 검증
        // Lunch의 경우 12:30까지 포함 (>= 대신 > 사용)
        if (breakType == TYPE_LUNCH) {
            if (startTimeMinutes < allowedStartMinutes || startTimeMinutes > allowedEndMinutes) {
                String startTimeStr = startHour + '시 ' + startMinute + '분';
                String endTimeStr = endHour + '시 ' + endMinute + '분';
                throw new BreakValidationException(
                    breakType + '은(는) ' + startTimeStr + '부터 ' + endTimeStr + ' 사이에만 신청 가능합니다.'
                );
            }
        } else {
            // 다른 Break Type은 기존 로직 유지 (끝 시간 제외)
            if (startTimeMinutes < allowedStartMinutes || startTimeMinutes >= allowedEndMinutes) {
                String startTimeStr = startHour + '시 ' + startMinute + '분';
                String endTimeStr = endHour + '시 ' + endMinute + '분';
                throw new BreakValidationException(
                    breakType + '은(는) ' + startTimeStr + '부터 ' + endTimeStr + ' 사이에만 신청 가능합니다.'
                );
            }
        }

        // 종료 시간 검증 (같은 시간대 내)
        Integer endTimeMinutes = timeToMinutes(endTime);
        if (endTimeMinutes < allowedStartMinutes || endTimeMinutes > allowedEndMinutes) {
            String startTimeStr = startHour + '시 ' + startMinute + '분';
            String endTimeStr = endHour + '시 ' + endMinute + '분';
            throw new BreakValidationException(
                breakType + '의 종료 시간은 ' + startTimeStr + '부터 ' + endTimeStr + ' 사이여야 합니다.'
            );
        }

        // Duration 검증 (Break Type에 따라 다름 - 제출 시 자동 설정)
        Integer actualDuration = calculateDuration(startTime, endTime);
        Integer expectedDuration = getExpectedDuration(breakType);
        if (actualDuration != expectedDuration) {
            throw new BreakValidationException(
                breakType + '의 휴식 시간은 ' + expectedDuration + '분이어야 합니다. (현재: ' + actualDuration + '분)'
            );
        }
    }

    /**
     * 같은 날 같은 타입의 중복 휴식 방지 검증
     * 오전/오후 각각 1회만 허용
     */
    public static void validateNoDuplicate(Break_Request__c req) {
        if (req == null) return;
        if (req.Requester__c == null) {
            throw new BreakValidationException('Requester is required.');
        }
        if (req.Date__c == null) {
            throw new BreakValidationException('Date is required.');
        }
        if (String.isBlank(req.Break_Type__c)) {
            throw new BreakValidationException('Break type is required.');
        }

        // 오전/오후 각각 1회 제한 검증
        if (req.Break_Type__c == TYPE_MORNING_BREAK || req.Break_Type__c == TYPE_AFTERNOON_BREAK) {
            // 오전 또는 오후 타입인 경우, 해당 그룹의 승인된 휴식 개수 확인
            // 취소된 레코드는 제외 (취소 후 다시 신청 가능)
            String groupType = req.Break_Type__c == TYPE_MORNING_BREAK ? TYPE_MORNING_BREAK : TYPE_AFTERNOON_BREAK;
            
            List<Break_Request__c> existing = [
                SELECT Id, Name, Date__c, Break_Type__c, Status__c
                FROM Break_Request__c
                WHERE Requester__c = :req.Requester__c
                  AND Date__c = :req.Date__c
                  AND Break_Type__c = :groupType
                  AND Status__c = 'Approved'
                  AND Id != :req.Id
            ];

            if (!existing.isEmpty()) {
                String periodName = req.Break_Type__c == TYPE_MORNING_BREAK ? '오전' : '오후';
                throw new BreakValidationException(
                    periodName + ' 휴식은 하루에 1회만 사용할 수 있습니다.'
                );
            }
        } else {
            // Lunch는 기존 로직 유지 (같은 타입 중복 방지)
            List<Break_Request__c> existing = [
                SELECT Id, Name, Date__c, Break_Type__c, Status__c
                FROM Break_Request__c
                WHERE Requester__c = :req.Requester__c
                  AND Date__c = :req.Date__c
                  AND Break_Type__c = :req.Break_Type__c
                  AND Status__c = 'Approved'
                  AND Id != :req.Id
                LIMIT 1
            ];

            if (!existing.isEmpty()) {
                Break_Request__c existingReq = existing[0];
                throw new BreakValidationException(
                    '이미 ' + req.Date__c.format() + '에 ' + req.Break_Type__c + 
                    ' 휴식이 승인되어 있습니다. (레코드: ' + 
                    (String.isNotBlank(existingReq.Name) ? existingReq.Name : existingReq.Id) + ')'
                );
            }
        }
    }

    /**
     * 전체 검증 (시간 범위 + 중복)
     * 시간이 null인 경우 시간 범위 검증은 건너뜀 (제출 시 자동 설정)
     */
    public static void validateBreakRequest(Break_Request__c req) {
        if (req == null) {
            throw new BreakValidationException('Break request is required.');
        }
        // 시간이 있는 경우에만 시간 범위 검증 수행
        if (req.Start_Time__c != null && req.End_Time__c != null) {
            validateTimeRange(req.Break_Type__c, req.Start_Time__c, req.End_Time__c);
        }
        validateNoDuplicate(req);
    }
}