import QtQuick 2.12
import Lomiri.Components 1.3
import OpenRdp 1.0 as Shared

Rectangle {
    id: root

    property bool active: false
    property bool darkMode: true
    property var accounts: []
    property var groups: []
    property string section: "general"
    property bool busy: false
    property bool pendingConnect: false

    property string editId: ""
    property string hostInput: ""
    property string friendlyName: ""
    property string groupName: "Saved PCs"
    property string accountId: ""
    property string resolutionPreset: "native"
    property int scaleFactor: 100
    property string defaultTouchMode: "direct_touch"
    property string audioMode: "play_on_device"
    property bool clipboardRedirection: true
    property bool enableNla: true
    property string validationError: ""

    signal saveRequested(var payload)
    signal cancelRequested
    signal connectRequested(string pcId)

    function save(connectAfter) {
        Qt.inputMethod.commit();
        if (busy)
            return false;
        if (!hostInput.trim()) {
            validationError = i18n.tr("Please enter a hostname or IP address.");
            section = "general";
            return false;
        }
        busy = true;
        pendingConnect = connectAfter === true;
        validationError = "";
        saveRequested({
                "action": "save_pc",
                "id": editId,
                "hostInput": hostInput.trim(),
                "friendlyName": friendlyName.trim(),
                "groupName": groupName.trim(),
                "accountId": accountId,
                "resolutionPreset": resolutionPreset,
                "scaleFactor": scaleFactor,
                "defaultTouchMode": defaultTouchMode,
                "audioMode": audioMode,
                "clipboardRedirection": clipboardRedirection,
                "enableNla": enableNla,
                "enableTls": true
            });
        return true;
    }
    function completeSave(result) {
        busy = false;
        if (!result.ok) {
            validationError = result.message || i18n.tr("Could not save PC.");
            return;
        }
        active = false;
        if (pendingConnect && result.entityId)
            connectRequested(result.entityId);
    }

    function openForNew(defaultRes, defaultScale, defaultTouch, defaultAudio, defaultClip) {
        editId = "";
        hostInput = "";
        friendlyName = "";
        groupName = "Saved PCs";
        accountId = "";
        resolutionPreset = defaultRes || "native";
        scaleFactor = defaultScale || 100;
        defaultTouchMode = defaultTouch || "direct_touch";
        audioMode = defaultAudio || "play_on_device";
        clipboardRedirection = (defaultClip !== undefined) ? defaultClip : true;
        enableNla = true;
        validationError = "";
        busy = false;
        pendingConnect = false;
        section = "general";
        active = true;
    }

    function openForEdit(pc) {
        editId = pc.id || "";
        hostInput = pc.address || pc.hostname || "";
        friendlyName = pc.friendlyName || "";
        groupName = pc.groupName || "Saved PCs";
        accountId = pc.accountId || "";
        resolutionPreset = pc.resolutionPreset || "native";
        scaleFactor = pc.scaleFactor || 100;
        defaultTouchMode = pc.defaultTouchMode || "direct_touch";
        audioMode = pc.audioMode || "play_on_device";
        clipboardRedirection = (pc.clipboardRedirection !== undefined) ? pc.clipboardRedirection : true;
        enableNla = (pc.enableNla !== undefined) ? pc.enableNla : true;
        validationError = "";
        busy = false;
        pendingConnect = false;
        section = "general";
        active = true;
    }

    visible: active
    anchors.fill: parent
    color: "#CC0B0E14"
    z: 80

    MouseArea {
        anchors.fill: parent
        onClicked: {
        }
    }

    Rectangle {
        width: Math.min(parent.width - units.gu(3), units.gu(60))
        height: Math.min(parent.height - units.gu(4), units.gu(74))
        anchors.centerIn: parent
        radius: units.gu(1.6)
        color: root.darkMode ? "#1C2331" : "#FFFFFF"
        border.width: units.dp(1)
        border.color: root.darkMode ? "#2B3548" : "#DCE2EC"

        Column {
            anchors.fill: parent
            anchors.margins: units.gu(2)
            spacing: units.gu(1.2)

            // Header
            Row {
                width: parent.width
                Label {
                    width: parent.width - units.gu(10)
                    text: root.editId.length > 0 ? i18n.tr("Edit Remote PC") : i18n.tr("Add Remote PC")
                    fontSize: "large"
                    font.bold: true
                    color: root.darkMode ? "#F3F6FA" : "#1B2028"
                }
                Button {
                    width: units.gu(9)
                    text: i18n.tr("Close")
                    enabled: !root.busy
                    height: 48
                    color: root.darkMode ? "#263042" : "#E2E8F0"
                    onClicked: {
                        root.active = false;
                        root.cancelRequested();
                    }
                }
            }

            Rectangle {
                visible: root.validationError.length > 0
                width: parent.width
                height: Math.max(48, errorLabel.implicitHeight + 16)
                radius: units.gu(0.8)
                color: "#3A1E24"
                Label {
                    id: errorLabel
                    anchors.centerIn: parent
                    width: parent.width - 16
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: root.validationError
                    fontSize: "small"
                    color: "#FCA5A5"
                }
            }

            Flow {
                width: parent.width
                spacing: 4
                Repeater {
                    model: [{
                            "key": "general",
                            "label": i18n.tr("General")
                        }, {
                            "key": "display",
                            "label": i18n.tr("Display")
                        }, {
                            "key": "devices",
                            "label": i18n.tr("Devices")
                        }]
                    delegate: Shared.ActionButton {
                        text: modelData.label
                        selected: root.section === modelData.key
                        onClicked: root.section = modelData.key
                    }
                }
            }
            Flickable {
                width: parent.width
                height: Math.max(0, parent.height - y - saveActions.height - units.gu(1.2))
                contentWidth: width
                contentHeight: formCol.implicitHeight + units.gu(2)
                clip: true

                Column {
                    id: formCol
                    width: parent.width
                    spacing: units.gu(1.4)

                    Column {
                        width: parent.width
                        spacing: 12
                        visible: root.section === "general"
                        Label {
                            text: i18n.tr("PC Name (Hostname or IP[:Port]) *")
                            fontSize: "small"
                            font.bold: true
                            color: root.darkMode ? "#9BA7B8" : "#5A6577"
                        }
                        TextField {
                            id: hostField
                            height: Math.max(48, units.gu(6))
                            objectName: "pcHostField"
                            width: parent.width
                            text: root.hostInput
                            placeholderText: "e.g. 192.168.1.50 or work-pc.local:3389"
                            // Addresses are literal input, not words for the keyboard to correct.
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                            onTextChanged: root.hostInput = text
                        }

                        Label {
                            text: i18n.tr("Friendly Name (Optional)")
                            fontSize: "small"
                            font.bold: true
                            color: root.darkMode ? "#9BA7B8" : "#5A6577"
                        }
                        TextField {
                            height: Math.max(48, units.gu(6))
                            width: parent.width
                            text: root.friendlyName
                            placeholderText: "e.g. Work Windows 11 Desktop"
                            onTextChanged: root.friendlyName = text
                        }

                        Label {
                            text: i18n.tr("Group")
                            color: Shared.Design.secondaryText
                        }
                        TextField {
                            width: parent.width
                            height: 48
                            text: root.groupName
                            onTextChanged: root.groupName = text
                        }
                        Flow {
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: root.groups
                                delegate: Shared.ActionButton {
                                    text: modelData
                                    onClicked: root.groupName = modelData
                                }
                            }
                        }
                        // User Account Picker
                        Label {
                            text: i18n.tr("User Account")
                            fontSize: "small"
                            font.bold: true
                            color: root.darkMode ? "#9BA7B8" : "#5A6577"
                        }
                        Flow {
                            width: parent.width
                            spacing: units.gu(0.8)

                            Button {
                                text: i18n.tr("Ask every time")
                                color: root.accountId === "" ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                                onClicked: root.accountId = ""
                            }

                            Repeater {
                                model: root.accounts
                                delegate: Button {
                                    height: Math.max(48, units.gu(6))
                                    text: modelData.displayName
                                    color: root.accountId === modelData.id ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                                    onClicked: root.accountId = modelData.id
                                }
                            }
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 12
                        visible: root.section === "display"
                        // Display Resolution Preset
                        Label {
                            text: i18n.tr("Display Resolution")
                            fontSize: "small"
                            font.bold: true
                            color: root.darkMode ? "#9BA7B8" : "#5A6577"
                        }
                        Flow {
                            width: parent.width
                            spacing: units.gu(0.8)
                            Repeater {
                                model: [{
                                        "key": "native",
                                        "label": "Device Native"
                                    }, {
                                        "key": "dynamic",
                                        "label": "Dynamic (Fit)"
                                    }, {
                                        "key": "1920x1080",
                                        "label": "1920×1080"
                                    }, {
                                        "key": "1600x900",
                                        "label": "1600×900"
                                    }, {
                                        "key": "1366x768",
                                        "label": "1366×768"
                                    }, {
                                        "key": "1280x720",
                                        "label": "1280×720"
                                    }]
                                delegate: Button {
                                    height: Math.max(48, units.gu(6))
                                    objectName: "resolutionOption_" + modelData.key
                                    text: modelData.label
                                    color: root.resolutionPreset === modelData.key ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                                    onClicked: root.resolutionPreset = modelData.key
                                }
                            }
                        }

                        // Remote Scale Factor
                        Label {
                            text: i18n.tr("Remote Desktop Scale")
                            fontSize: "small"
                            font.bold: true
                            color: root.darkMode ? "#9BA7B8" : "#5A6577"
                        }
                        Flow {
                            spacing: units.gu(0.8)
                            Repeater {
                                model: [100, 125, 150, 200]
                                delegate: Button {
                                    height: Math.max(48, units.gu(6))
                                    width: Math.max(72, units.gu(8.5))
                                    text: modelData + "%"
                                    color: root.scaleFactor === modelData ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                                    onClicked: root.scaleFactor = modelData
                                }
                            }
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 12
                        visible: root.section === "devices"
                        // Default Touch Input Mode
                        Label {
                            text: i18n.tr("Default Touch Input Mode")
                            fontSize: "small"
                            font.bold: true
                            color: root.darkMode ? "#9BA7B8" : "#5A6577"
                        }
                        Flow {
                            width: parent.width
                            spacing: units.gu(1)
                            Button {
                                objectName: "directTouchOption"
                                text: i18n.tr("Direct Touch")
                                color: root.defaultTouchMode === "direct_touch" ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                                onClicked: root.defaultTouchMode = "direct_touch"
                            }
                            Button {
                                objectName: "trackpadOption"
                                text: i18n.tr("Mouse Pointer (Trackpad)")
                                color: root.defaultTouchMode === "mouse_pointer" ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                                onClicked: root.defaultTouchMode = "mouse_pointer"
                            }
                        }

                        // Audio Redirection
                        Label {
                            text: i18n.tr("Sound Output (RDPSND)")
                            fontSize: "small"
                            font.bold: true
                            color: root.darkMode ? "#9BA7B8" : "#5A6577"
                        }
                        Flow {
                            width: parent.width
                            spacing: units.gu(0.8)
                            Repeater {
                                model: [{
                                        "key": "play_on_device",
                                        "label": "Play on this device"
                                    }, {
                                        "key": "play_on_remote",
                                        "label": "Play on remote PC"
                                    }, {
                                        "key": "disabled",
                                        "label": "Do not play"
                                    }]
                                delegate: Button {
                                    height: Math.max(48, units.gu(6))
                                    text: modelData.label
                                    color: root.audioMode === modelData.key ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                                    onClicked: root.audioMode = modelData.key
                                }
                            }
                        }

                        // Toggles Row (Clipboard & NLA)
                        Row {
                            width: parent.width
                            spacing: units.gu(1.5)

                            CheckBox {
                                checked: root.clipboardRedirection
                                onClicked: root.clipboardRedirection = checked
                            }
                            Label {
                                text: i18n.tr("Sync Clipboard (CLIPRDR)")
                                color: root.darkMode ? "#F3F6FA" : "#1B2028"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: units.gu(1.5)

                            CheckBox {
                                checked: root.enableNla
                                onClicked: root.enableNla = checked
                            }
                            Label {
                                text: i18n.tr("Network Level Authentication (CredSSP / NLA)")
                                color: root.darkMode ? "#F3F6FA" : "#1B2028"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            Row {
                id: saveActions
                width: parent.width
                spacing: 8
                Shared.ActionButton {
                    objectName: "savePcButton"
                    width: (parent.width - 8) / 2
                    text: i18n.tr("Save")
                    selected: true
                    enabled: !root.busy
                    onClicked: root.save(false)
                }
                Shared.ActionButton {
                    objectName: "saveConnectPcButton"
                    width: (parent.width - 8) / 2
                    text: root.busy ? i18n.tr("Saving…") : i18n.tr("Save & Connect")
                    primary: true
                    enabled: !root.busy
                    onClicked: root.save(true)
                }
            }
        }
    }
}
