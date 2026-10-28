import QtQuick 2.12
import Lomiri.Components 1.3

Flickable {
    id: root

    property var settings: ({})
    property bool darkMode: true
    property string appVersion: ""
    property string updateStatus: "idle"
    property bool updateChecking: false
    property bool updateReady: false
    property string skippedVersion: ""

    signal updateSettings(var payload)
    signal checkUpdatesRequested()

    contentWidth: width
    contentHeight: settingsCol.implicitHeight + units.gu(6)
    clip: true

    function pushUpdate(patch) {
        // The backend merges patches; avoid overwriting update preferences with stale UI values.
        var next = { action: "save_settings" }
        for (var k in patch) {
            next[k] = patch[k]
        }
        root.updateSettings(next)
    }

    function updateStatusText() {
        switch (updateStatus) {
        case "checking": return i18n.tr("Checking for updates…")
        case "upToDate": return i18n.tr("You are up to date.")
        case "available": return i18n.tr("An update is available. Check again to view it.")
        case "error": return i18n.tr("Could not check for updates. Check your connection and try again.")
        case "unavailable": return i18n.tr("Update information is unavailable for this device. Please try again later.")
        case "openingStore": return i18n.tr("Continue updating in OpenStore.")
        case "openFailed": return i18n.tr("Could not open OpenStore. Please try again.")
        default: return ""
        }
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

        Rectangle {
            width: parent.width
            height: reportingCol.implicitHeight + units.gu(3)
            radius: units.gu(1.4)
            color: root.darkMode ? "#1C2331" : "#FFFFFF"
            border.width: units.dp(1)
            border.color: root.darkMode ? "#2B3548" : "#DCE2EC"

            Column {
                id: reportingCol
                width: parent.width - units.gu(3)
                anchors.centerIn: parent
                spacing: units.gu(1.2)

                Row {
                    width: parent.width
                    spacing: units.gu(1.5)
                    CheckBox {
                        id: reportErrors
                        objectName: "reportErrorsCheckBox"
                        checked: root.settings.reportErrors !== false
                        onClicked: root.pushUpdate({ reportErrors: checked })
                    }
                    Label {
                        width: parent.width - reportErrors.width - parent.spacing
                        text: i18n.tr("Report Errors")
                        fontSize: "medium"
                        font.bold: true
                        wrapMode: Text.WordWrap
                        color: root.darkMode ? "#F3F6FA" : "#1B2028"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Label {
                    width: parent.width
                    text: i18n.tr("Send technical error reports to Sentry to help fix bugs. Enabled by default; changes apply immediately. Reports exclude credentials, PC addresses, screen contents, and clipboard text.")
                    wrapMode: Text.WordWrap
                    fontSize: "small"
                    color: root.darkMode ? "#9BA7B8" : "#5A6577"
                }
            }
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

        Rectangle {
            width: parent.width
            height: updatesCol.implicitHeight + units.gu(3)
            radius: units.gu(1.4)
            color: root.darkMode ? "#1C2331" : "#FFFFFF"
            border.width: units.dp(1)
            border.color: root.darkMode ? "#2B3548" : "#DCE2EC"

            Column {
                id: updatesCol
                width: parent.width - units.gu(3)
                anchors.centerIn: parent
                spacing: units.gu(1.2)

                Label {
                    text: i18n.tr("Updates")
                    fontSize: "medium"
                    font.bold: true
                    color: root.darkMode ? "#F3F6FA" : "#1B2028"
                }
                Label {
                    width: parent.width
                    text: i18n.tr("Installed version: ") + root.appVersion
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    fontSize: "small"
                    color: root.darkMode ? "#9BA7B8" : "#5A6577"
                }
                Row {
                    width: parent.width
                    spacing: units.gu(1.5)
                    CheckBox {
                        id: autoUpdates
                        objectName: "automaticUpdatesCheckBox"
                        checked: root.settings.autoCheckUpdates !== false
                        onClicked: root.pushUpdate({ autoCheckUpdates: checked })
                    }
                    Label {
                        width: parent.width - autoUpdates.width - parent.spacing
                        text: i18n.tr("Automatically check for updates")
                        wrapMode: Text.WordWrap
                        color: root.darkMode ? "#F3F6FA" : "#1B2028"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Label {
                    width: parent.width
                    text: i18n.tr("Check once a day when the app is opened or resumed. Manual checks are always available.")
                    wrapMode: Text.WordWrap
                    fontSize: "small"
                    color: root.darkMode ? "#9BA7B8" : "#5A6577"
                }
                Button {
                    objectName: "checkUpdatesButton"
                    width: parent.width
                    text: root.updateChecking ? i18n.tr("Checking…") : i18n.tr("Check for updates")
                    enabled: root.updateReady && !root.updateChecking
                    color: "#0078D4"
                    onClicked: root.checkUpdatesRequested()
                }
                Label {
                    width: parent.width
                    visible: text.length > 0
                    text: root.updateStatusText()
                    wrapMode: Text.WordWrap
                    fontSize: "small"
                    color: root.darkMode ? "#9BA7B8" : "#5A6577"
                }
                Label {
                    width: parent.width
                    visible: root.skippedVersion.length > 0
                    text: i18n.tr("Skipped version: ") + root.skippedVersion
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    fontSize: "small"
                    color: root.darkMode ? "#9BA7B8" : "#5A6577"
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
                    text: i18n.tr("Version 0.3.0 • License: GPL-3.0-or-later")
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
