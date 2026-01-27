({
    subscribe: function(component) {
        var empApi = component.find("empApi");
        var channel = component.get("v.channel");
        var replayId = -1;
        var self = this;

        // 중복 구독 방지
        try {
            if (component.get("v.isSubscribing")) {
                return;
            }
            component.set("v.isSubscribing", true);
        } catch (eFlag) { }

        // 기존 구독이 있으면 해제(중복 콜백/불안정 방지)
        try {
            var oldSub = component.get("v.subscription");
            if (oldSub) {
                empApi.unsubscribe(oldSub, $A.getCallback(function() {}));
                component.set("v.subscription", null);
            }
        } catch (eUnsub) { }

        // empApi 콜백은 Aura 컨텍스트 밖에서 실행될 수 있어서 $A.getCallback으로 감싸야 component.set/렌더링이 안전합니다.
        var messageCallback = $A.getCallback(function(message) {
            try {
                // 이벤트 수신 확인용 디버그
                component.set("v.lastDebug", "callback called");
                self.onMessage(component, message);
            } catch (e) {
                try {
                    component.set("v.lastDebug", "messageCallback error: " + (e.message || e));
                } catch (e2) { }
            }
        });

        // 에러 리스너(권한/연결/채널 문제 등) 디버깅용
        try {
            // 여러 번 subscribe()가 호출될 수 있으므로 onError 핸들러는 1회만 등록
            if (!component.get("v.hasEmpErrorHandler")) {
                component.set("v.hasEmpErrorHandler", true);
                empApi.onError($A.getCallback(function(error) {
                    try {
                        var errorMsg = "empApi error";
                        if (error) {
                            if (error.message) errorMsg += ": " + error.message;
                            else if (error.toString) errorMsg += ": " + error.toString();
                        }
                        component.set("v.lastDebug", errorMsg);
                    } catch (e2) { }

                    // 간헐적 끊김/재연결 대비: 자동 재구독(중복 방지)
                    try {
                        self.scheduleResubscribe(component, 1500);
                    } catch (e3) { }
                }));
            }
        } catch (e) { }

        component.set("v.lastDebug", "subscribing " + channel);
        empApi.subscribe(channel, replayId, messageCallback).then(function(subscription) {
            $A.getCallback(function() {
                component.set("v.lastDebug", "subscribed " + channel + " (id=" + (subscription && subscription.channel ? subscription.channel : "?") + ")");
                // 구독 객체를 저장하여 나중에 확인 가능하도록
                component.set("v.subscription", subscription);
                component.set("v.isSubscribing", false);
            })();
        }).catch(function(e) {
            try {
                $A.getCallback(function() {
                    component.set("v.lastDebug", "subscribe failed: " + (e.message || e || "unknown"));
                    component.set("v.isSubscribing", false);
                })();
            } catch (e2) { }

            // 실패 시에도 자동 재시도
            try {
                self.scheduleResubscribe(component, 2500);
            } catch (e3) { }
        });
    },

    scheduleResubscribe: function(component, delayMs) {
        var self = this;
        try {
            var t = component.get("v.resubscribeTimer");
            if (t) {
                // 이미 스케줄돼 있으면 중복 방지
                return;
            }
        } catch (e0) { }

        var ms = (delayMs == null) ? 1500 : delayMs;
        var timer = window.setTimeout($A.getCallback(function() {
            try {
                component.set("v.resubscribeTimer", null);
            } catch (e1) { }
            try {
                self.subscribe(component);
            } catch (e2) { }
        }), ms);

        try {
            component.set("v.resubscribeTimer", timer);
        } catch (e3) { }
    },

    onMessage: function(component, message) {
        // 모든 이벤트 수신 시 로그 남기기 (디버깅용)
        try {
            var eventType = "unknown";
            if (message && message.data && message.data.payload && message.data.payload.Payload__c) {
                try {
                    var rawPayload = message.data.payload.Payload__c;
                    if (typeof rawPayload === "object") {
                        eventType = rawPayload.type || "no-type";
                    } else {
                        var rawStr = String(rawPayload);
                        var cleaned = rawStr.split('#"').join('"');
                        var parsed = JSON.parse(cleaned);
                        eventType = parsed.type || "no-type";
                    }
                } catch (e) {
                    eventType = "parse-error";
                }
            }
            component.set("v.lastDebug", "event received (type=" + eventType + ")");
        } catch (e0) { }
        
        var p = message && message.data && message.data.payload ? message.data.payload : null;
        if (!p) {
            try {
                component.set("v.lastDebug", "no payload");
            } catch (e0) { }
            return;
        }
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
            try {
                component.set("v.lastDebug", "payload parsed");
            } catch (e2) { }
        } catch (e) {
            try {
                component.set("v.lastDebug", "payload parse failed: " + (e.message || e));
            } catch (e2) { }
            return;
        }

        // Skip if sender is me (15-char compare)
        // 주의: Platform Event의 CreatedById는 "이벤트 발행자(대개 sender)"이므로, 현재 사용자와 비교해야 합니다.
        var myId15 = "";
        try {
            myId15 = ("" + $A.get("$SObjectType.CurrentUser.Id")).substring(0, 15);
            try {
                component.set("v.lastDebug", "myId=" + myId15);
            } catch (e) { }
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
        try {
            component.set("v.lastDebug", "sender check passed");
        } catch (e) { }

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
                    try {
                        component.set("v.lastDebug", "event ignored (not participant)");
                    } catch (e) { }
                    return;
                }
            } else {
                // participantIds가 없으면(구버전) 오탐 방지를 위해 무시
                try {
                    component.set("v.lastDebug", "event ignored (no participantIds)");
                } catch (e) { }
                return;
            }
            try {
                component.set("v.lastDebug", "participant check passed");
            } catch (e) { }
        } catch (eP) {
            // participantIds가 없거나 형식이 다르면(구버전) 오탐 방지를 위해 무시
            try {
                component.set("v.lastDebug", "event ignored (no participantIds - error)");
            } catch (e) { }
            return;
        }

        // 채팅방 이름 변경(SessionRenamed)은 플래시 알림 대상에서 제외
        try {
            // 플래시는 "새 메시지"에만 반응해야 함.
            // ReadReceipt(읽음 갱신), SessionRenamed(이름 변경) 등은 플래시 대상이 아닙니다.
            var t = data && data.type ? ("" + data.type) : "";
            try {
                component.set("v.lastDebug", "checking type: " + (t || "empty"));
            } catch (e) { }
            // type이 없거나(구버전/이상 payload) 메시지 이벤트가 아니면 오탐 방지를 위해 무시
            if (!t || (t !== "NewMessage" && t !== "System")) {
                // ReadReceipt와 SessionRenamed는 정상적으로 무시되는 이벤트이므로 디버그 로그를 남기지 않음
                if (t !== "ReadReceipt" && t !== "SessionRenamed") {
                    try {
                        component.set("v.lastDebug", "event ignored (type=" + t + ")");
                    } catch (e) { }
                } else {
                    // ReadReceipt나 SessionRenamed인 경우에도 확인용으로 로그 남김 (디버깅용)
                    try {
                        component.set("v.lastDebug", "event ignored (type=" + t + " - normal)");
                    } catch (e) { }
                }
                return;
            }
            // NewMessage 또는 System 이벤트인 경우 디버그 로그
            try {
                component.set("v.lastDebug", "event type=" + t + " (processing)");
            } catch (e) { }
        } catch (eType) {
            try {
                component.set("v.lastDebug", "type check error: " + (eType.message || eType));
            } catch (eType2) { }
        }

        var sessionId15 = (data.sessionId || "").substring(0, 15);
        if (!sessionId15) {
            try {
                component.set("v.lastDebug", "no sessionId");
            } catch (e) { }
            return;
        }
        try {
            component.set("v.lastDebug", "sessionId=" + sessionId15);
        } catch (e) { }

        // Mute 세션이면 플래시 제외 (UtilityChat이 localStorage에 저장)
        try {
            var rawMuted = window.localStorage.getItem("utilityChat.mutedSessions15");
            if (rawMuted) {
                var muted = JSON.parse(rawMuted);
                if (muted && muted.length) {
                    for (var mi = 0; mi < muted.length; mi++) {
                        if ((muted[mi] || "").toString().substring(0, 15) === sessionId15) {
                            try {
                                component.set("v.lastDebug", "event ignored (muted session)");
                            } catch (e) { }
                            return;
                        }
                    }
                }
            }
            try {
                component.set("v.lastDebug", "mute check passed");
            } catch (e) { }
        } catch (eMute) {
            try {
                component.set("v.lastDebug", "mute check error");
            } catch (e) { }
        }

        component.set("v.flashSession15", sessionId15);
        try {
            component.set("v.lastDebug", "event session=" + sessionId15 + " (finding utility)");
        } catch (e) { }

        // 요구사항(추가):
        // - UtilityChat이 최소화/닫힘(utilityVisible=false) 이면 무조건 플래시
        // - UtilityChat이 열려있더라도, "현재 보고 있는 방"과 다른 방(sessionId15)에서 새 메시지가 오면 플래시
        var self = this;
        try {
            component.set("v.lastDebug", "finding utility...");
        } catch (e) { }
        self.findTargetUtilityId(component, 8).then(function(utilityId) {
            if (!utilityId) {
                try {
                    component.set("v.lastDebug", "target utility not found (label=" + (component.get("v.targetUtilityLabel") || "") + ")");
                } catch (e) { }
                return;
            }
            try {
                component.set("v.lastDebug", "utility found: " + utilityId);
            } catch (e) { }
            var utilityBarAPI = component.find("utilitybar");
            return utilityBarAPI
                .getUtilityInfo({ utilityId: utilityId })
                .then(function(info) {
                    var utilityVisible = !!(info && info.utilityVisible);
                    var shouldFlash = !utilityVisible;

                    if (utilityVisible) {
                        // UtilityChat이 열려있을 때:
                        // - "현재 보고 있는 방"과 같은 방이면 플래시하지 않음
                        // - 그 외(리스트 화면이거나 다른 방이거나 active 정보가 없으면) 플래시
                        try {
                            var isChatView = (window.localStorage.getItem("utilityChat.isChatView") || "") === "true";
                            var active15 = (window.localStorage.getItem("utilityChat.activeSession15") || "").substring(0, 15);
                            // 리스트 화면(isChatView=false)이라도 사용자는 해당 방을 "보고 있는 상태"가 아니므로 플래시가 필요합니다.
                            if (!isChatView || !active15) {
                                shouldFlash = true;
                                component.set("v.lastDebug", "event (visible - not in session view)");
                            } else if (active15 !== sessionId15) {
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
                    // utilityVisible 상태를 확인 못 하는 경우가 간헐적으로 발생할 수 있어 재시도합니다.
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
                // 마지막엔 best-effort로라도 플래시(미수신 체감 방지)
                component.set("v.lastDebug", "utilityInfo failed (force flash)");
            } catch (e) { }
            try {
                self.startFlash(component, sessionId15);
            } catch (e2) { }
            return;
        }

        window.setTimeout($A.getCallback(function() {
            try {
                var utilityBarAPI = component.find("utilitybar");
                utilityBarAPI
                    .getUtilityInfo({ utilityId: utilityId })
                    .then(function(info) {
                        var utilityVisible = !!(info && info.utilityVisible);
                        if (!utilityVisible) {
                            self.startFlash(component, sessionId15);
                            return;
                        }

                        // visible인 경우에도 "실제로 해당 방을 보고 있는 상태"가 아니면 플래시
                        try {
                            var isChatView = (window.localStorage.getItem("utilityChat.isChatView") || "") === "true";
                            var active15 = (window.localStorage.getItem("utilityChat.activeSession15") || "").substring(0, 15);
                            if (!isChatView || !active15 || active15 !== sessionId15) {
                                component.set("v.lastDebug", "event (utility visible - should flash)");
                                self.startFlash(component, sessionId15);
                            } else {
                                component.set("v.lastDebug", "event (utility visible - same session)");
                            }
                        } catch (eLS) {
                            self.startFlash(component, sessionId15);
                        }
                    })
                    .catch(function() {
                        self.retryFlashIfMinimized(component, utilityId, sessionId15, attemptsLeft - 1);
                    });
            } catch (e2) {
                self.retryFlashIfMinimized(component, utilityId, sessionId15, attemptsLeft - 1);
            }
        }), 300);
    },

    findTargetUtilityId: function(component, attemptsLeft) {
        // 캐시된 유틸리티 ID가 있으면 바로 사용
        try {
            var cached = component.get("v.cachedUtilityId");
            if (cached) {
                return Promise.resolve(cached);
            }
        } catch (e0) { }

        var utilityBarAPI = component.find("utilitybar");
        var match = (component.get("v.targetUtilityLabel") || "").toLowerCase();

        var left = (attemptsLeft == null) ? 1 : attemptsLeft;

        return utilityBarAPI.getAllUtilityInfo().then($A.getCallback(function(infos) {
            var id = null;
            for (var i = 0; i < (infos || []).length; i++) {
                var u = infos[i];
                // org/앱/버전에 따라 라벨 필드명이 다를 수 있어 여러 후보를 함께 비교
                var candidates = [];
                try {
                    candidates.push(u.panelHeaderLabel);
                    candidates.push(u.utilityLabel);
                    candidates.push(u.label);
                    candidates.push(u.apiName);
                    candidates.push(u.developerName);
                    candidates.push(u.name);
                } catch (eC) { }

                var matched = false;
                for (var ci = 0; ci < candidates.length; ci++) {
                    var c = (candidates[ci] || "").toString().toLowerCase();
                    if (!c) continue;
                    if (match && (c === match || c.indexOf(match) !== -1)) {
                        matched = true;
                        break;
                    }
                }
                if (matched) {
                    id = u.id;
                    break;
                }
            }
            if (id) {
                try {
                    component.set("v.cachedUtilityId", id);
                } catch (e1) { }
                return id;
            }

            if (left <= 1) return null;

            // 유틸리티 정보가 아직 로드되지 않은 타이밍 대비: 짧게 재시도
            return new Promise(function(resolve) {
                window.setTimeout($A.getCallback(function() {
                    resolve(null);
                }), 250);
            }).then(function() {
                return this.findTargetUtilityId(component, left - 1);
            }.bind(this));
        }.bind(this)));
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