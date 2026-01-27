/**
 * ===========================================================================================
 * @description       : Controller for retrieving leave balance information (yearly balances, used/remaining days)
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Retrieving yearly leave balances and remaining days for utility bar component
 */
public without sharing class LeaveBalanceController {
    public class LeaveBalanceDTO {
        @AuraEnabled public Decimal totalDays;
        @AuraEnabled public Decimal usedDays;
        @AuraEnabled public Decimal remainingDays;
        @AuraEnabled public Integer year;
    }

    // 연도별 전체 휴가 일수 조회 (유틸리티 바 \"일수 확인\"용)
    @AuraEnabled(cacheable=true)
    public static List<LeaveBalanceDTO> getMyYearlyBalances() {
        Id me = UserInfo.getUserId();

        // 1) 사용자의 모든 연차 부여 정보 조회
        List<Leave_Entitlement__c> ents = [
            SELECT Year__c, Total_Days__c
            FROM Leave_Entitlement__c
            WHERE User__c = :me
            ORDER BY Year__c ASC
        ];
        if (ents.isEmpty()) {
            return new List<LeaveBalanceDTO>();
        }

        // 2) Year__c(Text)를 Integer 연도로 변환
        Set<Integer> yearSet = new Set<Integer>();
        Map<Integer, Decimal> totalByYear = new Map<Integer, Decimal>();
        for (Leave_Entitlement__c e : ents) {
            if (String.isBlank(e.Year__c)) continue;
            Integer y;
            try {
                y = Integer.valueOf(e.Year__c);
            } catch (Exception ex) {
                continue;
            }
            yearSet.add(y);
            totalByYear.put(y, e.Total_Days__c == null ? 0 : e.Total_Days__c);
        }
        if (yearSet.isEmpty()) {
            return new List<LeaveBalanceDTO>();
        }

        // 3) 연도별 사용 일수 집계 (Approved / CancelSubmitted)
        Set<String> useStatuses = new Set<String>{ 'Approved', 'CancelSubmitted' };
        List<AggregateResult> usedAgg = [
            SELECT CALENDAR_YEAR(Start_Date__c) y, SUM(Days__c) sumDays
            FROM Leave_Request__c
            WHERE Requester__c = :me
              AND Status__c IN :useStatuses
              AND CALENDAR_YEAR(Start_Date__c) IN :yearSet
            GROUP BY CALENDAR_YEAR(Start_Date__c)
        ];
        Map<Integer, Decimal> usedByYear = new Map<Integer, Decimal>();
        for (AggregateResult ar : usedAgg) {
            Integer y = (Integer) ar.get('y');
            Decimal sumDays = (Decimal) ar.get('sumDays');
            usedByYear.put(y, sumDays == null ? 0 : sumDays);
        }

        // 4) DTO 리스트 생성 (연도 오름차순)
        List<Integer> years = new List<Integer>(yearSet);
        years.sort();

        List<LeaveBalanceDTO> result = new List<LeaveBalanceDTO>();
        for (Integer y : years) {
            LeaveBalanceDTO dto = new LeaveBalanceDTO();
            dto.year = y;
            dto.totalDays = totalByYear.containsKey(y) ? totalByYear.get(y) : 0;
            dto.usedDays = usedByYear.containsKey(y) ? usedByYear.get(y) : 0;
            dto.remainingDays = dto.totalDays - dto.usedDays;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static LeaveBalanceDTO getMyBalance(Integer yearParam) {
        Integer year = (yearParam == null) ? Date.today().year() : yearParam;
        Id me = UserInfo.getUserId();

        Date yearStart = Date.newInstance(year, 1, 1);
        Date yearEnd   = Date.newInstance(year, 12, 31);

        // 1) 연간 부여 일수 (Year__c는 Text 필드)
        // Year__c 값이 "2026" 형식인지 확인 필요 (공백/쉼표 제거)
        Decimal total = 0;
        String yearStr = String.valueOf(year).trim();
        List<Leave_Entitlement__c> ents = [
            SELECT Total_Days__c, Year__c, User__c, OwnerId
            FROM Leave_Entitlement__c
            WHERE User__c = :me
              AND Year__c = :yearStr
            LIMIT 1
        ];
        if (!ents.isEmpty() && ents[0].Total_Days__c != null) {
            total = ents[0].Total_Days__c;
        }

        // 2) 사용 일수 (Approved / CancelSubmitted)
        Set<String> useStatuses = new Set<String>{ 'Approved', 'CancelSubmitted' };
        Decimal used = 0;
        AggregateResult ar = [
            SELECT SUM(Days__c) sumDays
            FROM Leave_Request__c
            WHERE Requester__c = :me
              AND Status__c IN :useStatuses
              AND Start_Date__c >= :yearStart
              AND Start_Date__c <= :yearEnd
        ];
        if (ar != null && ar.get('sumDays') != null) {
            used = (Decimal) ar.get('sumDays');
        }

        LeaveBalanceDTO dto = new LeaveBalanceDTO();
        dto.totalDays = total;
        dto.usedDays = used;
        dto.remainingDays = total - used;
        dto.year = year;
        return dto;
    }
}