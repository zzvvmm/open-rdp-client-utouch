import QtQuick 2.12
import Lomiri.Components 1.3
import "pages"
import "components"

MainView {
    id: mainView
    objectName: "mainView"
    applicationName: "rdp-client-ut.zzvvmm"
    automaticOrientation: true

    width: units.gu(50)
    height: units.gu(88)

    property string currentTab: "pcs" // "pcs", "accounts", "settings"
    property bool inSessionView: false

    property var profilesList: []
    property var accountsList: []
    property var knownCertsList: []
    property var appSettings: ({
        themeMode: "dark",
        defaultResolution: "dynamic",
        defaultScaleFactor: 100,
        defaultTouchMode: "mouse_pointer",
        defaultAudioMode: "play_on_device",
        defaultClipboardEnabled: true,
        trackpadSpeedPercent: 100,
        showStatsOverlay: false,
        strictCertCheck: false
    })

    property string activeProfileId: ""
    property string activePcTitle: "Remote PC"
    property string sessionStage: "disconnected"
    property string sessionStageDetail: ""
    property string touchMode: "mouse_pointer"
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
        RdpBridge.dispatchJson(JSON.stringify(payloadObj))
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
        target: RdpBridge

        onEventJsonReceived: {
            var ev = {}
            try {
                ev = JSON.parse(jsonString)
            } catch (e) {
                return
            }

            if (ev.type === "state_snapshot") {
                mainView.profilesList = ev.profiles || []
                mainView.accountsList = ev.accounts || []
                mainView.knownCertsList = ev.knownCerts || []
                if (ev.settings) {
                    mainView.appSettings = ev.settings
                }
                if (ev.session) {
                    mainView.activeProfileId = ev.session.activeProfileId || ""
                    mainView.sessionStage = ev.session.stage || "disconnected"
                    mainView.touchMode = ev.session.touchMode || "mouse_pointer"
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
                sessionPage.notifyFrameUpdated()
            } else if (ev.type === "frame_updated") {
                mainView.currentFps = ev.fps || 60
                mainView.cursorX = ev.cursorX || mainView.cursorX
                mainView.cursorY = ev.cursorY || mainView.cursorY
                sessionPage.notifyFrameUpdated()
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

    Rectangle {
        anchors.fill: parent
        color: mainView.isDarkMode ? "#11151C" : "#F3F5F8"

        // Top Windows App Header Bar (hidden during fullscreen RDP session)
        Rectangle {
            id: topHeader
            visible: !mainView.inSessionView
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: units.gu(6.5)
            color: mainView.isDarkMode ? "#171C26" : "#FFFFFF"
            border.width: units.dp(1)
            border.color: mainView.isDarkMode ? "#262F40" : "#DCE2EC"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: units.gu(2)
                anchors.right: headerActions.left
                anchors.rightMargin: units.gu(1.2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: units.gu(1.2)

                Image {
                    width: units.gu(3.6)
                    height: units.gu(3.6)
                    anchors.verticalCenter: parent.verticalCenter
                    source: "qrc:/assets/logo.svg"
                }

                Column {
                    width: Math.max(0, parent.width - units.gu(4.8))
                    anchors.verticalCenter: parent.verticalCenter
                    Label {
                        width: parent.width
                        elide: Text.ElideRight
                        text: i18n.tr("Open RDP Client")
                        fontSize: "medium"
                        font.bold: true
                        color: mainView.isDarkMode ? "#F3F6FA" : "#1B2028"
                    }
                    Label {
                        width: parent.width
                        elide: Text.ElideRight
                        text: i18n.tr("Ubuntu Touch Remote Desktop")
                        fontSize: "x-small"
                        color: "#29B6F6"
                    }
                }
            }

            Row {
                id: headerActions
                anchors.right: parent.right
                anchors.rightMargin: units.gu(2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: units.gu(1)

                Button {
                    visible: mainView.activeProfileId.length > 0
                    text: i18n.tr("Return to Session")
                    color: "#0D9488"
                    onClicked: mainView.inSessionView = true
                }

                Button {
                    text: i18n.tr("+ Add PC")
                    color: "#0078D4"
                    onClicked: {
                        pcEditor.openForNew(
                            mainView.appSettings.defaultResolution,
                            mainView.appSettings.defaultScaleFactor,
                            mainView.appSettings.defaultTouchMode,
                            mainView.appSettings.defaultAudioMode,
                            mainView.appSettings.defaultClipboardEnabled
                        )
                    }
                }
            }
        }

        // Main Tab Content Area
        Item {
            visible: !mainView.inSessionView
            anchors.top: topHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: bottomNav.top

            DevicesPage {
                anchors.fill: parent
                visible: mainView.currentTab === "pcs"
                profiles: mainView.profilesList
                darkMode: mainView.isDarkMode
                activeProfileId: mainView.activeProfileId

                onConnectPc: mainView.connectToProfile(pcId, "", "")
                onAddPcRequested: {
                    pcEditor.openForNew(
                        mainView.appSettings.defaultResolution,
                        mainView.appSettings.defaultScaleFactor,
                        mainView.appSettings.defaultTouchMode,
                        mainView.appSettings.defaultAudioMode,
                        mainView.appSettings.defaultClipboardEnabled
                    )
                }
                onEditPcRequested: pcEditor.openForEdit(pcData)
                onDuplicatePcRequested: mainView.sendAction({ action: "duplicate_pc", id: pcId })
                onDeletePcRequested: mainView.sendAction({ action: "delete_pc", id: pcId })
                onFavoriteToggled: mainView.sendAction({ action: "toggle_favorite_pc", id: pcId })
            }

            AccountsPage {
                anchors.fill: parent
                visible: mainView.currentTab === "accounts"
                accounts: mainView.accountsList
                knownCerts: mainView.knownCertsList
                darkMode: mainView.isDarkMode

                onSaveAccount: mainView.sendAction(payload)
                onDeleteAccount: mainView.sendAction({ action: "delete_account", id: accountId })
                onRemoveKnownCert: mainView.sendAction({ action: "remove_known_cert", hostPort: hostPort })
            }

            SettingsPage {
                anchors.fill: parent
                visible: mainView.currentTab === "settings"
                settings: mainView.appSettings
                darkMode: mainView.isDarkMode

                onUpdateSettings: mainView.sendAction(payload)
            }
        }

        // Bottom Navigation Bar (Windows App Mobile Layout)
        Rectangle {
            id: bottomNav
            visible: !mainView.inSessionView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: units.gu(6.5)
            color: mainView.isDarkMode ? "#171C26" : "#FFFFFF"
            border.width: units.dp(1)
            border.color: mainView.isDarkMode ? "#262F40" : "#DCE2EC"

            Row {
                anchors.fill: parent

                Repeater {
                    model: [
                        { id: "pcs", label: i18n.tr("PCs"), icon: "computer-symbolic" },
                        { id: "accounts", label: i18n.tr("Accounts & Certs"), icon: "contact" },
                        { id: "settings", label: i18n.tr("Settings"), icon: "settings" }
                    ]
                    delegate: AbstractButton {
                        width: bottomNav.width / 3
                        height: bottomNav.height
                        onClicked: mainView.currentTab = modelData.id

                        Column {
                            anchors.centerIn: parent
                            spacing: units.gu(0.3)

                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(2.4)
                                height: units.gu(2.4)
                                name: modelData.icon
                                color: mainView.currentTab === modelData.id
                                       ? "#0078D4"
                                       : (mainView.isDarkMode ? "#9BA7B8" : "#5A6577")
                            }

                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                fontSize: "x-small"
                                font.bold: mainView.currentTab === modelData.id
                                color: mainView.currentTab === modelData.id
                                       ? "#0078D4"
                                       : (mainView.isDarkMode ? "#9BA7B8" : "#5A6577")
                            }
                        }
                    }
                }
            }
        }

        // Fullscreen Active RDP Session View
        SessionPage {
            id: sessionPage
            visible: mainView.inSessionView
            anchors.fill: parent

            pcTitle: mainView.activePcTitle
            sessionStage: mainView.sessionStage
            stageDetail: mainView.sessionStageDetail
            touchMode: mainView.touchMode
            remoteWidth: mainView.remoteWidth
            remoteHeight: mainView.remoteHeight
            cursorX: mainView.cursorX
            cursorY: mainView.cursorY
            currentFps: mainView.currentFps
            showStats: !!mainView.appSettings.showStatsOverlay
            ctrlState: mainView.ctrlState
            altState: mainView.altState
            shiftState: mainView.shiftState
            winState: mainView.winState
            pendingCert: mainView.pendingCertPrompt

            onDispatchAction: mainView.sendAction(payload)
            onExitSessionView: mainView.inSessionView = false
        }

        // Add / Edit PC Dialog
        PcEditorDialog {
            id: pcEditor
            darkMode: mainView.isDarkMode
            accounts: mainView.accountsList
            onSaveRequested: mainView.sendAction(payload)
        }

        // On-Demand Credentials Prompt Dialog ("Ask every time")
        Rectangle {
            visible: mainView.showCredPrompt
            anchors.fill: parent
            color: "#CC0B0E14"
            z: 85

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Rectangle {
                width: Math.min(parent.width - units.gu(4), units.gu(48))
                height: credCol.implicitHeight + units.gu(4)
                anchors.centerIn: parent
                radius: units.gu(1.6)
                color: mainView.isDarkMode ? "#1C2331" : "#FFFFFF"
                border.width: units.dp(1)
                border.color: "#0078D4"

                Column {
                    id: credCol
                    width: parent.width - units.gu(4)
                    anchors.centerIn: parent
                    spacing: units.gu(1.4)

                    Label {
                        text: i18n.tr("Sign in to ") + mainView.credPcTitle
                        fontSize: "large"
                        font.bold: true
                        color: mainView.isDarkMode ? "#F3F6FA" : "#1B2028"
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Label {
                        text: i18n.tr("Enter your Windows or xrdp credentials (NLA / CredSSP)")
                        fontSize: "small"
                        color: mainView.isDarkMode ? "#9BA7B8" : "#5A6577"
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    TextField {
                        width: parent.width
                        text: mainView.credUsername
                        placeholderText: i18n.tr("Username (e.g. DOMAIN\\user or user)")
                        onTextChanged: mainView.credUsername = text
                    }

                    TextField {
                        width: parent.width
                        text: mainView.credPassword
                        echoMode: TextInput.Password
                        placeholderText: i18n.tr("Password")
                        onTextChanged: mainView.credPassword = text
                    }

                    Row {
                        width: parent.width
                        spacing: units.gu(1.2)

                        Button {
                            width: (parent.width - units.gu(1.2)) / 2
                            text: i18n.tr("Cancel")
                            color: mainView.isDarkMode ? "#263042" : "#E2E8F0"
                            onClicked: mainView.showCredPrompt = false
                        }

                        Button {
                            width: (parent.width - units.gu(1.2)) / 2
                            text: i18n.tr("Connect")
                            color: "#0078D4"
                            onClicked: {
                                if (mainView.credUsername.trim().length === 0) return
                                mainView.showCredPrompt = false
                                mainView.connectToProfile(
                                    mainView.credProfileId,
                                    mainView.credUsername.trim(),
                                    mainView.credPassword
                                )
                            }
                        }
                    }
                }
            }
        }

        // Toast Notification Banner
        Rectangle {
            visible: mainView.toastMessage.length > 0
            anchors.bottom: parent.bottom
            anchors.bottomMargin: units.gu(8)
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - units.gu(4), toastLbl.implicitWidth + units.gu(4))
            height: units.gu(4.6)
            radius: height / 2
            color: "#EE1E293B"
            border.width: units.dp(1)
            border.color: "#EF4444"
            z: 99

            Label {
                id: toastLbl
                anchors.centerIn: parent
                text: mainView.toastMessage
                fontSize: "small"
                color: "#FCA5A5"
            }

            Timer {
                id: toastTimer
                interval: 4000
                repeat: false
                onTriggered: mainView.toastMessage = ""
            }
        }
    }
}
