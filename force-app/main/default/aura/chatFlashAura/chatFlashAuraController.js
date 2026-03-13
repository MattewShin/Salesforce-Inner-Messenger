({
    doInit: function (component, event, helper) {
        helper.subscribe(component);
    },

    handleChatEvent: function(component, event, helper) {
        // LWC에서 발생한 이벤트를 처리 (필요시)
        // 현재는 LWC -> Aura 방향만 필요하므로 빈 함수로 유지
    }
})