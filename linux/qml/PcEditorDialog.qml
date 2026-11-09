import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import OpenRdp 1.0

Dialog {
    id: root
    objectName: "pcEditor"
    anchors.centerIn: parent
    width: Math.min(600, parent.width - 40)
    height: Math.min(650, parent.height - 40)
    modal: true
    title: editId ? qsTr("Edit remote PC") : qsTr("Add remote PC")
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    property var accounts: []
    property var groups: []
    property string editId: ""
    property string validationError: ""
    property bool busy: false
    property bool pendingConnect: false
    property var resolutions: ["native", "dynamic", "1920x1080", "1600x900", "1366x768", "1280x720"]
    signal saveRequested(var payload)
    signal connectRequested(string id)
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
        group.editText = pc.groupName || "Saved PCs";
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
        busy = false;
        pendingConnect = false;
        sections.currentIndex = 0;
        open();
        host.forceActiveFocus();
    }
    function save(connectAfter) {
        Qt.inputMethod.commit();
        if (busy)
            return false;
        if (!host.text.trim()) {
            validationError = qsTr("Enter a hostname or IP address.");
            sections.currentIndex = 0;
            return false;
        }
        pendingConnect = connectAfter === true;
        busy = true;
        validationError = "";
        saveRequested({
                "action": "save_pc",
                "id": editId,
                "hostInput": host.text.trim(),
                "friendlyName": friendly.text.trim(),
                "groupName": group.editText.trim(),
                "accountId": account.model[account.currentIndex].id,
                "resolutionPreset": resolutions[resolution.currentIndex],
                "scaleFactor": scale.value,
                "defaultTouchMode": touch.currentIndex === 1 ? "mouse_pointer" : "direct_touch",
                "audioMode": audio.keys[audio.currentIndex],
                "clipboardRedirection": clipboard.checked,
                "enableNla": nla.checked,
                "enableTls": true
            });
        return true;
    }
    function completeSave(result) {
        busy = false;
        if (!result.ok) {
            validationError = result.message || qsTr("Could not save PC.");
            return;
        }
        close();
        if (pendingConnect && result.entityId)
            connectRequested(result.entityId);
    }
    footer: DialogButtonBox {
        ActionButton {
            text: qsTr("Cancel")
            enabled: !root.busy
            onClicked: root.reject()
        }
        ActionButton {
            objectName: "savePcButton"
            text: qsTr("Save")
            enabled: !root.busy
            selected: true
            onClicked: root.save(false)
        }
        ActionButton {
            objectName: "saveConnectPcButton"
            text: root.busy ? qsTr("Saving…") : qsTr("Save & Connect")
            enabled: !root.busy
            primary: true
            onClicked: root.save(true)
        }
    }
    contentItem: ColumnLayout {
        spacing: 16
        TabBar {
            id: sections
            Layout.fillWidth: true
            TabButton {
                text: qsTr("General")
                implicitHeight: 48
            }
            TabButton {
                text: qsTr("Display")
                implicitHeight: 48
            }
            TabButton {
                text: qsTr("Devices")
                implicitHeight: 48
            }
        }
        Label {
            text: root.validationError
            visible: text.length > 0
            color: Design.danger
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: parent.width
                spacing: 12
                ColumnLayout {
                    visible: sections.currentIndex === 0
                    Layout.fillWidth: true
                    spacing: 10
                    Label {
                        text: qsTr("Hostname or IP address, optionally :port")
                    }
                    TextField {
                        id: host
                        objectName: "pcHostField"
                        Layout.fillWidth: true
                        implicitHeight: 48
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
                        implicitHeight: 48
                        placeholderText: qsTr("A name you recognize")
                    }
                    Label {
                        text: qsTr("Group")
                    }
                    ComboBox {
                        id: group
                        Layout.fillWidth: true
                        implicitHeight: 48
                        editable: true
                        model: root.groups
                        selectTextByMouse: true
                    }
                    Label {
                        text: qsTr("Saved account")
                    }
                    ComboBox {
                        id: account
                        objectName: "pcAccount"
                        Layout.fillWidth: true
                        implicitHeight: 48
                        textRole: "displayName"
                        model: [{
                                "id": "",
                                "displayName": qsTr("Ask every time")
                            }].concat(root.accounts)
                    }
                    Label {
                        text: qsTr("Saved accounts are credentials for your remote PCs.")
                        color: Design.secondaryText
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
                ColumnLayout {
                    visible: sections.currentIndex === 1
                    Layout.fillWidth: true
                    spacing: 12
                    Label {
                        text: qsTr("Resolution")
                    }
                    ComboBox {
                        id: resolution
                        objectName: "pcResolution"
                        Layout.fillWidth: true
                        implicitHeight: 48
                        model: [qsTr("Match viewport"), qsTr("Dynamic (fit window)"), "1920×1080", "1600×900", "1366×768", "1280×720"]
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: qsTr("Dynamic updates the remote resolution when the session viewport changes. Fixed resolutions keep their configured size.")
                        color: Design.secondaryText
                    }
                    Label {
                        text: qsTr("Remote scaling (%)")
                    }
                    SpinBox {
                        id: scale
                        from: 100
                        to: 200
                        stepSize: 25
                        implicitHeight: 48
                    }
                }
                ColumnLayout {
                    visible: sections.currentIndex === 2
                    Layout.fillWidth: true
                    spacing: 12
                    Label {
                        text: qsTr("Touch input")
                    }
                    ComboBox {
                        id: touch
                        Layout.fillWidth: true
                        implicitHeight: 48
                        model: [qsTr("Direct touch"), qsTr("Virtual trackpad")]
                    }
                    Label {
                        text: qsTr("Audio")
                    }
                    ComboBox {
                        id: audio
                        Layout.fillWidth: true
                        implicitHeight: 48
                        property var keys: ["play_on_device", "play_on_remote", "disabled"]
                        model: [qsTr("Play locally"), qsTr("Play on remote PC"), qsTr("Disabled")]
                    }
                    CheckBox {
                        id: clipboard
                        text: qsTr("Synchronize clipboard text")
                        implicitHeight: 48
                    }
                    CheckBox {
                        id: nla
                        text: qsTr("Use Network Level Authentication (NLA)")
                        implicitHeight: 48
                    }
                }
            }
        }
    }
}
