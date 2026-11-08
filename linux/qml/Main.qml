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
    property alias appState: state
    property alias editor: pcEditor
    property alias sessionView: session
    readonly property bool modalOpen: pcEditor.visible || credentials.visible || certificate.visible || accounts.editorVisible
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
        Pane {
            visible: !state.inSessionView
            Layout.preferredWidth: 190
            Layout.fillHeight: true
            ColumnLayout {
                anchors.fill: parent
                spacing: 12
                Image {
                    source: "qrc:/assets/logo.svg"
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                }
                Label {
                    text: qsTr("Open RDP Client")
                    font.bold: true
                    font.pixelSize: 18
                }
                Label {
                    text: qsTr("Remote Desktop")
                    opacity: 0.65
                }
                Repeater {
                    model: [{
                            "key": "pcs",
                            "label": qsTr("Saved PCs")
                        }, {
                            "key": "accounts",
                            "label": qsTr("Accounts and certificates")
                        }, {
                            "key": "settings",
                            "label": qsTr("Settings")
                        }]
                    Button {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.label
                        checkable: true
                        checked: state.currentTab === modelData.key
                        onClicked: state.currentTab = modelData.key
                    }
                }
                Item {
                    Layout.fillHeight: true
                }
                Button {
                    visible: state.activeProfileId.length > 0
                    text: qsTr("Return to session")
                    Layout.fillWidth: true
                    onClicked: state.inSessionView = true
                }
                Label {
                    text: qsTr("Version ") + state.appVersion
                    opacity: 0.6
                }
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            DevicesPage {
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
            }
        }
    }
    PcEditorDialog {
        id: pcEditor
        accounts: state.accountsList
        onSaveRequested: function (payload) {
            state.sendAction(payload);
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
            state.showCredPrompt = false;
            state.connectToProfile(state.credProfileId, username.text.trim(), password.text);
            password.clear();
            state.credPassword = "";
        }
        onRejected: {
            state.showCredPrompt = false;
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
