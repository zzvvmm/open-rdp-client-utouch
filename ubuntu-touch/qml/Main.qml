import QtQuick 2.12
import Lomiri.Components 1.3
import RdpClient 1.0
import "pages"
import "components"
import OpenRdp 1.0 as Shared

MainView {
    id: mainView
    objectName: "mainView"
    applicationName: "rdp-client-ut.zzvvmm"
    automaticOrientation: true
    anchorToKeyboard: true

    width: units.gu(50)
    height: units.gu(88)

    property alias currentTab: appState.currentTab
    property alias inSessionView: appState.inSessionView
    property alias profilesList: appState.profilesList
    property alias accountsList: appState.accountsList
    property alias knownCertsList: appState.knownCertsList
    property alias appSettings: appState.appSettings
    property alias settingsLoaded: appState.settingsLoaded
    property alias appVersion: appState.appVersion
    property alias appArchitecture: appState.appArchitecture
    property alias appFramework: appState.appFramework
    property alias activeProfileId: appState.activeProfileId
    property alias activePc: appState.activePc
    property alias activePcTitle: appState.activePcTitle
    property alias sessionStage: appState.sessionStage
    property alias sessionStageDetail: appState.sessionStageDetail
    property alias touchMode: appState.touchMode
    property alias remoteWidth: appState.remoteWidth
    property alias remoteHeight: appState.remoteHeight
    property alias cursorX: appState.cursorX
    property alias cursorY: appState.cursorY
    property alias currentFps: appState.currentFps
    property alias ctrlState: appState.ctrlState
    property alias altState: appState.altState
    property alias shiftState: appState.shiftState
    property alias winState: appState.winState
    property alias pendingCertPrompt: appState.pendingCertPrompt
    property alias showCredPrompt: appState.showCredPrompt
    property alias credProfileId: appState.credProfileId
    property alias credPcTitle: appState.credPcTitle
    property alias credUsername: appState.credUsername
    property alias credPassword: appState.credPassword
    property alias toastMessage: appState.toastMessage
    property alias isDarkMode: appState.isDarkMode

    function sendAction(payload) { appState.sendAction(payload) }
    function showToast(message) { appState.showToast(message) }
    function connectToProfile(id, username, password) { appState.connectToProfile(id, username, password) }
    Shared.AppState {
        id: appState
        bridge: RdpBridge
        anchors.fill: parent
        onFrameUpdated: sessionPage.notifyFrameUpdated()
    }

    UpdateManager {
        id: updates
        ready: mainView.settingsLoaded
        installedVersion: mainView.appVersion
        architecture: mainView.appArchitecture
        framework: mainView.appFramework
        automaticEnabled: mainView.appSettings.autoCheckUpdates !== false
        skippedVersion: mainView.appSettings.skippedUpdateVersion || ""
        lastCheckedAt: mainView.appSettings.lastUpdateCheckEpoch || 0
        appActive: Qt.application.state === Qt.ApplicationActive
        canPrompt: !mainView.inSessionView && !mainView.showCredPrompt
                   && mainView.pendingCertPrompt === null && !pcEditor.visible
        onSavePreferences: {
            var payload = { action: "save_settings" }
            for (var key in patch) payload[key] = patch[key]
            mainView.sendAction(payload)
        }
        onOpenStoreRequested: updates.storeOpened(Qt.openUrlExternally(uri))
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
                appVersion: mainView.appVersion
                updateStatus: updates.status
                updateChecking: updates.checking
                updateReady: updates.ready
                skippedVersion: updates.skippedVersion
                onCheckUpdatesRequested: updates.checkForUpdates(true)
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
            dynamicResolution: mainView.activePc !== null && mainView.activePc.resolutionPreset === "dynamic"
            desktopScaleFactor: mainView.activePc ? mainView.activePc.scaleFactor || 100 : 100
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

        UpdatePrompt {
            visible: updates.promptVisible
            version: updates.availableUpdate ? updates.availableUpdate.version : ""
            changelog: updates.availableUpdate ? updates.availableUpdate.changelog : ""
            installedVersion: mainView.appVersion
            darkMode: mainView.isDarkMode
            openFailed: updates.status === "openFailed"
            onUpdateNow: updates.updateNow()
            onUpdateLater: updates.updateLater()
            onSkipVersion: updates.skipVersion()
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

        }
    }
}
