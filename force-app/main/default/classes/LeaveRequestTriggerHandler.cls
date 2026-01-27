/**
 * ===========================================================================================
 * @description       : Trigger handler for Leave_Request__c object (calendar sync, approver sharing, approval process cancellation)
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Calendar event sync, approver sharing, and approval process auto-cancellation on leave cancellation
 */
public without sharing class LeaveRequestTriggerHandler {
    private static Boolean running = false;

    public static void beforeUpsert(List<Leave_Request__c> news, Boolean isInsert, Map<Id, Leave_Request__c> oldMap) {
        if (running) return;
        running = true;
        try {
            Id me = UserInfo.getUserId();
            for (Leave_Request__c r : (news == null ? new List<Leave_Request__c>() : news)) {
                // default requester/status
                if (isInsert) {
                    if (r.Requester__c == null) r.Requester__c = me;
                    if (r.Status__c == null) r.Status__c = 'Draft';
                }

                // Cancelled 상태에서 Approved로 변경되는 것을 막기 (Approval Process 우회 방지)
                if (!isInsert && oldMap != null) {
                    Leave_Request__c oldR = oldMap.get(r.Id);
                    if (oldR != null && oldR.Status__c == 'Cancelled' && r.Status__c == 'Approved') {
                        r.addError('Cancelled 상태의 휴가 신청은 승인할 수 없습니다.');
                        continue; // 이 레코드의 나머지 처리 건너뛰기
                    }
                }

                // compute Days when key fields exist
                if (r.Start_Date__c != null && r.End_Date__c != null && r.Start_Slot__c != null && r.End_Slot__c != null) {
                    LeaveService.Range range = new LeaveService.Range(
                        r.Start_Date__c,
                        LeaveService.parseSlot(r.Start_Slot__c),
                        r.End_Date__c,
                        LeaveService.parseSlot(r.End_Slot__c)
                    );
                    r.Days__c = LeaveService.calculateBusinessDays(range);
                }

                // Approver default when entering Submitted/CancelSubmitted/Approved (needed for sharing)
                Leave_Request__c oldR = (oldMap == null) ? null : oldMap.get(r.Id);
                String oldStatus = oldR == null ? null : oldR.Status__c;
                String newStatus = r.Status__c;
                Boolean enteringActionable =
                    (newStatus == 'Submitted' && oldStatus != 'Submitted') ||
                    (newStatus == 'CancelSubmitted' && oldStatus != 'CancelSubmitted') ||
                    (newStatus == 'Approved' && oldStatus != 'Approved');
                if (enteringActionable && r.Approver__c == null && r.Requester__c != null) {
                    User u = [SELECT Id, ManagerId FROM User WHERE Id = :r.Requester__c LIMIT 1];
                    if (u.ManagerId != null) r.Approver__c = u.ManagerId;
                }
            }
        } finally {
            running = false;
        }
    }

    public static void afterUpsert(List<Leave_Request__c> news, Boolean isInsert, Map<Id, Leave_Request__c> oldMap) {
        if (running) return;
        running = true;
        try {
            if (news == null || news.isEmpty()) return;

            // 1) Cancelled 상태로 변경 시 진행 중인 Approval Process 자동 취소
            cancelPendingApprovalProcesses(news, oldMap);

            // 2) manager read-only sharing (Approver)
            syncApproverSharing(news, oldMap);

            // 3) calendar event sync by status transitions
            syncCalendarEvents(news, oldMap);

            // 4) Custom Notification to requester (Approved/Cancelled)
            sendNotificationsToRequester(news, oldMap);
        } finally {
            running = false;
        }
    }

    public static void afterDelete(List<Leave_Request__c> olds) {
        if (running) return;
        running = true;
        try {
            if (olds == null || olds.isEmpty()) return;
            // best-effort: delete linked events
            Set<Id> eventIds = new Set<Id>();
            for (Leave_Request__c r : olds) {
                if (String.isBlank(r.CalendarEventId__c)) continue;
                try {
                    eventIds.add((Id) r.CalendarEventId__c);
                } catch (Exception e) {
                    // ignore
                }
            }
            if (!eventIds.isEmpty()) {
                List<Event> evs = [SELECT Id FROM Event WHERE Id IN :eventIds];
                if (!evs.isEmpty()) delete evs;
            }
        } finally {
            running = false;
        }
    }

    private static void syncApproverSharing(List<Leave_Request__c> news, Map<Id, Leave_Request__c> oldMap) {
        // OWD Private 전제: Approver에게 Read 공유
        List<Leave_Request__Share> toUpsert = new List<Leave_Request__Share>();
        List<Leave_Request__Share> toDelete = new List<Leave_Request__Share>();

        Set<Id> changed = new Set<Id>();
        for (Leave_Request__c r : news) {
            Leave_Request__c oldR = oldMap == null ? null : oldMap.get(r.Id);
            Id oldApprover = oldR == null ? null : oldR.Approver__c;
            if (oldR == null || oldApprover != r.Approver__c) changed.add(r.Id);
        }
        if (changed.isEmpty()) return;

        Map<Id, Leave_Request__Share> existing = new Map<Id, Leave_Request__Share>();
        for (Leave_Request__Share s : [
            SELECT Id, ParentId, UserOrGroupId, AccessLevel, RowCause
            FROM Leave_Request__Share
            WHERE ParentId IN :changed
              AND RowCause = 'Manual'
        ]) {
            existing.put(s.ParentId, s);
        }

        for (Leave_Request__c r : news) {
            if (!changed.contains(r.Id)) continue;
            Leave_Request__Share ex = existing.get(r.Id);
            if (ex != null && (r.Approver__c == null || ex.UserOrGroupId != r.Approver__c)) {
                toDelete.add(ex);
            }
            if (r.Approver__c != null) {
                Leave_Request__Share ns = new Leave_Request__Share();
                ns.ParentId = r.Id;
                ns.UserOrGroupId = r.Approver__c;
                ns.AccessLevel = 'Read';
                ns.RowCause = Schema.Leave_Request__Share.RowCause.Manual;
                toUpsert.add(ns);
            }
        }

        if (!toDelete.isEmpty()) delete toDelete;
        if (!toUpsert.isEmpty()) upsert toUpsert;
    }

    private static void syncCalendarEvents(List<Leave_Request__c> news, Map<Id, Leave_Request__c> oldMap) {
        // Approved -> Event 생성 (WhatId로 Leave_Request__c 연결 + CalendarEventId__c 저장)
        // CancelSubmitted -> Event 삭제(숨김) - 즉시 실행
        // CancelRejected(= Approved로 복귀) -> Event 재생성
        // Cancelled -> Event 없음 유지

        List<Event> toInsert = new List<Event>();
        List<Event> toDelete = new List<Event>();
        List<Leave_Request__c> toUpdate = new List<Leave_Request__c>();

        Set<Id> needDeleteEvent = new Set<Id>();
        Set<Id> needCreateEvent = new Set<Id>();
        Map<Id, Leave_Request__c> byId = new Map<Id, Leave_Request__c>(news);

        // 상태 전환 감지
        for (Leave_Request__c r : news) {
            Leave_Request__c oldR = oldMap == null ? null : oldMap.get(r.Id);
            String oldStatus = oldR == null ? null : oldR.Status__c;
            String newStatus = r.Status__c;

            if (newStatus == 'Approved' && oldStatus != 'Approved') {
                // create event if not exists
                if (String.isBlank(r.CalendarEventId__c)) needCreateEvent.add(r.Id);
            }

            if (newStatus == 'CancelSubmitted' && oldStatus != 'CancelSubmitted') {
                // hide immediately by deleting event
                needDeleteEvent.add(r.Id);
            }

            if (newStatus == 'Approved' && oldStatus == 'CancelSubmitted') {
                // cancel rejected -> recreate event
                needCreateEvent.add(r.Id);
            }

            if (newStatus == 'Cancelled' && oldStatus != 'Cancelled') {
                // ensure event removed
                needDeleteEvent.add(r.Id);
            }
        }

        // 1) Event 삭제 (CancelSubmitted/Cancelled 상태 전환 시 즉시 숨김)
        if (!needDeleteEvent.isEmpty()) {
            Set<Id> eventIdsByField = new Set<Id>();
            Set<Id> requestIdsForWhatId = new Set<Id>();

            for (Id rid : needDeleteEvent) {
                Leave_Request__c r = byId.get(rid);
                if (r == null) continue;
                
                // CalendarEventId__c가 있으면 우선 사용
                if (!String.isBlank(r.CalendarEventId__c)) {
                    try {
                        eventIdsByField.add((Id) r.CalendarEventId__c);
                    } catch (Exception e) {
                        // invalid id format, fallback to WhatId lookup
                        requestIdsForWhatId.add(rid);
                    }
                } else {
                    // CalendarEventId__c가 없으면 WhatId로 조회 (안전장치)
                    requestIdsForWhatId.add(rid);
                }
            }

            // CalendarEventId__c로 조회
            if (!eventIdsByField.isEmpty()) {
                for (Event e : [SELECT Id FROM Event WHERE Id IN :eventIdsByField]) {
                    toDelete.add(e);
                }
            }

            // WhatId로 조회 (CalendarEventId__c가 없거나 유효하지 않은 경우)
            if (!requestIdsForWhatId.isEmpty()) {
                for (Event e : [SELECT Id FROM Event WHERE WhatId IN :requestIdsForWhatId]) {
                    toDelete.add(e);
                }
            }
        }

        // 삭제 실행 (취소요청 시 즉시 숨김)
        if (!toDelete.isEmpty()) {
            delete toDelete;
            // CalendarEventId__c 초기화
            for (Id rid : needDeleteEvent) {
                Leave_Request__c upd = new Leave_Request__c(Id = rid);
                upd.CalendarEventId__c = null;
                toUpdate.add(upd);
            }
        }

        // 2) Event 생성 (Approved 상태 전환 시, 또는 CancelRejected 후 재생성)
        if (!needCreateEvent.isEmpty()) {
            List<Leave_Request__c> reqs = [
                SELECT Id, Name, Requester__c, Leave_Type__c, Start_Date__c, End_Date__c, Start_Slot__c, End_Slot__c, Days__c
                FROM Leave_Request__c
                WHERE Id IN :needCreateEvent
            ];
            
            Map<Id, Event> reqToEvent = new Map<Id, Event>();
            for (Leave_Request__c r : reqs) {
                Event ev = new Event();
                ev.OwnerId = r.Requester__c;
                ev.WhatId = r.Id; // Leave_Request__c와 확실히 연결
                ev.Subject = 'Leave (' + (r.Leave_Type__c != null ? r.Leave_Type__c : '') + ') ' + 
                            r.Start_Date__c.format() + ' ' + r.Start_Slot__c + ' ~ ' + 
                            r.End_Date__c.format() + ' ' + r.End_Slot__c;
                // 표준 캘린더 "종일" 이벤트로 표현 (AM/PM은 제목으로 표시)
                ev.IsAllDayEvent = true;
                ev.ActivityDate = r.Start_Date__c;
                // 다일 휴가는 시작일~종료일을 하나의 Event로 표현 (표준 캘린더 AllDayEvent는 단일 날짜만 지원)
                // 2차에서 여러 Event 생성으로 개선 가능
                toInsert.add(ev);
                reqToEvent.put(r.Id, ev);
            }

            if (!toInsert.isEmpty()) {
                insert toInsert;
                // Event Id를 CalendarEventId__c에 저장 (삭제 시 확실히 찾기 위해)
                for (Leave_Request__c r : reqs) {
                    Event ev = reqToEvent.get(r.Id);
                    if (ev != null && ev.Id != null) {
                        Leave_Request__c upd = new Leave_Request__c(Id = r.Id);
                        upd.CalendarEventId__c = ev.Id;
                        toUpdate.add(upd);
                    }
                }
            }
        }

        // CalendarEventId__c 업데이트 (삭제 후 null 처리 + 생성 후 Id 저장)
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * Cancelled 상태로 변경 시 진행 중인 Approval Process 자동 취소
     * 승인 프로세스가 진행 중인 상태에서 사용자가 취소하면 Approval Process도 함께 취소
     */
    private static void cancelPendingApprovalProcesses(List<Leave_Request__c> news, Map<Id, Leave_Request__c> oldMap) {
        Set<Id> toCancel = new Set<Id>();
        
        // Cancelled 상태로 변경된 레코드 찾기
        for (Leave_Request__c r : news) {
            Leave_Request__c oldR = oldMap == null ? null : oldMap.get(r.Id);
            if (oldR == null) continue; // 새로 생성된 레코드는 제외
            
            String oldStatus = oldR.Status__c;
            String newStatus = r.Status__c;
            
            // Submitted 또는 CancelSubmitted 상태에서 Cancelled로 변경된 경우
            if ((oldStatus == 'Submitted' || oldStatus == 'CancelSubmitted') && newStatus == 'Cancelled') {
                toCancel.add(r.Id);
            }
        }
        
        if (toCancel.isEmpty()) return;
        
        // 진행 중인 Approval Process WorkItem 조회
        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id, ProcessInstanceId, ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId IN :toCancel
              AND ProcessInstance.Status = 'Pending'
        ];
        
        if (workItems.isEmpty()) return;
        
        // Approval Process 취소 (Recall) - 각 WorkItem을 개별적으로 처리
        for (ProcessInstanceWorkitem wi : workItems) {
            try {
                Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
                req.setAction('Removed'); // Recall action - Approval Process를 취소
                req.setWorkitemId(wi.Id);
                req.setComments('Leave request was cancelled. Approval process automatically recalled.');
                
                Approval.ProcessResult result = Approval.process(req);
                
                // 결과 로깅 (실패해도 치명적이지 않음)
                if (!result.isSuccess() && !result.getErrors().isEmpty()) {
                    System.debug('Failed to recall approval process for ' + wi.ProcessInstance.TargetObjectId + ': ' + result.getErrors()[0].getMessage());
                } else {
                    System.debug('Successfully recalled approval process for ' + wi.ProcessInstance.TargetObjectId);
                }
            } catch (Exception e) {
                // Approval Process 취소 실패는 치명적이지 않으므로 로깅만 수행
                System.debug('Error recalling approval process for ' + wi.ProcessInstance.TargetObjectId + ': ' + e.getMessage());
            }
        }
    }

    /**
     * 휴가 승인/취소 승인 시 요청자에게 Custom Notification 전송
     * - 최종 승인 (Approved): 요청자에게 승인 알림
     * - 최종 취소 승인 (Cancelled from CancelSubmitted): 요청자에게 취소 승인 알림
     */
    private static void sendNotificationsToRequester(List<Leave_Request__c> news, Map<Id, Leave_Request__c> oldMap) {
        // Custom Notification Type ID 조회
        List<CustomNotificationType> notificationTypes = [
            SELECT Id, DeveloperName
            FROM CustomNotificationType
            WHERE DeveloperName = 'Leave_Request_Alerts'
            LIMIT 1
        ];
        
        if (notificationTypes.isEmpty()) {
            System.debug('Custom Notification Type "Leave_Request_Alerts" not found. Skipping notifications.');
            return;
        }
        
        Id notificationTypeId = notificationTypes[0].Id;
        List<Messaging.CustomNotification> notifications = new List<Messaging.CustomNotification>();
        
        // 상태 전환 감지 및 알림 생성
        for (Leave_Request__c r : news) {
            Leave_Request__c oldR = oldMap == null ? null : oldMap.get(r.Id);
            if (oldR == null) continue; // 새로 생성된 레코드는 제외
            
            String oldStatus = oldR.Status__c;
            String newStatus = r.Status__c;
            
            // 최종 승인: Submitted -> Approved
            if (oldStatus == 'Submitted' && newStatus == 'Approved' && r.Requester__c != null) {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle('휴가 승인 완료');
                notification.setBody('휴가 신청이 승인되었습니다. ' + 
                    (r.Start_Date__c != null ? r.Start_Date__c.format() : '') + 
                    (r.Start_Slot__c != null ? ' ' + r.Start_Slot__c : '') + 
                    ' ~ ' + 
                    (r.End_Date__c != null ? r.End_Date__c.format() : '') + 
                    (r.End_Slot__c != null ? ' ' + r.End_Slot__c : ''));
                notification.setNotificationTypeId(notificationTypeId);
                notification.setTargetId(r.Id); // Leave_Request__c 레코드로 이동
                
                try {
                    notification.send(new Set<String>{ r.Requester__c });
                    System.debug('Approval notification sent to requester: ' + r.Requester__c);
                } catch (Exception e) {
                    System.debug('Failed to send approval notification: ' + e.getMessage());
                }
            }
            
            // 최종 취소 승인: CancelSubmitted -> Cancelled
            if (oldStatus == 'CancelSubmitted' && newStatus == 'Cancelled' && r.Requester__c != null) {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle('휴가 취소 승인 완료');
                notification.setBody('휴가 취소 요청이 승인되었습니다. ' + 
                    (r.Start_Date__c != null ? r.Start_Date__c.format() : '') + 
                    (r.Start_Slot__c != null ? ' ' + r.Start_Slot__c : '') + 
                    ' ~ ' + 
                    (r.End_Date__c != null ? r.End_Date__c.format() : '') + 
                    (r.End_Slot__c != null ? ' ' + r.End_Slot__c : ''));
                notification.setNotificationTypeId(notificationTypeId);
                notification.setTargetId(r.Id); // Leave_Request__c 레코드로 이동
                
                try {
                    notification.send(new Set<String>{ r.Requester__c });
                    System.debug('Cancellation approval notification sent to requester: ' + r.Requester__c);
                } catch (Exception e) {
                    System.debug('Failed to send cancellation approval notification: ' + e.getMessage());
                }
            }
        }
    }
}