/**
 * ===========================================================================================
 * @description       : Controller for Work Time operations (clock in/out, work time tracking)
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Work time clock in/out and tracking
 */
public without sharing class WorkTimeController {
    public class WorkTimeException extends Exception {}

    /**
     * 출근 처리 (Work Start Time 기록)
     * 오늘 날짜의 근무 시간 레코드가 없으면 생성, 있으면 업데이트
     */
    @AuraEnabled
    public static Work_Time__c clockIn() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        DateTime now = DateTime.now();
        Time currentTime = Time.newInstance(now.hour(), now.minute(), now.second(), now.millisecond());

        // 오늘 날짜의 근무 시간 레코드 조회
        List<Work_Time__c> existingWorkTimes = [
            SELECT Id, Work_Start_Time__c, Work_End_Time__c, Status__c
            FROM Work_Time__c
            WHERE User__c = :me
              AND Work_Date__c = :today
            LIMIT 1
        ];

        Work_Time__c workTime;
        if (!existingWorkTimes.isEmpty()) {
            workTime = existingWorkTimes[0];
            // 이미 출근한 경우 (Work_Start_Time__c가 있고 Status__c가 'On Duty')
            if (workTime.Work_Start_Time__c != null && workTime.Status__c == 'On Duty') {
                throw new WorkTimeException('이미 출근 처리되었습니다.');
            }
            // 출근 시간 업데이트
            workTime.Work_Start_Time__c = currentTime;
            // 요구사항: OFF → ON 재출근 시 기존 퇴근 시간은 제거해야 함
            workTime.Work_End_Time__c = null;
            workTime.Status__c = 'On Duty';
            update workTime;
        } else {
            // 새 레코드 생성
            workTime = new Work_Time__c(
                User__c = me,
                Work_Date__c = today,
                Work_Start_Time__c = currentTime,
                Status__c = 'On Duty'
            );
            insert workTime;
        }

        return workTime;
    }

    /**
     * 퇴근 처리 (Work End Time 기록)
     * 오늘 날짜의 근무 시간 레코드에 퇴근 시간 업데이트
     */
    @AuraEnabled
    public static Work_Time__c clockOut() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        DateTime now = DateTime.now();
        Time currentTime = Time.newInstance(now.hour(), now.minute(), now.second(), now.millisecond());

        // 오늘 날짜의 근무 시간 레코드 조회
        List<Work_Time__c> existingWorkTimes = [
            SELECT Id, Work_Start_Time__c, Work_End_Time__c, Status__c
            FROM Work_Time__c
            WHERE User__c = :me
              AND Work_Date__c = :today
              AND Status__c = 'On Duty'
            LIMIT 1
        ];

        if (existingWorkTimes.isEmpty()) {
            throw new WorkTimeException('출근 기록이 없습니다. 먼저 출근 처리해주세요.');
        }

        Work_Time__c workTime = existingWorkTimes[0];
        
        // 이미 퇴근한 경우
        if (workTime.Work_End_Time__c != null && workTime.Status__c == 'Off Duty') {
            throw new WorkTimeException('이미 퇴근 처리되었습니다.');
        }

        // 퇴근 시간이 출근 시간보다 이전인지 확인
        if (workTime.Work_Start_Time__c != null && currentTime < workTime.Work_Start_Time__c) {
            throw new WorkTimeException('퇴근 시간은 출근 시간보다 이후여야 합니다.');
        }

        // 퇴근 시간 업데이트
        workTime.Work_End_Time__c = currentTime;
        workTime.Status__c = 'Off Duty';
        update workTime;

        return workTime;
    }

    /**
     * 오늘 날짜의 현재 근무 상태 조회
     */
    @AuraEnabled(cacheable=false)
    public static Work_Time__c getTodayWorkTime() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();

        List<Work_Time__c> workTimes = [
            SELECT Id, Work_Date__c, Work_Start_Time__c, Work_End_Time__c, Status__c
            FROM Work_Time__c
            WHERE User__c = :me
              AND Work_Date__c = :today
            LIMIT 1
        ];

        if (workTimes.isEmpty()) {
            return null;
        }

        return workTimes[0];
    }

    /**
     * 날짜 범위의 근무 시간 조회 (내역용)
     */
    @AuraEnabled(cacheable=true)
    public static List<Work_Time__c> getWorkTimeHistory(Date startDate, Date endDate) {
        if (startDate == null) startDate = Date.today().addMonths(-3);
        if (endDate == null) endDate = Date.today().addMonths(3);
        Id me = UserInfo.getUserId();
        return [
            SELECT Id, Name, Work_Date__c, Work_Start_Time__c, Work_End_Time__c, Status__c
            FROM Work_Time__c
            WHERE User__c = :me
              AND Work_Date__c >= :startDate
              AND Work_Date__c <= :endDate
            ORDER BY Work_Date__c DESC, Work_Start_Time__c DESC
        ];
    }
}
