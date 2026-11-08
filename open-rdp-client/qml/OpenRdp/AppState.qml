import QtQuick 2.12

Item {
    id: mainView
    property var bridge: RdpBridge
    property string appPlatform: ""
    property string updateProvider: ""
    signal frameUpdated()

    property string currentTab: "pcs" // "pcs", "accounts", "settings"
    property bool inSessionView: false

    property var profilesList: []
    property var accountsList: []
    property var knownCertsList: []
    property var appSettings: ({
        themeMode: "dark",
        defaultResolution: "native",
        defaultScaleFactor: 100,
        defaultTouchMode: "direct_touch",
        defaultAudioMode: "play_on_device",
        defaultClipboardEnabled: true,
        trackpadSpeedPercent: 100,
        showStatsOverlay: false,
        strictCertCheck: false,
        reportErrors: true,
        autoCheckUpdates: true,
        skippedUpdateVersion: "",
        lastUpdateCheckEpoch: 0
    })
    property bool settingsLoaded: false
    property string appVersion: ""
    property string appArchitecture: ""
    property string appFramework: ""

    property string activeProfileId: ""
    readonly property var activePc: {
        for (var i = 0; i < profilesList.length; i++)
            if (profilesList[i].id === activeProfileId) return profilesList[i]
        return null
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
        bridge.dispatchJson(JSON.stringify(payloadObj))
    }

    function showToast(msg) {
        toastMessage = msg
        toastTimer.restart()
    }

    function connectToProfile(pcId, userOverride, passOverride) {
        for (var i = 0; i < profilesList.length; i++) {
            if (profilesList[i].id === pcId) {
                activePcTitle = profilesList[i].displayTitle
                break
            }
        }
        sendAction({
            action: "connect_pc",
            id: pcId,
            viewportWidth: Math.round(mainView.width),
            viewportHeight: Math.round(mainView.height),
            username: userOverride || "",
            password: passOverride || ""
        })
    }

    Component.onCompleted: {
        sendAction({ action: "init" })
    }

    Connections {
        target: mainView.bridge

        function onEventJsonReceived(jsonString) {
            var ev = {}
            try {
                ev = JSON.parse(jsonString)
            } catch (e) {
                return
            }

            if (ev.type === "state_snapshot") {
                mainView.appVersion = ev.appVersion || ""
                mainView.appArchitecture = ev.appArchitecture || ""
                mainView.appFramework = ev.appFramework || ""
                mainView.appPlatform = ev.appPlatform || ""
                mainView.updateProvider = ev.updateProvider || ""
                mainView.profilesList = ev.profiles || []
                mainView.accountsList = ev.accounts || []
                mainView.knownCertsList = ev.knownCerts || []
                if (ev.settings) {
                    mainView.appSettings = ev.settings
                    mainView.settingsLoaded = true
                }
                if (ev.session) {
                    mainView.activeProfileId = ev.session.activeProfileId || ""
                    mainView.sessionStage = ev.session.stage || "disconnected"
                    mainView.touchMode = ev.session.touchMode || "direct_touch"
                    mainView.cursorX = ev.session.cursorX || 0
                    mainView.cursorY = ev.session.cursorY || 0
                    mainView.ctrlState = ev.session.ctrlState || "off"
                    mainView.altState = ev.session.altState || "off"
                    mainView.shiftState = ev.session.shiftState || "off"
                    mainView.winState = ev.session.winState || "off"
                }
            } else if (ev.type === "session_stage") {
                mainView.sessionStage = ev.stage || "disconnected"
                mainView.sessionStageDetail = ev.detail || ""
                if (ev.stage !== "disconnected") {
                    mainView.inSessionView = true
                }
            } else if (ev.type === "certificate_prompt") {
                mainView.pendingCertPrompt = ev
                mainView.inSessionView = true
            } else if (ev.type === "credentials_required") {
                mainView.credProfileId = ev.profileId || ""
                mainView.credPcTitle = ev.displayTitle || "Remote PC"
                mainView.credUsername = ev.prefillUsername || ""
                mainView.credPassword = ""
                mainView.showCredPrompt = true
            } else if (ev.type === "desktop_resized") {
                mainView.remoteWidth = ev.width || 1280
                mainView.remoteHeight = ev.height || 720
                mainView.frameUpdated()
            } else if (ev.type === "frame_updated") {
                mainView.currentFps = ev.fps || 60
                mainView.cursorX = ev.cursorX !== undefined ? ev.cursorX : mainView.cursorX
                mainView.cursorY = ev.cursorY !== undefined ? ev.cursorY : mainView.cursorY
                mainView.frameUpdated()
            } else if (ev.type === "cursor_moved") {
                mainView.cursorX = ev.x || 0
                mainView.cursorY = ev.y || 0
            } else if (ev.type === "session_ended") {
                mainView.pendingCertPrompt = null
                if (ev.isError) {
                    mainView.showToast(ev.reason || "Session ended")
                } else {
                    mainView.inSessionView = false
                }
            } else if (ev.type === "toast_error") {
                mainView.showToast(ev.message || "Operation failed")
            }
        }
    }

    Timer { id: toastTimer; interval: 4000; onTriggered: mainView.toastMessage = "" }
}
