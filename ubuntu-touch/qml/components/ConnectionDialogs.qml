import QtQuick 2.12
import Lomiri.Components 1.3
import OpenRdp 1.0 as Shared

Rectangle {
    id: root
    property var appState
    property var accounts: []
    property var groups: []
    property string mode: ""
    property bool busy: false
    property string errorMessage: ""
    property string accountId: ""
    readonly property bool replacing: appState ? appState.replacementPromptVisible : false
    visible: mode.length > 0 || replacing
    anchors.fill: parent
    z: 84
    color: "#CC0B0E14"
    function openQuick() {
        mode = "quick";
        busy = false;
        errorMessage = "";
        accountId = "";
        host.forceActiveFocus();
    }
    function openSave() {
        mode = "save";
        busy = false;
        errorMessage = "";
        friendly.text = appState.activePcTitle;
        group.text = "Saved PCs";
    }
    function complete(result) {
        busy = false;
        if (result.ok)
            mode = "";
        else
            errorMessage = result.message || "";
    }
    MouseArea {
        anchors.fill: parent
    }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 480)
        height: Math.min(parent.height - 32, replacing ? 260 : 500)
        radius: 12
        color: Shared.Design.surface
        Column {
            id: content
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            Label {
                width: parent.width
                wrapMode: Text.Wrap
                color: Shared.Design.text
                fontSize: "large"
                font.bold: true
                text: root.replacing ? i18n.tr("Replace the active session?") : root.mode === "quick" ? i18n.tr("Quick Connect") : i18n.tr("Save this PC")
            }
            Flickable {
                width: parent.width
                height: parent.height - content.children[0].height - 72
                clip: true
                contentWidth: width
                contentHeight: fields.implicitHeight
                Column {
                    id: fields
                    width: parent.width
                    spacing: 12
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: Shared.Design.secondaryText
                        text: root.replacing ? i18n.tr("The current session will disconnect when the new connection starts.") : root.mode === "quick" ? i18n.tr("Connect once. Save the PC later if you need it again.") : i18n.tr("Add this connection to your saved PCs.")
                    }
                    Column {
                        width: parent.width
                        spacing: 12
                        visible: !root.replacing && root.mode === "quick"
                        TextField {
                            id: host
                            objectName: "quickConnectHost"
                            width: parent.width
                            height: 48
                            placeholderText: i18n.tr("Hostname or IP address, optionally :port")
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        }
                        Label {
                            text: i18n.tr("Saved account")
                            color: Shared.Design.text
                        }
                        Flow {
                            width: parent.width
                            spacing: 8
                            Shared.ActionButton {
                                text: i18n.tr("Ask every time")
                                selected: root.accountId === ""
                                onClicked: root.accountId = ""
                            }
                            Repeater {
                                model: root.accounts
                                delegate: Shared.ActionButton {
                                    text: modelData.displayName
                                    selected: root.accountId === modelData.id
                                    onClicked: root.accountId = modelData.id
                                }
                            }
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 12
                        visible: !root.replacing && root.mode === "save"
                        Label {
                            text: i18n.tr("Friendly name")
                            color: Shared.Design.text
                        }
                        TextField {
                            id: friendly
                            width: parent.width
                            height: 48
                        }
                        Label {
                            text: i18n.tr("Group")
                            color: Shared.Design.text
                        }
                        TextField {
                            id: group
                            width: parent.width
                            height: 48
                        }
                        Flow {
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: root.groups
                                delegate: Shared.ActionButton {
                                    text: modelData
                                    onClicked: group.text = modelData
                                }
                            }
                        }
                    }
                    Label {
                        width: parent.width
                        text: root.errorMessage
                        visible: text.length > 0
                        wrapMode: Text.Wrap
                        color: Shared.Design.danger
                        textFormat: Text.PlainText
                    }
                }
            }
            Row {
                width: parent.width
                spacing: 8
                Shared.ActionButton {
                    text: i18n.tr("Cancel")
                    width: (parent.width - 8) / 2
                    enabled: !root.busy || root.replacing
                    onClicked: {
                        if (root.replacing)
                            root.appState.cancelReplacement();
                        else
                            root.mode = "";
                    }
                }
                Shared.ActionButton {
                    objectName: "quickConnectSubmit"
                    width: (parent.width - 8) / 2
                    primary: true
                    text: root.replacing ? i18n.tr("Replace session") : root.mode === "save" ? i18n.tr("Save PC") : i18n.tr("Connect")
                    enabled: root.replacing || (!root.busy && (root.mode !== "quick" || host.text.trim().length > 0))
                    onClicked: {
                        Qt.inputMethod.commit();
                        if (root.replacing) {
                            root.appState.confirmReplacement();
                            return;
                        }
                        root.busy = true;
                        if (root.mode === "quick")
                            root.appState.quickConnect(host.text.trim(), root.accountId, function (result) {
                                    root.complete(result);
                                });
                        else
                            root.appState.submitAction({
                                    "action": "save_temporary_pc",
                                    "friendlyName": friendly.text,
                                    "groupName": group.text
                                }, function (result) {
                                    root.complete(result);
                                });
                    }
                }
            }
        }
    }
}
