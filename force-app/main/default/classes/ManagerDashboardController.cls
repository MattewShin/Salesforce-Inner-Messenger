/**
 * ===========================================================================================
 * @description       : Controller for Manager Dashboard (team member status, leave/break request management)
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Retrieving team member status (leave/break) and managing team leave/break requests
 */
public with sharing class ManagerDashboardController {
    public class AgentStatusDTO {
        @AuraEnabled public String userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String leaveStatus; // 'On Leave', 'Available'
        @AuraEnabled public String morningBreak; // 'Used', 'Available', 'Scheduled'
        @AuraEnabled public String lunch; // 'Used', 'Available', 'Scheduled'
        @AuraEnabled public String afternoonBreak; // 'Used', 'Available', 'Scheduled'
    }

    /**
     * 당일 기준 모든 상담사(직원)의 휴가/휴식 상태 조회
     * 매니저는 자신의 팀원들만 조회 가능
     */
    @AuraEnabled(cacheable=true)
    public static List<AgentStatusDTO> getTodayStatus() {
        Date today = Date.today();
        Id currentUserId = UserInfo.getUserId();
        
        // 현재 시간 기준으로 판단(AM/PM 구분)
        Time now = Time.newInstance(
            DateTime.now().hour(),
            DateTime.now().minute(),
            0,
            0
        );
        Time noon = Time.newInstance(12, 0, 0, 0);

        // 현재 사용자의 팀원 조회 (ManagerId가 currentUserId인 사용자들)
        List<User> teamMembers = [
            SELECT Id, Name
            FROM User
            WHERE ManagerId = :currentUserId
              AND IsActive = true
            ORDER BY Name ASC
        ];

        if (teamMembers.isEmpty()) {
            return new List<AgentStatusDTO>();
        }

        Set<Id> teamMemberIds = new Set<Id>();
        Map<Id, String> userIdToName = new Map<Id, String>();
        for (User u : teamMembers) {
            teamMemberIds.add(u.Id);
            userIdToName.put(u.Id, u.Name);
        }

        // 1) 당일 휴가 상태 조회 (Approved 또는 CancelSubmitted)
        Set<Id> onLeaveUserIds = new Set<Id>();
        List<Leave_Request__c> todayLeaves = [
            SELECT Id, Requester__c, Status__c,
                   Start_Date__c, End_Date__c, Start_Slot__c, End_Slot__c
            FROM Leave_Request__c
            WHERE Requester__c IN :teamMemberIds
              AND Start_Date__c <= :today
              AND End_Date__c >= :today
              AND Status__c IN ('Approved', 'CancelSubmitted')
        ];
        for (Leave_Request__c lr : todayLeaves) {
            // PM 시작 휴가의 오전 시간대는 "근무중"으로 표시해야 함
            if (isLeaveActiveNow(lr, today, now, noon)) {
                onLeaveUserIds.add(lr.Requester__c);
            }
        }

        // 2) 당일 휴식 상태 조회 (Approved만)
        Map<Id, Map<String, Break_Request__c>> userBreakMap = new Map<Id, Map<String, Break_Request__c>>();
        List<Break_Request__c> todayBreaks = [
            SELECT Id, Requester__c, Break_Type__c, Start_Time__c, Status__c
            FROM Break_Request__c
            WHERE Requester__c IN :teamMemberIds
              AND Date__c = :today
              AND Status__c = 'Approved'
        ];
        for (Break_Request__c br : todayBreaks) {
            if (!userBreakMap.containsKey(br.Requester__c)) {
                userBreakMap.put(br.Requester__c, new Map<String, Break_Request__c>());
            }
            userBreakMap.get(br.Requester__c).put(br.Break_Type__c, br);
        }

        // 4) DTO 생성
        List<AgentStatusDTO> result = new List<AgentStatusDTO>();
        for (Id userId : teamMemberIds) {
            AgentStatusDTO dto = new AgentStatusDTO();
            dto.userId = userId;
            dto.userName = userIdToName.get(userId);
            dto.leaveStatus = onLeaveUserIds.contains(userId) ? 'On Leave' : 'Available';

            // Morning Break
            if (userBreakMap.containsKey(userId) && 
                userBreakMap.get(userId).containsKey(BreakService.TYPE_MORNING_BREAK)) {
                // 요청사항: '예정' 제거 → 승인된 휴식은 즉시 '사용 완료'로 표기
                dto.morningBreak = 'Used';
            } else {
                dto.morningBreak = 'Available';
            }

            // Lunch
            if (userBreakMap.containsKey(userId) && 
                userBreakMap.get(userId).containsKey(BreakService.TYPE_LUNCH)) {
                dto.lunch = 'Used';
            } else {
                dto.lunch = 'Available';
            }

            // Afternoon Break
            if (userBreakMap.containsKey(userId) && 
                userBreakMap.get(userId).containsKey(BreakService.TYPE_AFTERNOON_BREAK)) {
                dto.afternoonBreak = 'Used';
            } else {
                dto.afternoonBreak = 'Available';
            }

            result.add(dto);
        }

        return result;
    }

    // 현재 시각 기준으로 "휴가중"인지 판정 (AM/PM 슬롯 반영)
    private static Boolean isLeaveActiveNow(Leave_Request__c lr, Date today, Time now, Time noon) {
        if (lr == null) return false;
        if (today == null || now == null || noon == null) return false;
        if (lr.Start_Date__c == null || lr.End_Date__c == null) return false;
        if (today < lr.Start_Date__c || today > lr.End_Date__c) return false;

        String startSlot = lr.Start_Slot__c;
        String endSlot = lr.End_Slot__c;

        // 시작일이 오늘이고 PM 시작이면, 정오 전에는 아직 근무중
        if (today == lr.Start_Date__c && startSlot == 'PM' && now < noon) {
            return false;
        }
        // 종료일이 오늘이고 AM 종료이면, 정오 이후에는 이미 복귀(근무중)
        if (today == lr.End_Date__c && endSlot == 'AM' && now >= noon) {
            return false;
        }
        return true;
    }

    /**
     * 관리자용: 팀원들의 휴식 신청 목록 조회 (롤백용)
     * 날짜 범위와 상태로 필터링 가능
     */
    @AuraEnabled(cacheable=false)
    public static List<BreakRequestDTO> getTeamBreakRequests(Date startDate, Date endDate, String statusFilter, String agentFilter) {
        Id currentUserId = UserInfo.getUserId();
        
        // 현재 사용자의 팀원 조회
        List<User> teamMembers = [
            SELECT Id, Name
            FROM User
            WHERE ManagerId = :currentUserId
              AND IsActive = true
        ];
        
        if (teamMembers.isEmpty()) {
            return new List<BreakRequestDTO>();
        }
        
        Set<Id> teamMemberIds = new Set<Id>();
        Map<Id, String> userIdToName = new Map<Id, String>();
        for (User u : teamMembers) {
            teamMemberIds.add(u.Id);
            userIdToName.put(u.Id, u.Name);
        }
        
        // 상담사 필터 적용
        if (agentFilter != null && agentFilter != 'All' && agentFilter != '') {
            Id agentId = agentFilter;
            if (teamMemberIds.contains(agentId)) {
                teamMemberIds.clear();
                teamMemberIds.add(agentId);
            }
        }
        
        // 날짜 범위 설정
        if (startDate == null) {
            startDate = Date.today().addDays(-7); // 기본: 최근 7일
        }
        if (endDate == null) {
            endDate = Date.today().addDays(7); // 기본: 향후 7일
        }
        
        // 휴식 신청 조회
        List<Break_Request__c> breaks;
        if (statusFilter != null && statusFilter != 'All' && statusFilter != '') {
            breaks = [
                SELECT Id, Name, Requester__c, Date__c, Break_Type__c, 
                       Start_Time__c, End_Time__c, Duration_Minutes__c, Status__c, Reason__c, CreatedDate
                FROM Break_Request__c
                WHERE Requester__c IN :teamMemberIds
                  AND Date__c >= :startDate
                  AND Date__c <= :endDate
                  AND Status__c = :statusFilter
                ORDER BY Date__c DESC, Start_Time__c DESC
            ];
        } else {
            breaks = [
                SELECT Id, Name, Requester__c, Date__c, Break_Type__c, 
                       Start_Time__c, End_Time__c, Duration_Minutes__c, Status__c, Reason__c, CreatedDate
                FROM Break_Request__c
                WHERE Requester__c IN :teamMemberIds
                  AND Date__c >= :startDate
                  AND Date__c <= :endDate
                ORDER BY Date__c DESC, Start_Time__c DESC
            ];
        }
        
        // DTO 변환
        List<BreakRequestDTO> result = new List<BreakRequestDTO>();
        for (Break_Request__c br : breaks) {
            BreakRequestDTO dto = new BreakRequestDTO();
            dto.id = br.Id;
            dto.name = br.Name;
            dto.requesterId = br.Requester__c;
            dto.requesterName = userIdToName.get(br.Requester__c);
            dto.dateValue = br.Date__c;
            dto.breakType = br.Break_Type__c;
            dto.startTime = br.Start_Time__c;
            dto.endTime = br.End_Time__c;
            dto.durationMinutes = br.Duration_Minutes__c;
            dto.status = br.Status__c;
            dto.reason = br.Reason__c;
            dto.createdDate = br.CreatedDate;
            result.add(dto);
        }
        
        return result;
    }

    public class BreakRequestDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String requesterId;
        @AuraEnabled public String requesterName;
        @AuraEnabled public Date dateValue;
        @AuraEnabled public String breakType;
        @AuraEnabled public Time startTime;
        @AuraEnabled public Time endTime;
        @AuraEnabled public Decimal durationMinutes;
        @AuraEnabled public String status;
        @AuraEnabled public String reason;
        @AuraEnabled public DateTime createdDate;
    }

    /**
     * 관리자용: 팀원들의 휴가 신청 목록 조회
     * 날짜 범위와 상태로 필터링 가능
     */
    @AuraEnabled(cacheable=false)
    public static List<LeaveRequestDTO> getTeamLeaveRequests(Date startDate, Date endDate, String statusFilter, String agentFilter) {
        Id currentUserId = UserInfo.getUserId();
        
        // 현재 사용자의 팀원 조회
        List<User> teamMembers = [
            SELECT Id, Name
            FROM User
            WHERE ManagerId = :currentUserId
              AND IsActive = true
        ];
        
        if (teamMembers.isEmpty()) {
            return new List<LeaveRequestDTO>();
        }
        
        Set<Id> teamMemberIds = new Set<Id>();
        Map<Id, String> userIdToName = new Map<Id, String>();
        for (User u : teamMembers) {
            teamMemberIds.add(u.Id);
            userIdToName.put(u.Id, u.Name);
        }
        
        // 상담사 필터 적용
        if (agentFilter != null && agentFilter != 'All' && agentFilter != '') {
            Id agentId = agentFilter;
            if (teamMemberIds.contains(agentId)) {
                teamMemberIds.clear();
                teamMemberIds.add(agentId);
            }
        }
        
        // 날짜 범위 설정
        if (startDate == null) {
            startDate = Date.today().addDays(-30); // 기본: 최근 30일
        }
        if (endDate == null) {
            endDate = Date.today().addDays(30); // 기본: 향후 30일
        }
        
        // 휴가 신청 조회
        List<Leave_Request__c> leaves;
        if (statusFilter != null && statusFilter != 'All' && statusFilter != '') {
            leaves = [
                SELECT Id, Name, Requester__c, Start_Date__c, End_Date__c, Start_Slot__c, End_Slot__c,
                       Days__c, Leave_Type__c, Status__c, Reason__c, CreatedDate
                FROM Leave_Request__c
                WHERE Requester__c IN :teamMemberIds
                  AND Start_Date__c <= :endDate
                  AND End_Date__c >= :startDate
                  AND Status__c = :statusFilter
                ORDER BY Start_Date__c DESC, CreatedDate DESC
            ];
        } else {
            leaves = [
                SELECT Id, Name, Requester__c, Start_Date__c, End_Date__c, Start_Slot__c, End_Slot__c,
                       Days__c, Leave_Type__c, Status__c, Reason__c, CreatedDate
                FROM Leave_Request__c
                WHERE Requester__c IN :teamMemberIds
                  AND Start_Date__c <= :endDate
                  AND End_Date__c >= :startDate
                ORDER BY Start_Date__c DESC, CreatedDate DESC
            ];
        }
        
        // DTO 변환
        List<LeaveRequestDTO> result = new List<LeaveRequestDTO>();
        for (Leave_Request__c lr : leaves) {
            LeaveRequestDTO dto = new LeaveRequestDTO();
            dto.id = lr.Id;
            dto.name = lr.Name;
            dto.requesterId = lr.Requester__c;
            dto.requesterName = userIdToName.get(lr.Requester__c);
            dto.startDate = lr.Start_Date__c;
            dto.endDate = lr.End_Date__c;
            dto.startSlot = lr.Start_Slot__c;
            dto.endSlot = lr.End_Slot__c;
            dto.days = lr.Days__c;
            dto.leaveType = lr.Leave_Type__c;
            dto.status = lr.Status__c;
            dto.reason = lr.Reason__c;
            dto.createdDate = lr.CreatedDate;
            result.add(dto);
        }
        
        return result;
    }

    public class LeaveRequestDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String requesterId;
        @AuraEnabled public String requesterName;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String startSlot;
        @AuraEnabled public String endSlot;
        @AuraEnabled public Decimal days;
        @AuraEnabled public String leaveType;
        @AuraEnabled public String status;
        @AuraEnabled public String reason;
        @AuraEnabled public DateTime createdDate;
    }

    /**
     * 관리자용: 팀원들의 근무 시간 목록 조회
     * 날짜 범위와 상담사로 필터링 가능
     */
    @AuraEnabled(cacheable=false)
    public static List<WorkTimeDTO> getTeamWorkTimes(Date startDate, Date endDate, String agentFilter, String statusFilter) {
        Id currentUserId = UserInfo.getUserId();
        
        // 현재 사용자의 팀원 조회
        List<User> teamMembers = [
            SELECT Id, Name
            FROM User
            WHERE ManagerId = :currentUserId
              AND IsActive = true
        ];
        
        Set<Id> teamMemberIds = new Set<Id>();
        Map<Id, String> userIdToName = new Map<Id, String>();
        
        // 현재 사용자(매니저) 자신도 포함
        User currentUser = [SELECT Id, Name FROM User WHERE Id = :currentUserId LIMIT 1];
        teamMemberIds.add(currentUser.Id);
        userIdToName.put(currentUser.Id, currentUser.Name);
        
        // 팀원 추가
        for (User u : teamMembers) {
            teamMemberIds.add(u.Id);
            userIdToName.put(u.Id, u.Name);
        }
        
        if (teamMemberIds.isEmpty()) {
            return new List<WorkTimeDTO>();
        }
        
        // 상담사 필터 적용
        if (agentFilter != null && agentFilter != 'All' && agentFilter != '') {
            Id agentId = agentFilter;
            if (teamMemberIds.contains(agentId)) {
                teamMemberIds.clear();
                teamMemberIds.add(agentId);
            }
        }
        
        // 날짜 범위 설정
        if (startDate == null) {
            startDate = Date.today().addDays(-30); // 기본: 최근 30일
        }
        if (endDate == null) {
            endDate = Date.today().addDays(30); // 기본: 향후 30일
        }
        
        // 근무 시간 조회
        List<Work_Time__c> workTimes;
        if (statusFilter != null && statusFilter != 'All' && statusFilter != '') {
            workTimes = [
                SELECT Id, Name, User__c, Work_Date__c, Work_Start_Time__c, Work_End_Time__c, Status__c, CreatedDate
                FROM Work_Time__c
                WHERE User__c IN :teamMemberIds
                  AND Work_Date__c >= :startDate
                  AND Work_Date__c <= :endDate
                  AND Status__c = :statusFilter
                ORDER BY Work_Date__c DESC, Work_Start_Time__c DESC
            ];
        } else {
            workTimes = [
                SELECT Id, Name, User__c, Work_Date__c, Work_Start_Time__c, Work_End_Time__c, Status__c, CreatedDate
                FROM Work_Time__c
                WHERE User__c IN :teamMemberIds
                  AND Work_Date__c >= :startDate
                  AND Work_Date__c <= :endDate
                ORDER BY Work_Date__c DESC, Work_Start_Time__c DESC
            ];
        }
        
        // DTO 변환
        List<WorkTimeDTO> result = new List<WorkTimeDTO>();
        for (Work_Time__c wt : workTimes) {
            WorkTimeDTO dto = new WorkTimeDTO();
            dto.id = wt.Id;
            dto.name = wt.Name;
            dto.userId = wt.User__c;
            dto.userName = userIdToName.get(wt.User__c);
            dto.workDate = wt.Work_Date__c;
            dto.workStartTime = wt.Work_Start_Time__c;
            dto.workEndTime = wt.Work_End_Time__c;
            dto.status = wt.Status__c;
            dto.createdDate = wt.CreatedDate;
            result.add(dto);
        }
        
        return result;
    }

    public class WorkTimeDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Date workDate;
        @AuraEnabled public Time workStartTime;
        @AuraEnabled public Time workEndTime;
        @AuraEnabled public String status;
        @AuraEnabled public DateTime createdDate;
    }
}