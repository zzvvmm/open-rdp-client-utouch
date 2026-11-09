import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import OpenRdp 1.0

Pane {
    id: root
    property var accounts: []
    property var knownCerts: []
    readonly property bool editorVisible: editor.visible
    property string editId: ""
    property bool busy: false
    property string validationError: ""
    signal dispatchAction(var payload)
    function editAccount(account) {
        editId = account.id || "";
        username.text = account.username || "";
        domain.text = account.domain || "";
        displayName.text = account.displayName || "";
        password.clear();
        validationError = "";
        busy = false;
        editor.open();
        username.forceActiveFocus();
    }
    function saveAccount() {
        if (!username.text.trim()) {
            validationError = qsTr("Enter a username.");
            return false;
        }
        if (busy)
            return false;
        busy = true;
        dispatchAction({
                "action": "save_account",
                "id": editId,
                "username": username.text.trim(),
                "domain": domain.text.trim(),
                "displayName": displayName.text.trim(),
                "password": password.text
            });
        password.clear();
        return true;
    }
    function completeSave(result) {
        busy = false;
        if (result.ok)
            editor.close();
        else
            validationError = result.message || qsTr("Could not save account.");
    }
    padding: 32
    background: Rectangle {
        color: Design.background
    }
    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            width: parent.width
            spacing: 16
            RowLayout {
                Label {
                    text: qsTr("Saved accounts")
                    font.pixelSize: 30
                    font.bold: true
                    Layout.fillWidth: true
                }
                Button {
                    objectName: "addAccountButton"
                    text: qsTr("Add account")
                    onClicked: root.editAccount({})
                }
            }
            Label {
                text: qsTr("Credentials for your remote PCs, stored in the encrypted local vault.")
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.65
            }
            Repeater {
                model: root.accounts
                Frame {
                    background: Rectangle {
                        color: Design.surface
                        radius: 12
                        border.color: Design.border
                    }
                    padding: 16
                    required property var modelData
                    Layout.fillWidth: true
                    RowLayout {
                        anchors.fill: parent
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelData.displayName
                                textFormat: Text.PlainText
                                font.bold: true
                            }
                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelData.qualifiedUsername + (modelData.hasSavedPassword ? qsTr(" · Password saved") : qsTr(" · Ask for password"))
                                textFormat: Text.PlainText
                            }
                        }
                        Button {
                            text: qsTr("Edit")
                            onClicked: root.editAccount(modelData)
                        }
                        Button {
                            text: qsTr("Delete")
                            onClicked: root.dispatchAction({
                                    "action": "delete_account",
                                    "id": modelData.id
                                })
                        }
                    }
                }
            }
            Label {
                visible: root.accounts.length === 0
                text: qsTr("No saved accounts yet.")
            }
            Label {
                text: qsTr("Trusted certificates")
                font.pixelSize: 22
                font.bold: true
                Layout.topMargin: 16
            }
            Label {
                text: qsTr("Pinned SHA-256 fingerprints for your remote PCs.")
                opacity: 0.65
            }
            Repeater {
                model: root.knownCerts
                Frame {
                    background: Rectangle {
                        color: Design.surface
                        radius: 12
                        border.color: Design.border
                    }
                    padding: 16
                    required property var modelData
                    Layout.fillWidth: true
                    RowLayout {
                        anchors.fill: parent
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelData.hostPort + " (" + modelData.subjectCn + ")"
                                textFormat: Text.PlainText
                                font.bold: true
                            }
                            Label {
                                Layout.fillWidth: true
                                text: modelData.sha256Fingerprint
                                textFormat: Text.PlainText
                                wrapMode: Text.WrapAnywhere
                                font.family: "monospace"
                            }
                            Label {
                                text: qsTr("Valid until: ") + modelData.validUntil
                                textFormat: Text.PlainText
                            }
                        }
                        Button {
                            text: qsTr("Revoke")
                            onClicked: root.dispatchAction({
                                    "action": "remove_known_cert",
                                    "hostPort": modelData.hostPort
                                })
                        }
                    }
                }
            }
            Label {
                visible: root.knownCerts.length === 0
                text: qsTr("Certificates are shown here after you trust a remote PC.")
            }
        }
    }
    Dialog {
        id: editor
        objectName: "accountEditor"
        anchors.centerIn: parent
        width: Math.min(480, root.width - 40)
        modal: true
        closePolicy: root.busy ? Popup.NoAutoClose : Popup.CloseOnEscape
        title: root.editId ? qsTr("Edit account") : qsTr("New account")
        onClosed: password.clear()
        footer: DialogButtonBox {
            ActionButton {
                text: qsTr("Cancel")
                enabled: !root.busy
                onClicked: editor.reject()
            }
            ActionButton {
                text: qsTr("Save account")
                primary: true
                enabled: !root.busy
                onClicked: root.saveAccount()
            }
        }
        contentItem: ColumnLayout {
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: root.validationError
                visible: text.length > 0
                color: "#e85c5c"
            }
            TextField {
                id: username
                implicitHeight: 48
                objectName: "accountUsername"
                Layout.fillWidth: true
                placeholderText: qsTr("Username or DOMAIN\\user")
            }
            TextField {
                id: domain
                implicitHeight: 48
                Layout.fillWidth: true
                placeholderText: qsTr("Domain (optional)")
            }
            TextField {
                id: displayName
                implicitHeight: 48
                Layout.fillWidth: true
                placeholderText: qsTr("Display name (optional)")
            }
            TextField {
                id: password
                implicitHeight: 48
                objectName: "accountPassword"
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: root.editId ? qsTr("Password (leave blank to keep existing)") : qsTr("Password (optional)")
            }
        }
    }
}
