({
    subscribe: function(component) {
        var empApi = component.find("empApi");
        var channel = component.get("v.channel");
        var replayId = -1;
        var self = this;

        // empApi 콜백은 Aura 컨텍스트 밖에서 실행될 수 있어서 $A.getCallback으로 감싸야 component.set/렌더링이 안전합니다.
        var messageCallback = $A.getCallback(function(message) {
            try {
                self.onMessage(component, message);
            } catch (e) {
                try {
                    component.set("v.lastDebug", "messageCallback error");
                } catch (e2) { }
            }
        });

        // 에러 리스너(권한/연결/채널 문제 등) 디버깅용
        try {
            empApi.onError($A.getCallback(function(error) {
                try {
                    component.set("v.lastDebug", "empApi error");
                } catch (e2) { }
            }));
        } catch (e) { }

        component.set("v.lastDebug", "subscribing " + channel);
        empApi.subscribe(channel, replayId, messageCallback).then(function() {
            $A.getCallback(function() {
                component.set("v.lastDebug", "subscribed " + channel);
            })();
        }).catch(function(e) {
            try {
                $A.getCallback(function() {
                    component.set("v.lastDebug", "subscribe failed");
                })();
            } catch (e2) { }
        });
    },

    onMessage: function(component, message) {
        var p = message && message.data && message.data.payload ? message.data.payload : null;
        if (!p) return;
        // 여기까지 왔다는 것은 이벤트 콜백이 실제로 호출됐다는 의미
        try {
            component.set("v.lastDebug", "event received");
        } catch (e0) { }
        if (!p.Payload__c) {
            try {
                component.set("v.lastDebug", "event received (no Payload__c)");
            } catch (e1) { }
            return;
        }

        // Parse Payload__c
        var data;
        try {
            if (typeof p.Payload__c === "object") {
                data = p.Payload__c;
            } else {
                var raw = "" + p.Payload__c;
                raw = raw.split('#"').join('"');
                data = JSON.parse(raw);
            }
        } catch (e) {
            try {
                component.set("v.lastDebug", "payload parse failed");
            } catch (e2) { }
            return;
        }

        // Skip if sender is me (15-char compare)
        // 주의: Platform Event의 CreatedById는 "이벤트 발행자(대개 sender)"이므로, 현재 사용자와 비교해야 합니다.
        var myId15 = "";
        try {
            myId15 = ("" + $A.get("$SObjectType.CurrentUser.Id")).substring(0, 15);
        } catch (eMy) {
            myId15 = "";
        }
        var senderId15 = (data.senderId || "").substring(0, 15);
        if (senderId15 && myId15 && senderId15 === myId15) {
            try {
                component.set("v.lastDebug", "event ignored (self)");
            } catch (eSelf) { }
            return;
        }

        // 참여자가 아닌 사용자는 이벤트를 무시 (Platform Event는 org-wide 브로드캐스트)
        try {
            var list = data.participantIds;
            if (list && list.length) {
                var ok = false;
                for (var i = 0; i < list.length; i++) {
                    if ((list[i] || "").toString().substring(0, 15) === myId15) {
                        ok = true;
                        break;
                    }
                }
                if (!ok) {
                    component.set("v.lastDebug", "event ignored (not participant)");
                    return;
                }
            }
        } catch (eP) {
            // participantIds가 없거나 형식이 다르면(구버전) 오탐 방지를 위해 무시
            component.set("v.lastDebug", "event ignored (no participantIds)");
            return;
        }

        // 채팅방 이름 변경(SessionRenamed)은 플래시 알림 대상에서 제외
        try {
            // 플래시는 "새 메시지"에만 반응해야 함.
            // ReadReceipt(읽음 갱신), SessionRenamed(이름 변경) 등은 플래시 대상이 아닙니다.
            var t = data && data.type ? ("" + data.type) : "";
            // type이 없거나(구버전/이상 payload) 메시지 이벤트가 아니면 오탐 방지를 위해 무시
            if (!t || (t !== "NewMessage" && t !== "System")) {
                component.set("v.lastDebug", "event ignored (type=" + t + ")");
                return;
            }
        } catch (eType) { }

        var sessionId15 = (data.sessionId || "").substring(0, 15);
        if (!sessionId15) return;

        // Mute 세션이면 플래시 제외 (UtilityChat이 localStorage에 저장)
        try {
            var rawMuted = window.localStorage.getItem("utilityChat.mutedSessions15");
            if (rawMuted) {
                var muted = JSON.parse(rawMuted);
                if (muted && muted.length) {
                    for (var mi = 0; mi < muted.length; mi++) {
                        if ((muted[mi] || "").toString().substring(0, 15) === sessionId15) {
                            component.set("v.lastDebug", "event ignored (muted session)");
                            return;
                        }
                    }
                }
            }
        } catch (eMute) { }

        component.set("v.flashSession15", sessionId15);
        component.set("v.lastDebug", "event session=" + sessionId15);

        // 요구사항(추가):
        // - UtilityChat이 최소화/닫힘(utilityVisible=false) 이면 무조건 플래시
        // - UtilityChat이 열려있더라도, "현재 보고 있는 방"과 다른 방(sessionId15)에서 새 메시지가 오면 플래시
        var self = this;
        self.findTargetUtilityId(component).then(function(utilityId) {
            if (!utilityId) {
                component.set("v.lastDebug", "target utility not found");
                return;
            }
            var utilityBarAPI = component.find("utilitybar");
            return utilityBarAPI
                .getUtilityInfo({ utilityId: utilityId })
                .then(function(info) {
                    var utilityVisible = !!(info && info.utilityVisible);
                    var shouldFlash = !utilityVisible;

                    if (utilityVisible) {
                        // UtilityChat이 열려있을 때는 "다른 방" 알림만 플래시
                        try {
                            var isChatView = (window.localStorage.getItem("utilityChat.isChatView") || "") === "true";
                            var active15 = (window.localStorage.getItem("utilityChat.activeSession15") || "").substring(0, 15);
                            if (isChatView && active15 && active15 !== sessionId15) {
                                shouldFlash = true;
                                component.set("v.lastDebug", "event (other session while visible)");
                            } else {
                                component.set("v.lastDebug", "event (visible - same session)");
                            }
                        } catch (eLS) {
                            component.set("v.lastDebug", "event (visible - no storage)");
                        }
                    }

                    if (shouldFlash) {
                        self.startFlash(component, sessionId15);
                    }
                })
                .catch(function() {
                    // utilityVisible 상태를 확인 못 하면 오탐 플래시가 날 수 있으므로 재시도 후 포기
                    component.set("v.lastDebug", "utilityInfo failed (retry)");
                    self.retryFlashIfMinimized(component, utilityId, sessionId15, 3);
                });
        }).catch(function() {
            // getAllUtilityInfo 자체가 실패하면 플래시를 시작하지 않음(오탐 방지)
            try {
                component.set("v.lastDebug", "getAllUtilityInfo failed");
            } catch (e) { }
        });
    },

    retryFlashIfMinimized: function(component, utilityId, sessionId15, attemptsLeft) {
        var self = this;
        if (!attemptsLeft || attemptsLeft <= 0) {
            try {
                component.set("v.lastDebug", "utilityInfo failed (give up)");
            } catch (e) { }
            return;
        }

        window.setTimeout($A.getCallback(function() {
            try {
                var utilityBarAPI = component.find("utilitybar");
                utilityBarAPI
                    .getUtilityInfo({ utilityId: utilityId })
                    .then(function(info) {
                        if (info && info.utilityVisible) {
                            component.set("v.lastDebug", "event (utility visible)");
                            return;
                        }
                        self.startFlash(component, sessionId15);
                    })
                    .catch(function() {
                        self.retryFlashIfMinimized(component, utilityId, sessionId15, attemptsLeft - 1);
                    });
            } catch (e2) {
                self.retryFlashIfMinimized(component, utilityId, sessionId15, attemptsLeft - 1);
            }
        }), 300);
    },

    findTargetUtilityId: function(component) {
        var utilityBarAPI = component.find("utilitybar");
        var match = (component.get("v.targetUtilityLabel") || "").toLowerCase();

        return utilityBarAPI.getAllUtilityInfo().then(function(infos) {
            var id = null;
            for (var i = 0; i < (infos || []).length; i++) {
                var u = infos[i];
                var header = (u.panelHeaderLabel || "").toLowerCase();
                if (match && (header === match || header.indexOf(match) !== -1)) {
                    id = u.id;
                    break;
                }
            }
            return id;
        });
    },

    startFlash: function(component, sessionId15) {
        var utilityBarAPI = component.find("utilitybar");
        var self = this;

        // 이미 플래시 중이면(다른 방에서 이벤트가 와도) 타겟 세션만 갱신하고 계속 유지
        if (component.get("v.isFlashing")) {
            component.set("v.flashSession15", sessionId15);
            component.set("v.lastDebug", "flashing (update session=" + sessionId15 + ")");
            return;
        }
        component.set("v.isFlashing", true);

        self.findTargetUtilityId(component).then(function(utilityId) {
            if (!utilityId) {
                component.set("v.isFlashing", false);
                component.set("v.lastDebug", "target utility not found");
                return;
            }
            component.set("v.lastDebug", "flash targetId=" + utilityId);

            var highlighted = false;
            var startedAt = Date.now();
            // 안전장치: 너무 오래 방치되면 자동 종료(10분)
            var maxMs = 10 * 60 * 1000;

            var intervalId = window.setInterval($A.getCallback(function() {
                // Stop 조건:
                // - UtilityChat이 열려있고, 현재 보고 있는 방이 flashSession15와 같으면 중단
                try {
                    utilityBarAPI.getUtilityInfo({ utilityId: utilityId }).then(function(info) {
                        if (info && info.utilityVisible) {
                            try {
                                var isChatView = (window.localStorage.getItem("utilityChat.isChatView") || "") === "true";
                                var active15 = (window.localStorage.getItem("utilityChat.activeSession15") || "").substring(0, 15);
                                var target15 = (component.get("v.flashSession15") || "").substring(0, 15);
                                if (isChatView && active15 && target15 && active15 === target15) {
                                    self.stopFlash(component);
                                }
                            } catch (eStop) { }
                        }
                    });
                } catch (e) { }

                // 안전장치: 최대 시간 초과 시 종료
                if (Date.now() - startedAt >= maxMs) {
                    self.stopFlash(component);
                    return;
                }

                highlighted = !highlighted;
                try {
                    utilityBarAPI.setUtilityHighlighted({ utilityId: utilityId, highlighted: highlighted });
                } catch (e) {
                    // ignore
                }
            }), 500);

            component.set("v.intervalId", intervalId);
        }).catch(function() {
            component.set("v.isFlashing", false);
        });
    },

    stopFlash: function(component) {
        var utilityBarAPI = component.find("utilitybar");
        var self = this;

        var intervalId = component.get("v.intervalId");
        if (intervalId) {
            window.clearInterval(intervalId);
            component.set("v.intervalId", null);
        }
        component.set("v.isFlashing", false);

        self.findTargetUtilityId(component).then(function(utilityId) {
            if (utilityId) {
                try {
                    utilityBarAPI.setUtilityHighlighted({ utilityId: utilityId, highlighted: false });
                } catch (e) {
                    // ignore
                }
            }
        });
    }
})