/**
 * ===========================================================================================
 * @description       : Trigger handler for Break_Request__c object (calendar sync, presence status updates)
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Calendar event sync and Omni-Channel presence status updates on break approval
 */
public without sharing class BreakRequestTriggerHandler {
    private static Boolean running = false;

    public static void handle(List<Break_Request__c> news, Map<Id, Break_Request__c> oldMap, System.TriggerOperation op) {
        if (running) return;
        running = true;
        try {
            if (op == System.TriggerOperation.BEFORE_INSERT || op == System.TriggerOperation.BEFORE_UPDATE) {
                beforeUpsert(news, op == System.TriggerOperation.BEFORE_INSERT, oldMap);
            } else if (op == System.TriggerOperation.AFTER_INSERT || op == System.TriggerOperation.AFTER_UPDATE) {
                afterUpsert(news, oldMap);
            } else if (op == System.TriggerOperation.AFTER_DELETE) {
                afterDelete(news);
            }
        } finally {
            running = false;
        }
    }

    private static void beforeUpsert(List<Break_Request__c> news, Boolean isInsert, Map<Id, Break_Request__c> oldMap) {
        Id me = UserInfo.getUserId();
        for (Break_Request__c r : (news == null ? new List<Break_Request__c>() : news)) {
            // 기본값 설정
            if (isInsert) {
                if (r.Requester__c == null) r.Requester__c = me;
                if (r.Status__c == null) r.Status__c = 'Draft';
            }

            // Duration 계산
            if (r.Start_Time__c != null && r.End_Time__c != null) {
                r.Duration_Minutes__c = BreakService.calculateDuration(r.Start_Time__c, r.End_Time__c);
            }
        }
    }

    private static void afterUpsert(List<Break_Request__c> news, Map<Id, Break_Request__c> oldMap) {
        syncCalendarEvents(news, oldMap);
        // Note: Presence Status 변경은 LWC에서 CustomEvent를 통해 처리됩니다.
        // Apex에서 직접 변경하는 것은 작동하지 않으므로 제거했습니다.
    }

    private static void afterDelete(List<Break_Request__c> deleted) {
        // Event 삭제
        if (deleted == null || deleted.isEmpty()) {
            return;  // 삭제할 레코드가 없으면 조기 반환
        }
        
        Set<Id> eventIds = new Set<Id>();
        for (Break_Request__c r : deleted) {
            if (r != null && String.isNotBlank(r.CalendarEventId__c)) {
                eventIds.add(r.CalendarEventId__c);
            }
        }
        if (!eventIds.isEmpty()) {
            try {
                List<Event> toDelete = [SELECT Id FROM Event WHERE Id IN :eventIds];
                if (!toDelete.isEmpty()) {
                    delete toDelete;
                }
            } catch (Exception e) {
                // Event 삭제 실패 시 조용히 진행 (Event가 없을 수 있음)
                System.debug('Event deletion failed: ' + e.getMessage());
            }
        }
    }

    /**
     * 캘린더 Event 동기화
     * - Approved: Event 생성
     * - Cancelled/Deleted: Event 삭제
     */
    private static void syncCalendarEvents(List<Break_Request__c> news, Map<Id, Break_Request__c> oldMap) {
        List<Event> toInsert = new List<Event>();
        List<Event> toDelete = new List<Event>();
        List<Break_Request__c> toUpdate = new List<Break_Request__c>();
        Set<Id> needCreateEvent = new Set<Id>();
        Set<Id> needDeleteEvent = new Set<Id>();

        for (Break_Request__c r : news) {
            Break_Request__c old = (oldMap != null) ? oldMap.get(r.Id) : null;
            Boolean statusChanged = (old == null || old.Status__c != r.Status__c);
            Boolean isNewApproved = (r.Status__c == 'Approved' && (old == null || old.Status__c != 'Approved'));
            Boolean isNewCancelled = (r.Status__c == 'Cancelled' && (old == null || old.Status__c != 'Cancelled'));

            // Approved 전환 시 Event 생성
            if (isNewApproved) {
                needCreateEvent.add(r.Id);
            }

            // Cancelled 전환 시 Event 삭제
            if (isNewCancelled && String.isNotBlank(r.CalendarEventId__c)) {
                needDeleteEvent.add(r.Id);
            }
        }

        // 1) Event 삭제 (Cancelled 전환 시)
        if (!needDeleteEvent.isEmpty()) {
            List<Break_Request__c> reqs = [
                SELECT Id, CalendarEventId__c
                FROM Break_Request__c
                WHERE Id IN :needDeleteEvent
            ];
            Set<Id> eventIds = new Set<Id>();
            for (Break_Request__c r : reqs) {
                if (String.isNotBlank(r.CalendarEventId__c)) {
                    eventIds.add(r.CalendarEventId__c);
                }
            }
            if (!eventIds.isEmpty()) {
                toDelete = [SELECT Id FROM Event WHERE Id IN :eventIds];
            }
        }

        if (!toDelete.isEmpty()) {
            delete toDelete;
            // CalendarEventId__c 초기화
            for (Id rid : needDeleteEvent) {
                Break_Request__c upd = new Break_Request__c(Id = rid);
                upd.CalendarEventId__c = null;
                toUpdate.add(upd);
            }
        }

        // 2) Event 생성 (Approved 전환 시)
        if (!needCreateEvent.isEmpty()) {
            List<Break_Request__c> reqs = [
                SELECT Id, Name, Requester__c, Date__c, Break_Type__c, Start_Time__c, End_Time__c, Duration_Minutes__c
                FROM Break_Request__c
                WHERE Id IN :needCreateEvent
            ];
            
            Map<Id, Event> reqToEvent = new Map<Id, Event>();
            for (Break_Request__c r : reqs) {
                Event ev = new Event();
                ev.OwnerId = r.Requester__c;
                ev.WhatId = r.Id;
                
                // 제목: "Morning Break (10분)" 형식
                String typeLabel = r.Break_Type__c;
                String durationLabel = (r.Duration_Minutes__c != null) ? 
                    String.valueOf(r.Duration_Minutes__c) + '분' : '';
                ev.Subject = typeLabel + (String.isNotBlank(durationLabel) ? ' (' + durationLabel + ')' : '');
                
                // DateTime 설정 (Date + Time)
                if (r.Date__c != null && r.Start_Time__c != null) {
                    ev.StartDateTime = DateTime.newInstance(r.Date__c, r.Start_Time__c);
                }
                if (r.Date__c != null && r.End_Time__c != null) {
                    ev.EndDateTime = DateTime.newInstance(r.Date__c, r.End_Time__c);
                }
                
                ev.IsAllDayEvent = false;
                toInsert.add(ev);
                reqToEvent.put(r.Id, ev);
            }

            if (!toInsert.isEmpty()) {
                insert toInsert;
                // Event Id를 CalendarEventId__c에 저장
                for (Break_Request__c r : reqs) {
                    Event ev = reqToEvent.get(r.Id);
                    if (ev != null && ev.Id != null) {
                        Break_Request__c upd = new Break_Request__c(Id = r.Id);
                        upd.CalendarEventId__c = ev.Id;
                        toUpdate.add(upd);
                    }
                }
            }
        }

        // CalendarEventId__c 업데이트
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}