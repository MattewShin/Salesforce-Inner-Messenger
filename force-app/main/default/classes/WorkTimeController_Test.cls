@IsTest
private class WorkTimeController_Test {
    @IsTest
    static void clockIn_shouldClearEndTime_whenReClockInAfterClockOut() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();

        // 기존에 "퇴근"까지 기록된 상태를 만든다.
        Work_Time__c wt = new Work_Time__c(
            User__c = me,
            Work_Date__c = today,
            Work_Start_Time__c = Time.newInstance(9, 0, 0, 0),
            Work_End_Time__c = Time.newInstance(18, 0, 0, 0),
            Status__c = 'Off Duty'
        );
        insert wt;

        Test.startTest();
        Work_Time__c afterClockIn = WorkTimeController.clockIn();
        Test.stopTest();

        Work_Time__c reloaded = [
            SELECT Work_Start_Time__c, Work_End_Time__c, Status__c
            FROM Work_Time__c
            WHERE Id = :afterClockIn.Id
            LIMIT 1
        ];

        System.assertEquals('On Duty', reloaded.Status__c, '재출근 시 상태는 On Duty여야 합니다.');
        System.assertEquals(null, reloaded.Work_End_Time__c, '재출근 시 기존 퇴근 시간은 제거되어야 합니다.');
        System.assertNotEquals(null, reloaded.Work_Start_Time__c, '재출근 시 출근 시간은 설정되어야 합니다.');
    }

    @IsTest
    static void clockOut_shouldSetEndTime_andStatusOffDuty() {
        // 출근 → 퇴근 흐름 기본 검증
        Test.startTest();
        Work_Time__c clockedIn = WorkTimeController.clockIn();
        Work_Time__c clockedOut = WorkTimeController.clockOut();
        Test.stopTest();

        Work_Time__c reloaded = [
            SELECT Work_Start_Time__c, Work_End_Time__c, Status__c
            FROM Work_Time__c
            WHERE Id = :clockedOut.Id
            LIMIT 1
        ];

        System.assertEquals('Off Duty', reloaded.Status__c, '퇴근 시 상태는 Off Duty여야 합니다.');
        System.assertNotEquals(null, reloaded.Work_Start_Time__c, '퇴근 전 출근 시간이 있어야 합니다.');
        System.assertNotEquals(null, reloaded.Work_End_Time__c, '퇴근 시 퇴근 시간이 설정되어야 합니다.');
    }

    @IsTest
    static void trigger_shouldClearEndTime_whenStatusOnDuty() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();

        // On Duty인데 End Time이 들어온 경우(어떤 경로로든) 서버에서 강제로 제거되어야 함
        Work_Time__c wt = new Work_Time__c(
            User__c = me,
            Work_Date__c = today,
            Work_Start_Time__c = Time.newInstance(9, 0, 0, 0),
            Work_End_Time__c = Time.newInstance(9, 0, 0, 0),
            Status__c = 'On Duty'
        );
        insert wt;

        Work_Time__c reloaded = [
            SELECT Work_End_Time__c, Status__c
            FROM Work_Time__c
            WHERE Id = :wt.Id
            LIMIT 1
        ];

        System.assertEquals('On Duty', reloaded.Status__c);
        System.assertEquals(null, reloaded.Work_End_Time__c, 'On Duty인 레코드는 Work_End_Time__c가 항상 null이어야 합니다.');
    }
}

