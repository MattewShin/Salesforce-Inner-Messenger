/**
 * ===========================================================================================
 * @description       : Service class for Leave Request business logic (business days calculation, conflict validation)
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Business days calculation (excluding weekends), slot parsing, and overlap validation
 */
public with sharing class LeaveService {
    public class LeaveValidationException extends Exception {}

    // String 상수로 Slot 정의
    public static final String SLOT_AM = 'AM';
    public static final String SLOT_PM = 'PM';

    public class Range {
        public Date startDate;
        public String startSlot;
        public Date endDate;
        public String endSlot;
        public Range(Date sd, String ss, Date ed, String es) {
            startDate = sd; startSlot = ss; endDate = ed; endSlot = es;
        }
    }

    public static String parseSlot(String s) {
        String v = (s == null) ? '' : s.trim();
        if (v == SLOT_AM || v.equalsIgnoreCase(SLOT_AM)) {
            return SLOT_AM;
        }
        if (v == SLOT_PM || v.equalsIgnoreCase(SLOT_PM)) {
            return SLOT_PM;
        }
        throw new LeaveValidationException('Invalid slot: ' + s);
    }

    public static Integer halfIndex(Date d, String slot) {
        Date anchor = Date.newInstance(2000, 1, 1);
        Integer days = anchor.daysBetween(d);
        Boolean isPM = (slot != null && slot == SLOT_PM);
        return (days * 2) + (isPM ? 1 : 0);
    }

    public static Boolean isWeekend(Date d) {
        Integer dow = Integer.valueOf(DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0)).format('u'));
        return dow == 6 || dow == 7;
    }

    public static Decimal calculateBusinessDays(Range r) {
        validateRange(r);
        Integer halves = 0;
        Date cur = r.startDate;
        while (cur <= r.endDate) {
            if (!isWeekend(cur)) {
                if (cur == r.startDate && cur == r.endDate) {
                    if (r.startSlot == SLOT_AM && r.endSlot == SLOT_AM) halves += 1;
                    else if (r.startSlot == SLOT_PM && r.endSlot == SLOT_PM) halves += 1;
                    else if (r.startSlot == SLOT_AM && r.endSlot == SLOT_PM) halves += 2;
                } else if (cur == r.startDate) {
                    Boolean startIsPM = (r.startSlot == SLOT_PM);
                    halves += startIsPM ? 1 : 2;
                } else if (cur == r.endDate) {
                    Boolean endIsAM = (r.endSlot == SLOT_AM);
                    halves += endIsAM ? 1 : 2;
                } else {
                    halves += 2;
                }
            }
            cur = cur.addDays(1);
        }
        return Decimal.valueOf(halves) / 2;
    }

    public static void validateRange(Range r) {
        if (r == null) throw new LeaveValidationException('Range is required.');
        if (r.startDate == null || r.endDate == null) throw new LeaveValidationException('Start/End date is required.');
        if (r.startSlot == null || r.endSlot == null) throw new LeaveValidationException('Start/End slot is required.');
        if (r.startDate > r.endDate) throw new LeaveValidationException('Start date must be <= end date.');
        Boolean sameDayPMtoAM = (r.startDate == r.endDate && 
                                  r.startSlot == SLOT_PM && 
                                  r.endSlot == SLOT_AM);
        if (sameDayPMtoAM) {
            throw new LeaveValidationException('Same-day PM to AM is not allowed.');
        }
    }

    public static Boolean overlaps(Range a, Range b) {
        validateRange(a);
        validateRange(b);
        Integer aStart = halfIndex(a.startDate, a.startSlot);
        Integer aEnd = halfIndex(a.endDate, a.endSlot);
        Integer bStart = halfIndex(b.startDate, b.startSlot);
        Integer bEnd = halfIndex(b.endDate, b.endSlot);
        return aStart <= bEnd && bStart <= aEnd;
    }

    public static void validateNoConflict(Leave_Request__c req) {
        if (req == null) return;
        if (req.Requester__c == null) throw new LeaveValidationException('Requester is required.');
        Range r = new Range(req.Start_Date__c, parseSlot(req.Start_Slot__c), req.End_Date__c, parseSlot(req.End_Slot__c));
        validateRange(r);

        Set<String> activeStatuses = new Set<String>{ 'Submitted', 'Approved', 'CancelSubmitted' };
        List<Leave_Request__c> others = [
            SELECT Id, Name, Start_Date__c, Start_Slot__c, End_Date__c, End_Slot__c, Status__c
            FROM Leave_Request__c
            WHERE Requester__c = :req.Requester__c
              AND Status__c IN :activeStatuses
              AND Id != :req.Id
        ];
        for (Leave_Request__c o : others) {
            Range orr = new Range(o.Start_Date__c, parseSlot(o.Start_Slot__c), o.End_Date__c, parseSlot(o.End_Slot__c));
            if (overlaps(r, orr)) {
                String conflictPeriod = o.Start_Date__c.format() + ' ' + o.Start_Slot__c + ' ~ ' + o.End_Date__c.format() + ' ' + o.End_Slot__c;
                String conflictStatus = o.Status__c;
                throw new LeaveValidationException(
                    '이미 ' + conflictPeriod + ' 기간의 휴가 요청(' + (String.isNotBlank(o.Name) ? o.Name : o.Id) + 
                    ', 상태: ' + conflictStatus + ')이 존재합니다. 기간이 겹치지 않도록 수정해주세요.'
                );
            }
        }
    }
}