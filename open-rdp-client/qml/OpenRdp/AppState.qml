import QtQuick 2.12

Item {
    id: mainView
    property var bridge: RdpBridge
    property string appPlatform: ""
    property string updateProvider: ""
    signal frameUpdated
    signal actionCompleted(var result)
    property int nextRequestId: 0
    property var requestHandlers: ({})
    property var replacementAction: null
    property var replacementHandler: null
    readonly property bool replacementPromptVisible: replacementAction !== null
    readonly property bool hasActiveSession: activeProfileId.length > 0 && sessionStage !== "error" && sessionStage !== "disconnected"
    property var sessionProfile: null
    property bool temporarySession: false

    property string currentTab: "pcs" // "pcs", "accounts", "settings"
    property bool inSessionView: false

    property var profilesList: []
    property var accountsList: []
    property var knownCertsList: []
    property var appSettings: ({
            "themeMode": "dark",
            "libraryLayout": "grid",
            "librarySort": "name",
            "defaultResolution": "native",
            "defaultScaleFactor": 100,
            "defaultTouchMode": "direct_touch",
            "defaultAudioMode": "play_on_device",
            "defaultClipboardEnabled": true,
            "trackpadSpeedPercent": 100,
            "showStatsOverlay": false,
            "strictCertCheck": false,
            "reportErrors": true,
            "autoCheckUpdates": true,
            "skippedUpdateVersion": "",
            "lastUpdateCheckEpoch": 0
        })
    property bool settingsLoaded: false
    property string appVersion: ""
    property string appArchitecture: ""
    property string appFramework: ""

    property string activeProfileId: ""
    readonly property var activePc: {
        for (var i = 0; i < profilesList.length; i++)
            if (profilesList[i].id === activeProfileId)
                return profilesList[i];
        return sessionProfile;
    }
    property string activePcTitle: "Remote PC"
    property string sessionStage: "disconnected"
    property string sessionStageDetail: ""
    property string touchMode: "direct_touch"
    property int remoteWidth: 1280
    property int remoteHeight: 720
    property int cursorX: 640
    property int cursorY: 360
    property int currentFps: 60
    property string ctrlState: "off"
    property string altState: "off"
    property string shiftState: "off"
    property string winState: "off"
    property var pendingCertPrompt: null

    // Credential prompt state ("Ask every time")
    property bool showCredPrompt: false
    property string credProfileId: ""
    property string credPcTitle: ""
    property string credUsername: ""
    property string credPassword: ""

    property string toastMessage: ""

    readonly property bool isDarkMode: (appSettings.themeMode || "dark") !== "light"

    function sendAction(payloadObj) {
        bridge.dispatchJson(JSON.stringify(payloadObj));
    }

    function showToast(msg) {
        toastMessage = msg;
        toastTimer.restart();
    }

    function submitAction(payload, handler) {
        var requestId = "ui-" + (++nextRequestId);
        payload.requestId = requestId;
        requestHandlers[requestId] = handler;
        sendAction(payload);
        return requestId;
    }

    function sendConnection(payload, handler) {
        pendingCertPrompt = null;
        sessionStageDetail = "";
        payload.viewportWidth = Math.max(320, Math.round(mainView.width));
        payload.viewportHeight = Math.max(200, Math.round(mainView.height));
        if (handler)
            submitAction(payload, handler);
        else
            sendAction(payload);
    }

    function requestConnection(payload, handler) {
        if (hasActiveSession) {
            if (payload.action === "connect_pc" && payload.id === activeProfileId) {
                inSessionView = true;
            } else {
                replacementAction = payload;
                replacementHandler = handler || null;
            }
        } else {
            sendConnection(payload, handler);
        }
    }

    function confirmReplacement() {
        var payload = replacementAction;
        var handler = replacementHandler;
        replacementAction = null;
        replacementHandler = null;
        if (payload)
            sendConnection(payload, handler);
    }

    function cancelReplacement() {
        var handler = replacementHandler;
        replacementAction = null;
        replacementHandler = null;
        if (handler)
            handler({
                    "ok": false,
                    "message": ""
                });
    }

    function connectToProfile(pcId, userOverride, passOverride) {
        var payload = {
            "action": "connect_pc",
            "id": pcId
        };
        if (userOverride) {
            payload.username = userOverride;
            payload.password = passOverride || "";
            sendConnection(payload);
            credPassword = "";
        } else
            requestConnection(payload);
    }

    function quickConnect(host, accountId, handler) {
        requestConnection({
                "action": "quick_connect",
                "hostInput": host,
                "accountId": accountId || ""
            }, handler);
    }

    function submitCredentials() {
        if (!credUsername.trim())
            return;
        showCredPrompt = false;
        connectToProfile(credProfileId, credUsername.trim(), credPassword);
        credPassword = "";
    }

    function cancelCredentials() {
        showCredPrompt = false;
        credPassword = "";
    }

    function retryConnection() {
        if (activeProfileId)
            sendConnection({
                    "action": "connect_pc",
                    "id": activeProfileId
                });
    }

    function cancelConnection() {
        pendingCertPrompt = null;
        cancelCredentials();
        sendAction({
                "action": "disconnect_session"
            });
        inSessionView = false;
    }

    Component.onCompleted: {
        sendAction({
                "action": "init"
            });
    }

    Connections {
        target: mainView.bridge

        function onEventJsonReceived(jsonString) {
            var ev = {};
            try {
                ev = JSON.parse(jsonString);
            } catch (e) {
                return;
            }
            if (ev.type === "state_snapshot") {
                mainView.appVersion = ev.appVersion || "";
                mainView.appArchitecture = ev.appArchitecture || "";
                mainView.appFramework = ev.appFramework || "";
                mainView.appPlatform = ev.appPlatform || "";
                mainView.updateProvider = ev.updateProvider || "";
                mainView.profilesList = ev.profiles || [];
                mainView.accountsList = ev.accounts || [];
                mainView.knownCertsList = ev.knownCerts || [];
                if (ev.settings) {
                    mainView.appSettings = ev.settings;
                    mainView.settingsLoaded = true;
                }
                if (ev.session) {
                    if (mainView.activeProfileId !== (ev.session.activeProfileId || ""))
                        mainView.pendingCertPrompt = null;
                    mainView.activeProfileId = ev.session.activeProfileId || "";
                    mainView.sessionProfile = ev.session.activeProfile || null;
                    mainView.temporarySession = ev.session.isTemporary === true;
                    if (mainView.activePc)
                        mainView.activePcTitle = mainView.activePc.displayTitle;
                    mainView.sessionStageDetail = ev.session.stageDetail || "";
                    mainView.sessionStage = ev.session.stage || "disconnected";
                    mainView.touchMode = ev.session.touchMode || "direct_touch";
                    mainView.cursorX = ev.session.cursorX || 0;
                    mainView.cursorY = ev.session.cursorY || 0;
                    mainView.ctrlState = ev.session.ctrlState || "off";
                    mainView.altState = ev.session.altState || "off";
                    mainView.shiftState = ev.session.shiftState || "off";
                    mainView.winState = ev.session.winState || "off";
                }
            } else if (ev.type === "action_result") {
                var handler = mainView.requestHandlers[ev.requestId];
                delete mainView.requestHandlers[ev.requestId];
                if (handler)
                    handler(ev);
                mainView.actionCompleted(ev);
            } else if (ev.type === "session_stage") {
                mainView.sessionStage = ev.stage || "disconnected";
                mainView.sessionStageDetail = ev.detail || "";
                if (ev.stage !== "disconnected") {
                    mainView.inSessionView = true;
                }
            } else if (ev.type === "certificate_prompt") {
                mainView.pendingCertPrompt = ev;
                mainView.inSessionView = true;
            } else if (ev.type === "credentials_required") {
                mainView.credProfileId = ev.profileId || "";
                mainView.credPcTitle = ev.displayTitle || "Remote PC";
                mainView.credUsername = ev.prefillUsername || "";
                mainView.credPassword = "";
                mainView.showCredPrompt = true;
            } else if (ev.type === "desktop_resized") {
                mainView.remoteWidth = ev.width || 1280;
                mainView.remoteHeight = ev.height || 720;
                mainView.frameUpdated();
            } else if (ev.type === "frame_updated") {
                mainView.currentFps = ev.fps || 60;
                mainView.cursorX = ev.cursorX !== undefined ? ev.cursorX : mainView.cursorX;
                mainView.cursorY = ev.cursorY !== undefined ? ev.cursorY : mainView.cursorY;
                mainView.frameUpdated();
            } else if (ev.type === "cursor_moved") {
                mainView.cursorX = ev.x || 0;
                mainView.cursorY = ev.y || 0;
            } else if (ev.type === "session_ended") {
                mainView.pendingCertPrompt = null;
                if (!mainView.showCredPrompt || mainView.credProfileId === ev.profileId) {
                    mainView.credPassword = "";
                    mainView.showCredPrompt = false;
                }
                mainView.sessionStageDetail = ev.reason || "";
                if (ev.isError) {
                    mainView.showToast(ev.reason || "Session ended");
                } else {
                    mainView.inSessionView = false;
                }
            } else if (ev.type === "toast_error") {
                mainView.showToast(ev.message || "Operation failed");
            }
        }
    }

    Timer {
        id: toastTimer
        interval: 4000
        onTriggered: mainView.toastMessage = ""
    }
}
