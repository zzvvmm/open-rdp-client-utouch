import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Dialog {
    id: root
    objectName: "certificateDialog"
    property var prompt: null
    signal decision(string value)
    anchors.centerIn: parent
    width: Math.min(620, parent.width - 40)
    height: Math.min(540, parent.height - 40)
    visible: prompt !== null
    modal: true
    closePolicy: Popup.NoAutoClose
    title: prompt && prompt.isMismatchWarning ? qsTr("Certificate changed") : qsTr("Verify server certificate")
    contentItem: ScrollView {
        clip: true
        contentWidth: availableWidth
        ColumnLayout {
            width: parent.width
            spacing: 14
            Label {
                Layout.fillWidth: true
                text: root.prompt && root.prompt.isMismatchWarning ? qsTr("The server certificate differs from the certificate you trusted. Verify this change before sending credentials.") : qsTr("Verify this certificate before sending credentials to the remote PC.")
                wrapMode: Text.Wrap
                color: root.prompt && root.prompt.isMismatchWarning ? "#e85c5c" : palette.text
            }
            Label {
                Layout.fillWidth: true
                text: root.prompt ? root.prompt.statusReason || "" : ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                visible: text.length > 0
            }
            Repeater {
                model: [qsTr("Server"), qsTr("Subject"), qsTr("Issuer"), qsTr("Valid from"), qsTr("Valid until"), qsTr("SHA-256 fingerprint")]
                ColumnLayout {
                    required property int index
                    required property string modelData
                    Layout.fillWidth: true
                    Label {
                        text: modelData
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.prompt ? [root.prompt.host + ":" + root.prompt.port, root.prompt.subjectCn, root.prompt.issuerCn, root.prompt.validFrom, root.prompt.validUntil, root.prompt.sha256Fingerprint][index] || "" : ""
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        font.family: index === 5 ? "monospace" : Qt.application.font.family
                    }
                }
            }
        }
    }
    footer: DialogButtonBox {
        Button {
            text: qsTr("Reject")
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            onClicked: root.decision("reject")
        }
        Button {
            text: qsTr("Trust once")
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: root.decision("trust_once")
        }
        Button {
            text: qsTr("Trust always")
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: root.decision("trust_always")
        }
    }
}
