public with sharing class WorkTimeTriggerHandler {
    /**
     * 데이터 정합성 규칙:
     * - Status__c = 'On Duty' 인 레코드는 Work_End_Time__c 가 항상 null 이어야 합니다.
     *   (UI에서 숨기는 것만으로는 보고/집계/재조회 시 혼선이 생길 수 있어 서버에서 강제)
     */
    public static void beforeInsertOrUpdate(List<Work_Time__c> newList) {
        if (newList == null) return;
        for (Work_Time__c wt : newList) {
            if (wt == null) continue;
            if (wt.Status__c == 'On Duty') {
                wt.Work_End_Time__c = null;
            }
        }
    }
}

