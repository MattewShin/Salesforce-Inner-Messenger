/**
 * ===========================================================================================
 * @description       : Test class for LeaveService
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Test coverage for LeaveService methods (business days calculation, conflict validation)
 */
@IsTest
private class LeaveService_Test {
    @TestSetup
    static void setup() {
        Profile p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];
        User u1 = new User(
            ProfileId = p.Id,
            Username = 'leave.test.u1+' + String.valueOf(DateTime.now().getTime()) + '@example.com',
            Email = 'leave.test.u1+' + String.valueOf(DateTime.now().getTime()) + '@example.com',
            LastName = 'LeaveTestU1',
            Alias = 'ltu1',
            TimeZoneSidKey = 'Asia/Seoul',
            LocaleSidKey = 'ko_KR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'ko'
        );
        insert u1;
    }

    private static User u1() {
        return [SELECT Id FROM User WHERE LastName = 'LeaveTestU1' LIMIT 1];
    }

    @IsTest
    static void test_parseSlot() {
        Test.startTest();
        String am = LeaveService.parseSlot('AM');
        String pm = LeaveService.parseSlot('PM');
        Test.stopTest();

        System.assertEquals(LeaveService.SLOT_AM, am, 'AM 파싱');
        System.assertEquals(LeaveService.SLOT_PM, pm, 'PM 파싱');

        Boolean threw = false;
        try {
            LeaveService.parseSlot('INVALID');
        } catch (LeaveService.LeaveValidationException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Invalid slot 예외');
    }

    @IsTest
    static void test_isWeekend() {
        Date mon = Date.newInstance(2026, 1, 5); // 월요일
        Date sat = Date.newInstance(2026, 1, 10); // 토요일
        Date sun = Date.newInstance(2026, 1, 11); // 일요일

        Test.startTest();
        Boolean monIsWeekend = LeaveService.isWeekend(mon);
        Boolean satIsWeekend = LeaveService.isWeekend(sat);
        Boolean sunIsWeekend = LeaveService.isWeekend(sun);
        Test.stopTest();

        System.assertEquals(false, monIsWeekend, '월요일은 평일');
        System.assertEquals(true, satIsWeekend, '토요일은 주말');
        System.assertEquals(true, sunIsWeekend, '일요일은 주말');
    }

    @IsTest
    static void test_validateRange() {
        Date d1 = Date.newInstance(2026, 1, 5);
        Date d2 = Date.newInstance(2026, 1, 7);

        // 정상 케이스
        LeaveService.Range r1 = new LeaveService.Range(d1, LeaveService.SLOT_AM, d2, LeaveService.SLOT_PM);
        Test.startTest();
        LeaveService.validateRange(r1);
        Test.stopTest();

        // null 체크
        Boolean threw = false;
        try {
            LeaveService.validateRange(null);
        } catch (LeaveService.LeaveValidationException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'null Range 예외');

        // 날짜 역전
        threw = false;
        try {
            LeaveService.Range r2 = new LeaveService.Range(d2, LeaveService.SLOT_AM, d1, LeaveService.SLOT_PM);
            LeaveService.validateRange(r2);
        } catch (LeaveService.LeaveValidationException e) {
            threw = true;
        }
        System.assertEquals(true, threw, '날짜 역전 예외');

        // 같은 날 PM -> AM (불가)
        threw = false;
        try {
            LeaveService.Range r3 = new LeaveService.Range(d1, LeaveService.SLOT_PM, d1, LeaveService.SLOT_AM);
            LeaveService.validateRange(r3);
        } catch (LeaveService.LeaveValidationException e) {
            threw = true;
        }
        System.assertEquals(true, threw, '같은 날 PM->AM 예외');
    }

    @IsTest
    static void test_calculateBusinessDays_singleDay() {
        Date d = Date.newInstance(2026, 1, 5); // 월요일

        Test.startTest();
        Decimal amAm = LeaveService.calculateBusinessDays(new LeaveService.Range(d, LeaveService.SLOT_AM, d, LeaveService.SLOT_AM));
        Decimal pmPm = LeaveService.calculateBusinessDays(new LeaveService.Range(d, LeaveService.SLOT_PM, d, LeaveService.SLOT_PM));
        Decimal amPm = LeaveService.calculateBusinessDays(new LeaveService.Range(d, LeaveService.SLOT_AM, d, LeaveService.SLOT_PM));
        Test.stopTest();

        System.assertEquals(0.5, amAm, 'AM-AM = 0.5일');
        System.assertEquals(0.5, pmPm, 'PM-PM = 0.5일');
        System.assertEquals(1.0, amPm, 'AM-PM = 1.0일');
    }

    @IsTest
    static void test_calculateBusinessDays_multiDay() {
        Date start = Date.newInstance(2026, 1, 5); // 월요일
        Date endDate = Date.newInstance(2026, 1, 7); // 수요일

        Test.startTest();
        Decimal amPm = LeaveService.calculateBusinessDays(new LeaveService.Range(start, LeaveService.SLOT_AM, endDate, LeaveService.SLOT_PM));
        Decimal pmAm = LeaveService.calculateBusinessDays(new LeaveService.Range(start, LeaveService.SLOT_PM, endDate, LeaveService.SLOT_AM));
        Test.stopTest();

        // 월(AM~PM) + 화(AM~PM) + 수(AM~PM) = 3일
        System.assertEquals(3.0, amPm, '월AM~수PM = 3일');
        // 월(PM) + 화(AM~PM) + 수(AM) = 2.0일
        System.assertEquals(2.0, pmAm, '월PM~수AM = 2.0일');
    }

    @IsTest
    static void test_calculateBusinessDays_weekendExcluded() {
        Date fri = Date.newInstance(2026, 1, 9); // 금요일
        Date mon = Date.newInstance(2026, 1, 12); // 월요일

        Test.startTest();
        Decimal days = LeaveService.calculateBusinessDays(new LeaveService.Range(fri, LeaveService.SLOT_AM, mon, LeaveService.SLOT_PM));
        Test.stopTest();

        // 금(AM~PM) + 토(제외) + 일(제외) + 월(AM~PM) = 2일
        System.assertEquals(2.0, days, '주말 제외 계산');
    }

    @IsTest
    static void test_overlaps() {
        Date d1 = Date.newInstance(2026, 1, 5);
        Date d2 = Date.newInstance(2026, 1, 7);
        Date d3 = Date.newInstance(2026, 1, 8);

        LeaveService.Range r1 = new LeaveService.Range(d1, LeaveService.SLOT_AM, d2, LeaveService.SLOT_PM);
        LeaveService.Range r2 = new LeaveService.Range(d2, LeaveService.SLOT_AM, d3, LeaveService.SLOT_PM);
        LeaveService.Range r3 = new LeaveService.Range(d3, LeaveService.SLOT_AM, Date.newInstance(2026, 1, 10), LeaveService.SLOT_PM);

        Test.startTest();
        Boolean overlap1 = LeaveService.overlaps(r1, r2); // 겹침 (d2 공통)
        Boolean overlap2 = LeaveService.overlaps(r1, r3); // 안 겹침
        Test.stopTest();

        System.assertEquals(true, overlap1, '겹치는 범위');
        System.assertEquals(false, overlap2, '안 겹치는 범위');
    }

    @IsTest
    static void test_validateNoConflict() {
        User u = u1();
        Date d1 = Date.newInstance(2026, 1, 5);
        Date d2 = Date.newInstance(2026, 1, 7);

        Leave_Request__c existing = new Leave_Request__c(
            Requester__c = u.Id,
            Start_Date__c = d1,
            Start_Slot__c = 'AM',
            End_Date__c = d2,
            End_Slot__c = 'PM',
            Status__c = 'Approved',
            Leave_Type__c = '연차'
        );
        insert existing;

        Leave_Request__c conflict = new Leave_Request__c(
            Requester__c = u.Id,
            Start_Date__c = d1,
            Start_Slot__c = 'PM',
            End_Date__c = d2,
            End_Slot__c = 'PM',
            Status__c = 'Draft',
            Leave_Type__c = '연차'
        );

        Test.startTest();
        Boolean threw = false;
        try {
            LeaveService.validateNoConflict(conflict);
        } catch (LeaveService.LeaveValidationException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, '충돌 검사 예외');
    }
}