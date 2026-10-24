import QtQuick 2.12
import Lomiri.Components 1.3

Rectangle {
    id: root

    property bool active: false
    property bool darkMode: true
    property var accounts: []

    property string editId: ""
    property string hostInput: ""
    property string friendlyName: ""
    property string groupName: "Saved PCs"
    property string accountId: ""
    property string resolutionPreset: "dynamic"
    property int scaleFactor: 100
    property string defaultTouchMode: "mouse_pointer"
    property string audioMode: "play_on_device"
    property bool clipboardRedirection: true
    property bool enableNla: true
    property string validationError: ""

    signal saveRequested(var payload)
    signal cancelRequested()

    function openForNew(defaultRes, defaultScale, defaultTouch, defaultAudio, defaultClip) {
        editId = ""
        hostInput = ""
        friendlyName = ""
        groupName = "Saved PCs"
        accountId = ""
        resolutionPreset = defaultRes || "dynamic"
        scaleFactor = defaultScale || 100
        defaultTouchMode = defaultTouch || "mouse_pointer"
        audioMode = defaultAudio || "play_on_device"
        clipboardRedirection = (defaultClip !== undefined) ? defaultClip : true
        enableNla = true
        validationError = ""
        active = true
    }

    function openForEdit(pc) {
        editId = pc.id || ""
        hostInput = pc.address || pc.hostname || ""
        friendlyName = pc.friendlyName || ""
        groupName = pc.groupName || "Saved PCs"
        accountId = pc.accountId || ""
        resolutionPreset = pc.resolutionPreset || "dynamic"
        scaleFactor = pc.scaleFactor || 100
        defaultTouchMode = pc.defaultTouchMode || "mouse_pointer"
        audioMode = pc.audioMode || "play_on_device"
        clipboardRedirection = (pc.clipboardRedirection !== undefined) ? pc.clipboardRedirection : true
        enableNla = (pc.enableNla !== undefined) ? pc.enableNla : true
        validationError = ""
        active = true
    }

    visible: active
    anchors.fill: parent
    color: "#CC0B0E14"
    z: 80

    MouseArea {
        anchors.fill: parent
        onClicked: {}
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
                    color: root.darkMode ? "#263042" : "#E2E8F0"
                    onClicked: {
                        root.active = false
                        root.cancelRequested()
                    }
                }
            }

            Rectangle {
                visible: root.validationError.length > 0
                width: parent.width
                height: units.gu(4)
                radius: units.gu(0.8)
                color: "#3A1E24"
                Label {
                    anchors.centerIn: parent
                    text: root.validationError
                    fontSize: "small"
                    color: "#FCA5A5"
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - units.gu(12)
                contentWidth: width
                contentHeight: formCol.implicitHeight + units.gu(2)
                clip: true

                Column {
                    id: formCol
                    width: parent.width
                    spacing: units.gu(1.4)

                    Label {
                        text: i18n.tr("PC Name (Hostname or IP[:Port]) *")
                        fontSize: "small"
                        font.bold: true
                        color: root.darkMode ? "#9BA7B8" : "#5A6577"
                    }
                    TextField {
                        width: parent.width
                        text: root.hostInput
                        placeholderText: "e.g. 192.168.1.50 or work-pc.local:3389"
                        onTextChanged: root.hostInput = text
                    }

                    Label {
                        text: i18n.tr("Friendly Name (Optional)")
                        fontSize: "small"
                        font.bold: true
                        color: root.darkMode ? "#9BA7B8" : "#5A6577"
                    }
                    TextField {
                        width: parent.width
                        text: root.friendlyName
                        placeholderText: "e.g. Work Windows 11 Desktop"
                        onTextChanged: root.friendlyName = text
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
                                text: modelData.displayName
                                color: root.accountId === modelData.id ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                                onClicked: root.accountId = modelData.id
                            }
                        }
                    }

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
                            model: [
                                { key: "dynamic", label: "Dynamic (Fit)" },
                                { key: "native", label: "Device Native" },
                                { key: "1920x1080", label: "1920×1080" },
                                { key: "1600x900", label: "1600×900" },
                                { key: "1366x768", label: "1366×768" },
                                { key: "1280x720", label: "1280×720" }
                            ]
                            delegate: Button {
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
                    Row {
                        spacing: units.gu(0.8)
                        Repeater {
                            model: [100, 125, 150, 200]
                            delegate: Button {
                                width: units.gu(8.5)
                                text: modelData + "%"
                                color: root.scaleFactor === modelData ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                                onClicked: root.scaleFactor = modelData
                            }
                        }
                    }

                    // Default Touch Input Mode
                    Label {
                        text: i18n.tr("Default Touch Input Mode")
                        fontSize: "small"
                        font.bold: true
                        color: root.darkMode ? "#9BA7B8" : "#5A6577"
                    }
                    Row {
                        spacing: units.gu(1)
                        Button {
                            text: i18n.tr("Mouse Pointer (Trackpad)")
                            color: root.defaultTouchMode === "mouse_pointer" ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                            onClicked: root.defaultTouchMode = "mouse_pointer"
                        }
                        Button {
                            text: i18n.tr("Direct Touch")
                            color: root.defaultTouchMode === "direct_touch" ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                            onClicked: root.defaultTouchMode = "direct_touch"
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
                            model: [
                                { key: "play_on_device", label: "Play on this device" },
                                { key: "play_on_remote", label: "Play on remote PC" },
                                { key: "disabled", label: "Do not play" }
                            ]
                            delegate: Button {
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

            // Save Action Row
            Row {
                width: parent.width
                spacing: units.gu(1.2)

                Button {
                    width: parent.width
                    height: units.gu(4.5)
                    text: root.editId.length > 0 ? i18n.tr("Save Changes") : i18n.tr("Save PC")
                    color: "#0078D4"
                    onClicked: {
                        if (root.hostInput.trim().length === 0) {
                            root.validationError = i18n.tr("Please enter a hostname or IP address.")
                            return
                        }
                        root.saveRequested({
                            action: "save_pc",
                            id: root.editId,
                            hostInput: root.hostInput.trim(),
                            friendlyName: root.friendlyName.trim(),
                            groupName: root.groupName.trim(),
                            accountId: root.accountId,
                            resolutionPreset: root.resolutionPreset,
                            scaleFactor: root.scaleFactor,
                            defaultTouchMode: root.defaultTouchMode,
                            audioMode: root.audioMode,
                            clipboardRedirection: root.clipboardRedirection,
                            enableNla: root.enableNla,
                            enableTls: true
                        })
                        root.active = false
                    }
                }
            }
        }
    }
}
