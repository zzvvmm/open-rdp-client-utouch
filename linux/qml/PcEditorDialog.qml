import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Dialog {
    id: root
    objectName: "pcEditor"
    anchors.centerIn: parent
    width: Math.min(600, parent.width - 40)
    height: Math.min(670, parent.height - 40)
    modal: true
    title: editId ? qsTr("Edit remote PC") : qsTr("Add remote PC")
    standardButtons: Dialog.Save | Dialog.Cancel
    property var accounts: []
    property string editId: ""
    property string validationError: ""
    property var resolutions: ["native", "dynamic", "1920x1080", "1600x900", "1366x768", "1280x720"]
    signal saveRequested(var payload)
    function openForNew(settings) {
        openForEdit({
                "resolutionPreset": settings.defaultResolution,
                "scaleFactor": settings.defaultScaleFactor,
                "defaultTouchMode": settings.defaultTouchMode,
                "audioMode": settings.defaultAudioMode,
                "clipboardRedirection": settings.defaultClipboardEnabled
            });
    }
    function openForEdit(pc) {
        editId = pc.id || "";
        host.text = pc.address || pc.hostname || "";
        friendly.text = pc.friendlyName || "";
        group.text = pc.groupName || "Saved PCs";
        account.currentIndex = Math.max(0, account.model.findIndex(function (a) {
                    return a.id === (pc.accountId || "");
                }));
        resolution.currentIndex = Math.max(0, resolutions.indexOf(pc.resolutionPreset || "native"));
        scale.value = pc.scaleFactor || 100;
        touch.currentIndex = pc.defaultTouchMode === "mouse_pointer" ? 1 : 0;
        audio.currentIndex = Math.max(0, audio.keys.indexOf(pc.audioMode || "play_on_device"));
        clipboard.checked = pc.clipboardRedirection !== false;
        nla.checked = pc.enableNla !== false;
        validationError = "";
        open();
        host.forceActiveFocus();
    }
    function save() {
        if (!host.text.trim()) {
            validationError = qsTr("Enter a hostname or IP address.");
            return false;
        }
        saveRequested({
                "action": "save_pc",
                "id": editId,
                "hostInput": host.text.trim(),
                "friendlyName": friendly.text.trim(),
                "groupName": group.text.trim(),
                "accountId": account.model[account.currentIndex].id,
                "resolutionPreset": resolutions[resolution.currentIndex],
                "scaleFactor": scale.value,
                "defaultTouchMode": touch.currentIndex === 1 ? "mouse_pointer" : "direct_touch",
                "audioMode": audio.keys[audio.currentIndex],
                "clipboardRedirection": clipboard.checked,
                "enableNla": nla.checked,
                "enableTls": true
            });
        close();
        return true;
    }
    // A custom handler keeps invalid forms open instead of accepting the dialog.
    footer: DialogButtonBox {
        standardButtons: Dialog.Save | Dialog.Cancel
        onAccepted: root.save()
        onRejected: root.reject()
    }
    contentItem: ScrollView {
        clip: true
        contentWidth: availableWidth
        ColumnLayout {
            width: parent.width
            spacing: 10
            Label {
                text: root.validationError
                visible: text.length > 0
                color: "#e85c5c"
            }
            Label {
                text: qsTr("Hostname or IP address, optionally :port")
            }
            TextField {
                id: host
                objectName: "pcHostField"
                Layout.fillWidth: true
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                placeholderText: "work-pc.local:3389"
            }
            Label {
                text: qsTr("Friendly name")
            }
            TextField {
                id: friendly
                objectName: "pcFriendlyName"
                Layout.fillWidth: true
            }
            Label {
                text: qsTr("Group")
            }
            TextField {
                id: group
                Layout.fillWidth: true
            }
            Label {
                text: qsTr("Account")
            }
            ComboBox {
                id: account
                objectName: "pcAccount"
                Layout.fillWidth: true
                textRole: "displayName"
                model: [{
                        "id": "",
                        "displayName": qsTr("Ask every time")
                    }].concat(root.accounts)
            }
            Label {
                text: qsTr("Resolution")
            }
            ComboBox {
                id: resolution
                objectName: "pcResolution"
                Layout.fillWidth: true
                model: [qsTr("Match viewport"), qsTr("Dynamic (fit window)"), "1920×1080", "1600×900", "1366×768", "1280×720"]
            }
            RowLayout {
                Label {
                    text: qsTr("Remote scaling (%)")
                }
                SpinBox {
                    id: scale
                    from: 100
                    to: 200
                    stepSize: 25
                }
            }
            RowLayout {
                Label {
                    text: qsTr("Touch input")
                }
                ComboBox {
                    id: touch
                    model: [qsTr("Direct touch"), qsTr("Virtual trackpad")]
                }
            }
            Label {
                text: qsTr("Audio")
            }
            ComboBox {
                id: audio
                Layout.fillWidth: true
                property var keys: ["play_on_device", "play_on_remote", "disabled"]
                model: [qsTr("Play locally"), qsTr("Play on remote PC"), qsTr("Disabled")]
            }
            CheckBox {
                id: clipboard
                text: qsTr("Synchronize clipboard text")
            }
            CheckBox {
                id: nla
                text: qsTr("Use Network Level Authentication (NLA)")
            }
        }
    }
}
