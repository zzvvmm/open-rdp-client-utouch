import QtQuick 2.12
import Lomiri.Components 1.3

Rectangle {
    id: root
    objectName: "updatePrompt"
    anchors.fill: parent
    color: "#CC0B0E14"
    z: 100
    visible: false
    focus: visible
    onVisibleChanged: {
        if (visible) {
            forceActiveFocus()
            Qt.inputMethod.hide()
        }
    }
    Keys.onEscapePressed: root.updateLater()
    Keys.onBackPressed: root.updateLater()

    property string version: ""
    property string installedVersion: ""
    property string changelog: ""
    property bool darkMode: true
    property bool openFailed: false
    signal updateNow()
    signal updateLater()
    signal skipVersion()

    MouseArea { anchors.fill: parent }

    Rectangle {
        id: dialog
        objectName: "updateDialog"
        width: Math.min(parent.width - units.gu(3), units.gu(58))
        height: Math.min(parent.height - units.gu(3), units.gu(70))
        anchors.centerIn: parent
        radius: units.gu(1.6)
        color: root.darkMode ? "#1C2331" : "#FFFFFF"
        border.width: units.dp(1)
        border.color: "#0078D4"

        Flickable {
            id: scroll
            objectName: "updateDialogScroll"
            anchors.fill: parent
            anchors.margins: units.gu(2)
            clip: true
            contentWidth: width
            contentHeight: content.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: content
                width: scroll.width
                spacing: units.gu(1.4)

                Label {
                    width: parent.width
                    text: i18n.tr("Update available")
                    fontSize: "large"
                    font.bold: true
                    wrapMode: Text.WordWrap
                    color: root.darkMode ? "#F3F6FA" : "#1B2028"
                }
                Label {
                    width: parent.width
                    text: i18n.tr("Open RDP Client ") + root.version
                    textFormat: Text.PlainText
                    fontSize: "medium"
                    font.bold: true
                    wrapMode: Text.WrapAnywhere
                    color: "#29B6F6"
                }
                Label {
                    width: parent.width
                    text: i18n.tr("Installed version: ") + root.installedVersion
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    fontSize: "small"
                    color: root.darkMode ? "#9BA7B8" : "#5A6577"
                }
                Label {
                    text: i18n.tr("Changelog")
                    font.bold: true
                    color: root.darkMode ? "#F3F6FA" : "#1B2028"
                }
                Flickable {
                    objectName: "updateChangelogScroll"
                    width: parent.width
                    height: Math.min(changelogLabel.implicitHeight, Math.max(units.gu(8), dialog.height * 0.3))
                    contentWidth: width
                    contentHeight: changelogLabel.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Label {
                        id: changelogLabel
                        objectName: "updateChangelog"
                        width: parent.width
                        text: root.changelog || i18n.tr("No changelog was provided for this version.")
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        fontSize: "small"
                        color: root.darkMode ? "#E2E8F0" : "#334155"
                    }
                }
                Label {
                    width: parent.width
                    text: i18n.tr("OpenStore will open so you can download and install the update.")
                    fontSize: "small"
                    wrapMode: Text.WordWrap
                    color: root.darkMode ? "#9BA7B8" : "#5A6577"
                }
                Label {
                    width: parent.width
                    visible: root.openFailed
                    text: i18n.tr("Could not open OpenStore. Please try again or choose Update Later.")
                    fontSize: "small"
                    wrapMode: Text.WordWrap
                    color: root.darkMode ? "#FCA5A5" : "#B91C1C"
                }
                Button {
                    objectName: "updateNowButton"
                    width: parent.width
                    text: i18n.tr("Update Now")
                    color: "#0078D4"
                    onClicked: root.updateNow()
                }
                Button {
                    objectName: "updateLaterButton"
                    width: parent.width
                    text: i18n.tr("Update Later")
                    color: root.darkMode ? "#263042" : "#E2E8F0"
                    onClicked: root.updateLater()
                }
                Button {
                    objectName: "skipUpdateButton"
                    width: parent.width
                    text: i18n.tr("Skip This Version")
                    color: root.darkMode ? "#263042" : "#E2E8F0"
                    onClicked: root.skipVersion()
                }
            }
        }
    }
}
