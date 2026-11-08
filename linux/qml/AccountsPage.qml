import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Pane {
    id: root
    property var accounts: []
    property var knownCerts: []
    readonly property bool editorVisible: editor.visible
    property string editId: ""
    property string validationError: ""
    signal dispatchAction(var payload)
    function editAccount(account) {
        editId = account.id || "";
        username.text = account.username || "";
        domain.text = account.domain || "";
        displayName.text = account.displayName || "";
        password.clear();
        validationError = "";
        editor.open();
        username.forceActiveFocus();
    }
    function saveAccount() {
        if (!username.text.trim()) {
            validationError = qsTr("Enter a username.");
            return false;
        }
        dispatchAction({
                "action": "save_account",
                "id": editId,
                "username": username.text.trim(),
                "domain": domain.text.trim(),
                "displayName": displayName.text.trim(),
                "password": password.text
            });
        editor.close();
        password.clear();
        return true;
    }
    padding: 24
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
                    font.pixelSize: 26
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
                text: qsTr("Reusable credentials stored in the local vault.")
                opacity: 0.65
            }
            Repeater {
                model: root.accounts
                Frame {
                    required property var modelData
                    Layout.fillWidth: true
                    RowLayout {
                        anchors.fill: parent
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label {
                                text: modelData.displayName
                                textFormat: Text.PlainText
                                font.bold: true
                            }
                            Label {
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
                    required property var modelData
                    Layout.fillWidth: true
                    RowLayout {
                        anchors.fill: parent
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label {
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
        title: root.editId ? qsTr("Edit account") : qsTr("New account")
        onClosed: password.clear()
        footer: DialogButtonBox {
            standardButtons: Dialog.Save | Dialog.Cancel
            onAccepted: root.saveAccount()
            onRejected: editor.reject()
        }
        contentItem: ColumnLayout {
            Label {
                text: root.validationError
                visible: text.length > 0
                color: "#e85c5c"
            }
            TextField {
                id: username
                objectName: "accountUsername"
                Layout.fillWidth: true
                placeholderText: qsTr("Username or DOMAIN\\user")
            }
            TextField {
                id: domain
                Layout.fillWidth: true
                placeholderText: qsTr("Domain (optional)")
            }
            TextField {
                id: displayName
                Layout.fillWidth: true
                placeholderText: qsTr("Display name (optional)")
            }
            TextField {
                id: password
                objectName: "accountPassword"
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: root.editId ? qsTr("Password (leave blank to keep existing)") : qsTr("Password (optional)")
            }
        }
    }
}
