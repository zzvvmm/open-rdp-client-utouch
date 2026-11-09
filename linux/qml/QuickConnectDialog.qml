import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import OpenRdp 1.0

Dialog {
    id: root
    objectName: "quickConnectDialog"
    anchors.centerIn: parent
    modal: true
    width: Math.min(480, parent.width - 40)
    title: qsTr("Quick Connect")
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    property var accounts: []
    property bool busy: false
    property string errorMessage: ""
    signal connectRequested(string host, string accountId)
    onOpened: {
        errorMessage = "";
        busy = false;
        host.forceActiveFocus();
    }
    function complete(result) {
        busy = false;
        if (result.ok)
            close();
        else
            errorMessage = result.message || "";
    }
    contentItem: ColumnLayout {
        spacing: 12
        Label {
            text: qsTr("Connect once. Save the PC later if you need it again.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            color: Design.secondaryText
        }
        Label {
            text: qsTr("Hostname or IP address")
        }
        TextField {
            id: host
            objectName: "quickConnectHost"
            Layout.fillWidth: true
            implicitHeight: 48
            placeholderText: "work-pc.local:3389"
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            onAccepted: connectButton.clicked()
        }
        Label {
            text: qsTr("Saved account")
        }
        ComboBox {
            id: account
            Layout.fillWidth: true
            implicitHeight: 48
            textRole: "displayName"
            model: [{
                    "id": "",
                    "displayName": qsTr("Ask every time")
                }].concat(root.accounts)
        }
        Label {
            text: root.errorMessage
            visible: text.length > 0
            color: Design.danger
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            textFormat: Text.PlainText
        }
        RowLayout {
            Item {
                Layout.fillWidth: true
            }
            ActionButton {
                text: qsTr("Cancel")
                enabled: !root.busy
                onClicked: root.reject()
            }
            ActionButton {
                id: connectButton
                objectName: "quickConnectSubmit"
                text: root.busy ? qsTr("Connecting…") : qsTr("Connect")
                primary: true
                enabled: !root.busy && host.text.trim().length > 0
                onClicked: {
                    if (!enabled)
                        return;
                    root.busy = true;
                    root.connectRequested(host.text.trim(), account.model[account.currentIndex].id);
                }
            }
        }
    }
}
