import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import OpenRdp 1.0

ApplicationWindow {
    id: window
    objectName: "desktopWindow"
    width: 1100
    height: 760
    minimumWidth: 800
    minimumHeight: 600
    visible: true
    title: qsTr("Open RDP Client")
    font.pixelSize: Design.textSize
    property alias appState: state
    property alias editor: pcEditor
    property alias sessionView: session
    readonly property bool modalOpen: pcEditor.visible || credentials.visible || certificate.visible || accounts.editorVisible || quickConnect.visible || replaceSession.visible || saveTemporary.visible || devices.modalOpen
    palette.window: state.isDarkMode ? "#11151c" : "#f3f5f8"
    palette.windowText: state.isDarkMode ? "#f3f6fa" : "#1b2028"
    palette.base: state.isDarkMode ? "#1c2331" : "#ffffff"
    palette.alternateBase: state.isDarkMode ? "#171c26" : "#e8edf4"
    palette.text: state.isDarkMode ? "#f3f6fa" : "#1b2028"
    palette.button: state.isDarkMode ? "#263042" : "#e2e8f0"
    palette.buttonText: state.isDarkMode ? "#f3f6fa" : "#1b2028"
    palette.placeholderText: state.isDarkMode ? "#9ba7b8" : "#5a6577"
    palette.highlight: "#0078d4"
    palette.highlightedText: "white"

    Binding {
        target: Design
        property: "darkMode"
        value: state.isDarkMode
    }
    PcLibrary {
        id: library
        profiles: state.profilesList
    }

    function acceptDemoCertificate() {
        if (state.pendingCertPrompt && state.pendingCertPrompt.host === "demo.local") {
            state.sendAction({
                    "action": "respond_certificate",
                    "decision": "trust_once"
                });
            state.pendingCertPrompt = null;
        }
    }
    function toggleFullscreen() {
        visibility = visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen;
        session.restoreFocus();
    }
    function startDemo() {
        for (var i = 0; i < state.profilesList.length; ++i) {
            if (state.profilesList[i].isDemo) {
                state.connectToProfile(state.profilesList[i].id, "", "");
                return;
            }
        }
    }
    Shortcut {
        sequences: ["Ctrl+Alt+Return", "Ctrl+Alt+Enter"]
        onActivated: window.toggleFullscreen()
    }
    onClosing: state.sendAction({
            "action": "disconnect_session"
        })

    AppState {
        id: state
        objectName: "appState"
        width: session.viewportWidth
        height: session.viewportHeight
        onFrameUpdated: session.refreshCanvas()
    }
    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            visible: !state.inSessionView
            Layout.preferredWidth: window.width < 980 ? 88 : 208
            Layout.fillHeight: true
            color: Design.navigation
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                Image {
                    source: "qrc:/assets/logo.svg"
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    visible: window.width >= 980
                    text: qsTr("Open RDP Client")
                    font.bold: true
                    font.pixelSize: 18
                    Layout.alignment: Qt.AlignHCenter
                }
                Item {
                    Layout.preferredHeight: 24
                }
                Repeater {
                    model: [{
                            "key": "pcs",
                            "label": qsTr("PCs"),
                            "icon": "pcs"
                        }, {
                            "key": "accounts",
                            "label": qsTr("Accounts"),
                            "icon": "accounts"
                        }, {
                            "key": "settings",
                            "label": qsTr("Settings"),
                            "icon": "settings"
                        }]
                    ActionButton {
                        required property var modelData
                        Layout.fillWidth: true
                        height: 52
                        text: window.width < 980 ? "" : modelData.label
                        accessibleName: modelData.label
                        iconSource: "qrc:/assets/icons/" + modelData.icon + ".svg"
                        selected: state.currentTab === modelData.key
                        onClicked: state.currentTab = modelData.key
                        ToolTip.text: modelData.label
                        ToolTip.visible: activeFocus && window.width < 980
                    }
                }
                Item {
                    Layout.fillHeight: true
                }
                ActionButton {
                    visible: state.hasActiveSession
                    Layout.fillWidth: true
                    text: window.width < 980 ? "↗" : qsTr("Return to session")
                    accessibleName: qsTr("Return to session")
                    selected: true
                    onClicked: state.inSessionView = true
                }
                Label {
                    text: state.appVersion
                    color: Design.secondaryText
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            DevicesPage {
                id: devices
                appState: state
                settings: state.appSettings
                sessionStage: state.sessionStage
                onQuickConnectRequested: quickConnect.open()
                anchors.fill: parent
                visible: !state.inSessionView && state.currentTab === "pcs"
                profiles: state.profilesList
                activeProfileId: state.activeProfileId
                onConnectRequested: function (id) {
                    state.connectToProfile(id, "", "");
                }
                onEditRequested: function (pc) {
                    pcEditor.openForEdit(pc);
                }
                onAddRequested: pcEditor.openForNew(state.appSettings)
                onDispatchAction: function (payload) {
                    state.sendAction(payload);
                }
            }
            AccountsPage {
                id: accounts
                anchors.fill: parent
                visible: !state.inSessionView && state.currentTab === "accounts"
                accounts: state.accountsList
                knownCerts: state.knownCertsList
                onDispatchAction: function (payload) {
                    if (payload.action === "save_account")
                        state.submitAction(payload, function (result) {
                                accounts.completeSave(result);
                            });
                    else
                        state.sendAction(payload);
                }
            }
            SettingsPage {
                anchors.fill: parent
                visible: !state.inSessionView && state.currentTab === "settings"
                settings: state.appSettings
                appVersion: state.appVersion
                onDispatchAction: function (payload) {
                    state.sendAction(payload);
                }
            }
            SessionPage {
                id: session
                anchors.fill: parent
                visible: state.inSessionView
                appState: window.appState
                blocked: window.modalOpen
                fullscreen: window.visibility === Window.FullScreen
                onFullscreenRequested: window.toggleFullscreen()
                onSavePcRequested: {
                    temporaryName.text = state.activePcTitle;
                    saveTemporary.errorMessage = "";
                    saveTemporary.open();
                }
            }
        }
    }
    PcEditorDialog {
        id: pcEditor
        accounts: state.accountsList
        groups: library.groupNames
        onSaveRequested: function (payload) {
            state.submitAction(payload, function (result) {
                    pcEditor.completeSave(result);
                });
        }
        onConnectRequested: function (id) {
            state.connectToProfile(id, "", "");
        }
    }
    QuickConnectDialog {
        id: quickConnect
        accounts: state.accountsList
        onConnectRequested: function (host, accountId) {
            state.quickConnect(host, accountId, function (result) {
                    quickConnect.complete(result);
                });
        }
    }
    Dialog {
        id: replaceSession
        objectName: "replaceSessionDialog"
        anchors.centerIn: parent
        modal: true
        title: qsTr("Replace the active session?")
        width: Math.min(440, window.width - 40)
        visible: state.replacementPromptVisible
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            text: qsTr("The current session will disconnect when the new connection starts.")
        }
        onAccepted: state.confirmReplacement()
        onRejected: state.cancelReplacement()
    }
    Dialog {
        id: saveTemporary
        anchors.centerIn: parent
        modal: true
        title: qsTr("Save this PC")
        width: Math.min(460, window.width - 40)
        property string errorMessage: ""
        property bool busy: false
        contentItem: ColumnLayout {
            Label {
                text: qsTr("Friendly name")
            }
            TextField {
                id: temporaryName
                Layout.fillWidth: true
                implicitHeight: 48
            }
            Label {
                text: qsTr("Group")
            }
            ComboBox {
                id: temporaryGroup
                editable: true
                model: ["Saved PCs"].concat(library.groupNames.filter(function (name) {
                            return name !== "Saved PCs";
                        }))
                Layout.fillWidth: true
                implicitHeight: 48
            }
            Label {
                text: saveTemporary.errorMessage
                visible: text.length > 0
                color: Design.danger
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            ActionButton {
                text: qsTr("Save PC")
                primary: true
                enabled: !saveTemporary.busy
                onClicked: {
                    saveTemporary.busy = true;
                    state.submitAction({
                            "action": "save_temporary_pc",
                            "friendlyName": temporaryName.text,
                            "groupName": temporaryGroup.editText
                        }, function (result) {
                            saveTemporary.busy = false;
                            if (result.ok)
                                saveTemporary.close();
                            else
                                saveTemporary.errorMessage = result.message;
                        });
                }
            }
        }
    }
    Dialog {
        id: credentials
        objectName: "credentialsDialog"
        anchors.centerIn: parent
        width: Math.min(460, window.width - 40)
        title: qsTr("Sign in to ") + state.credPcTitle
        modal: true
        visible: state.showCredPrompt
        standardButtons: Dialog.Ok | Dialog.Cancel
        onOpened: username.forceActiveFocus()
        onAccepted: {
            state.credUsername = username.text.trim();
            state.credPassword = password.text;
            state.submitCredentials();
            password.clear();
            state.credPassword = "";
        }
        onRejected: {
            state.cancelCredentials();
            password.clear();
            state.credPassword = "";
        }
        onVisibleChanged: if (visible && standardButton(Dialog.Ok))
            standardButton(Dialog.Ok).enabled = Qt.binding(function () {
                    return username.text.trim().length > 0;
                })
        contentItem: ColumnLayout {
            TextField {
                id: username
                objectName: "credentialUsername"
                Layout.fillWidth: true
                text: state.credUsername
                placeholderText: qsTr("DOMAIN\\user or user@domain")
            }
            TextField {
                id: password
                objectName: "credentialPassword"
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: qsTr("Password")
            }
        }
    }
    CertificateDialog {
        id: certificate
        prompt: state.pendingCertPrompt
        onDecision: function (value) {
            state.sendAction({
                    "action": "respond_certificate",
                    "decision": value
                });
            state.pendingCertPrompt = null;
        }
    }
    Popup {
        x: (window.width - width) / 2
        y: window.height - height - 28
        visible: state.toastMessage.length > 0
        closePolicy: Popup.NoAutoClose
        contentItem: Label {
            text: state.toastMessage
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            width: Math.min(600, window.width - 80)
        }
    }
}
