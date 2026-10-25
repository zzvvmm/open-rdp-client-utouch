import QtQuick 2.12
import Lomiri.Components 1.3

Flickable {
    id: root

    property var settings: ({})
    property bool darkMode: true

    signal updateSettings(var payload)

    contentWidth: width
    contentHeight: settingsCol.implicitHeight + units.gu(6)
    clip: true

    function pushUpdate(patch) {
        var next = {
            action: "save_settings",
            themeMode: settings.themeMode || "dark",
            defaultResolution: settings.defaultResolution || "dynamic",
            defaultScaleFactor: settings.defaultScaleFactor || 100,
            defaultTouchMode: settings.defaultTouchMode || "mouse_pointer",
            defaultAudioMode: settings.defaultAudioMode || "play_on_device",
            defaultClipboardEnabled: (settings.defaultClipboardEnabled !== undefined) ? settings.defaultClipboardEnabled : true,
            trackpadSpeedPercent: settings.trackpadSpeedPercent || 100,
            showStatsOverlay: !!settings.showStatsOverlay,
            strictCertCheck: !!settings.strictCertCheck
        }
        for (var k in patch) {
            next[k] = patch[k]
        }
        root.updateSettings(next)
    }

    Column {
        id: settingsCol
        width: parent.width - units.gu(4)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: units.gu(2)
        spacing: units.gu(2)

        Label {
            text: i18n.tr("Global Preferences")
            fontSize: "large"
            font.bold: true
            color: root.darkMode ? "#F3F6FA" : "#1B2028"
        }

        // Theme Card
        Rectangle {
            width: parent.width
            height: themeInner.implicitHeight + units.gu(3)
            radius: units.gu(1.4)
            color: root.darkMode ? "#1C2331" : "#FFFFFF"
            border.width: units.dp(1)
            border.color: root.darkMode ? "#2B3548" : "#DCE2EC"

            Column {
                id: themeInner
                width: parent.width - units.gu(3)
                anchors.centerIn: parent
                spacing: units.gu(1.2)

                Label {
                    text: i18n.tr("Appearance (Suru Theme)")
                    fontSize: "medium"
                    font.bold: true
                    color: root.darkMode ? "#F3F6FA" : "#1B2028"
                }

                Row {
                    spacing: units.gu(1)
                    Button {
                        text: i18n.tr("Fluent Dark")
                        color: (root.settings.themeMode || "dark") === "dark" ? "#0078D4" : "#263042"
                        onClicked: root.pushUpdate({ themeMode: "dark" })
                    }
                    Button {
                        text: i18n.tr("Suru Light")
                        color: root.settings.themeMode === "light" ? "#0078D4" : "#263042"
                        onClicked: root.pushUpdate({ themeMode: "light" })
                    }
                }
            }
        }

        // Touch & Trackpad Ergonomics Card
        Rectangle {
            width: parent.width
            height: touchInner.implicitHeight + units.gu(3)
            radius: units.gu(1.4)
            color: root.darkMode ? "#1C2331" : "#FFFFFF"
            border.width: units.dp(1)
            border.color: root.darkMode ? "#2B3548" : "#DCE2EC"

            Column {
                id: touchInner
                width: parent.width - units.gu(3)
                anchors.centerIn: parent
                spacing: units.gu(1.2)

                Label {
                    text: i18n.tr("Touch & Virtual Trackpad")
                    fontSize: "medium"
                    font.bold: true
                    color: root.darkMode ? "#F3F6FA" : "#1B2028"
                }

                Label {
                    text: i18n.tr("Trackpad Pointer Speed: ") + (root.settings.trackpadSpeedPercent || 100) + "%"
                    fontSize: "small"
                    color: root.darkMode ? "#9BA7B8" : "#5A6577"
                }

                Row {
                    spacing: units.gu(0.8)
                    Repeater {
                        model: [75, 100, 125, 150, 200]
                        delegate: Button {
                            width: units.gu(7.5)
                            text: modelData + "%"
                            color: (root.settings.trackpadSpeedPercent || 100) === modelData ? "#0078D4" : (root.darkMode ? "#263042" : "#E2E8F0")
                            onClicked: root.pushUpdate({ trackpadSpeedPercent: modelData })
                        }
                    }
                }

                Row {
                    spacing: units.gu(1.5)
                    CheckBox {
                        checked: !!root.settings.showStatsOverlay
                        onClicked: root.pushUpdate({ showStatsOverlay: checked })
                    }
                    Label {
                        text: i18n.tr("Show live resolution & FPS badge in session pill")
                        color: root.darkMode ? "#F3F6FA" : "#1B2028"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // About Open-Source Card
        Rectangle {
            width: parent.width
            height: aboutCol.implicitHeight + units.gu(3)
            radius: units.gu(1.4)
            color: root.darkMode ? "#1C2331" : "#FFFFFF"
            border.width: units.dp(1)
            border.color: root.darkMode ? "#2B3548" : "#DCE2EC"

            Column {
                id: aboutCol
                width: parent.width - units.gu(3)
                anchors.centerIn: parent
                spacing: units.gu(0.8)

                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: i18n.tr("Open RDP Client for Ubuntu Touch")
                    fontSize: "medium"
                    font.bold: true
                    color: root.darkMode ? "#F3F6FA" : "#1B2028"
                }
                Label {
                    text: i18n.tr("Version 0.1.3 • License: GPL-3.0-or-later")
                    fontSize: "small"
                    color: "#29B6F6"
                }
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: i18n.tr("Powered by a pure-Rust IronRDP engine with QtQuick/Lomiri UI. Supports CredSSP/NLA authentication, TOFU certificate verification, dynamic display resize (DISP), clipboard sync (CLIPRDR), and PCM audio redirection (RDPSND).")
                    fontSize: "small"
                    color: root.darkMode ? "#9BA7B8" : "#5A6577"
                }
            }
        }
    }
}
