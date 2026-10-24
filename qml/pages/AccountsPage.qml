import QtQuick 2.12
import Lomiri.Components 1.3

Flickable {
    id: root

    property var accounts: []
    property var knownCerts: []
    property bool darkMode: true

    property bool showAccountEditor: false
    property string editAccountId: ""
    property string editUsername: ""
    property string editDomain: ""
    property string editDisplayName: ""
    property string editPassword: ""

    signal saveAccount(var payload)
    signal deleteAccount(string accountId)
    signal removeKnownCert(string hostPort)

    contentWidth: width
    contentHeight: mainCol.implicitHeight + units.gu(6)
    clip: true

    Column {
        id: mainCol
        width: parent.width - units.gu(4)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: units.gu(2)
        spacing: units.gu(2.2)

        // Section 1: User Accounts Header
        Row {
            width: parent.width
            Column {
                width: parent.width - units.gu(18)
                spacing: units.gu(0.3)
                Label {
                    text: i18n.tr("Saved User Accounts")
                    fontSize: "large"
                    font.bold: true
                    color: root.darkMode ? "#F3F6FA" : "#1B2028"
                }
                Label {
                    text: i18n.tr("Reusable Windows credentials stored in the encrypted local vault.")
                    fontSize: "small"
                    color: root.darkMode ? "#9BA7B8" : "#5A6577"
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }
            Button {
                width: units.gu(17)
                text: i18n.tr("+ Add Account")
                color: "#0078D4"
                onClicked: {
                    root.editAccountId = ""
                    root.editUsername = ""
                    root.editDomain = ""
                    root.editDisplayName = ""
                    root.editPassword = ""
                    root.showAccountEditor = true
                }
            }
        }

        // Inline Account Editor Card
        Rectangle {
            visible: root.showAccountEditor
            width: parent.width
            height: editorCol.implicitHeight + units.gu(3.2)
            radius: units.gu(1.4)
            color: root.darkMode ? "#1C2331" : "#FFFFFF"
            border.width: units.dp(1)
            border.color: "#0078D4"

            Column {
                id: editorCol
                width: parent.width - units.gu(3.2)
                anchors.centerIn: parent
                spacing: units.gu(1.2)

                Label {
                    text: root.editAccountId.length > 0 ? i18n.tr("Edit User Account") : i18n.tr("New User Account")
                    fontSize: "medium"
                    font.bold: true
                    color: root.darkMode ? "#F3F6FA" : "#1B2028"
                }

                TextField {
                    width: parent.width
                    text: root.editUsername
                    placeholderText: i18n.tr("Username (e.g. DOMAIN\\alice or alice@corp.local)")
                    onTextChanged: root.editUsername = text
                }

                TextField {
                    width: parent.width
                    text: root.editPassword
                    echoMode: TextInput.Password
                    placeholderText: root.editAccountId.length > 0
                                     ? i18n.tr("Password (leave blank to keep existing)")
                                     : i18n.tr("Password (optional)")
                    onTextChanged: root.editPassword = text
                }

                TextField {
                    width: parent.width
                    text: root.editDisplayName
                    placeholderText: i18n.tr("Friendly Label (optional, e.g. Work Domain Admin)")
                    onTextChanged: root.editDisplayName = text
                }

                Row {
                    spacing: units.gu(1)
                    Button {
                        text: i18n.tr("Save Account")
                        color: "#0078D4"
                        onClicked: {
                            if (root.editUsername.trim().length === 0) return
                            root.saveAccount({
                                action: "save_account",
                                id: root.editAccountId,
                                username: root.editUsername.trim(),
                                domain: root.editDomain.trim(),
                                displayName: root.editDisplayName.trim(),
                                password: root.editPassword
                            })
                            root.showAccountEditor = false
                        }
                    }
                    Button {
                        text: i18n.tr("Cancel")
                        color: root.darkMode ? "#263042" : "#E2E8F0"
                        onClicked: root.showAccountEditor = false
                    }
                }
            }
        }

        // Saved Accounts List
        Repeater {
            model: root.accounts
            delegate: Rectangle {
                width: mainCol.width
                height: units.gu(8)
                radius: units.gu(1.2)
                color: root.darkMode ? "#1C2331" : "#FFFFFF"
                border.width: units.dp(1)
                border.color: root.darkMode ? "#2B3548" : "#DCE2EC"

                Row {
                    anchors.fill: parent
                    anchors.margins: units.gu(1.5)
                    spacing: units.gu(1.5)

                    Rectangle {
                        width: units.gu(4.6)
                        height: units.gu(4.6)
                        radius: width / 2
                        color: "#0078D4"
                        anchors.verticalCenter: parent.verticalCenter
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2.4)
                            height: units.gu(2.4)
                            name: "contact"
                            color: "#FFFFFF"
                        }
                    }

                    Column {
                        width: parent.width - units.gu(21)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.gu(0.3)
                        Label {
                            text: modelData.displayName
                            fontSize: "medium"
                            font.bold: true
                            color: root.darkMode ? "#F3F6FA" : "#1B2028"
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Label {
                            text: modelData.qualifiedUsername + (modelData.hasSavedPassword ? " • Password saved in vault" : " • Prompt password")
                            fontSize: "small"
                            color: root.darkMode ? "#9BA7B8" : "#5A6577"
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Button {
                        width: units.gu(6.5)
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr("Edit")
                        color: root.darkMode ? "#263042" : "#E2E8F0"
                        onClicked: {
                            root.editAccountId = modelData.id
                            root.editUsername = modelData.qualifiedUsername
                            root.editDomain = modelData.domain
                            root.editDisplayName = modelData.displayName
                            root.editPassword = ""
                            root.showAccountEditor = true
                        }
                    }

                    Button {
                        width: units.gu(6.5)
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr("Delete")
                        color: "#3A1E24"
                        onClicked: root.deleteAccount(modelData.id)
                    }
                }
            }
        }

        Label {
            visible: root.accounts.length === 0 && !root.showAccountEditor
            text: i18n.tr("No saved accounts yet. Add one above to sign in automatically when connecting.")
            fontSize: "small"
            color: root.darkMode ? "#9BA7B8" : "#5A6577"
        }

        // Section 2: Trusted TLS Certificates (TOFU Known Hosts)
        Rectangle {
            width: parent.width
            height: units.dp(1)
            color: root.darkMode ? "#2B3548" : "#DCE2EC"
        }

        Column {
            width: parent.width
            spacing: units.gu(0.4)
            Label {
                text: i18n.tr("Trusted PC Certificates (TOFU)")
                fontSize: "large"
                font.bold: true
                color: root.darkMode ? "#F3F6FA" : "#1B2028"
            }
            Label {
                text: i18n.tr("Pinned SHA-256 TLS fingerprints for remote RDP servers.")
                fontSize: "small"
                color: root.darkMode ? "#9BA7B8" : "#5A6577"
            }
        }

        Repeater {
            model: root.knownCerts
            delegate: Rectangle {
                width: mainCol.width
                height: units.gu(9.5)
                radius: units.gu(1.2)
                color: root.darkMode ? "#1C2331" : "#FFFFFF"
                border.width: units.dp(1)
                border.color: root.darkMode ? "#2B3548" : "#DCE2EC"

                Row {
                    anchors.fill: parent
                    anchors.margins: units.gu(1.4)
                    spacing: units.gu(1.2)

                    Column {
                        width: parent.width - units.gu(11)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.gu(0.3)

                        Label {
                            text: modelData.hostPort + " (" + modelData.subjectCn + ")"
                            fontSize: "small"
                            font.bold: true
                            color: root.darkMode ? "#F3F6FA" : "#1B2028"
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Label {
                            text: modelData.sha256Fingerprint
                            fontSize: "x-small"
                            font.family: "Ubuntu Mono"
                            color: "#29B6F6"
                            elide: Text.ElideMiddle
                            width: parent.width
                        }

                        Label {
                            text: i18n.tr("Valid until: ") + modelData.validUntil
                            fontSize: "x-small"
                            color: root.darkMode ? "#9BA7B8" : "#5A6577"
                        }
                    }

                    Button {
                        width: units.gu(9)
                        anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr("Revoke")
                        color: "#3A1E24"
                        onClicked: root.removeKnownCert(modelData.hostPort)
                    }
                }
            }
        }

        Label {
            visible: root.knownCerts.length === 0
            text: i18n.tr("No certificates pinned yet. You will be prompted to inspect and trust certificates on first connection.")
            fontSize: "small"
            color: root.darkMode ? "#9BA7B8" : "#5A6577"
            wrapMode: Text.WordWrap
            width: parent.width
        }
    }
}
