import QtQuick 2.12
import Lomiri.Components 1.3

Rectangle {
    id: root
    property var pcData: ({})
    property bool darkMode: true
    property bool isActiveSession: false

    signal connectClicked(string pcId)
    signal editClicked(var pc)
    signal duplicateClicked(string pcId)
    signal deleteClicked(string pcId)
    signal favoriteToggled(string pcId)

    radius: units.gu(1.5)
    color: darkMode ? "#1C2331" : "#FFFFFF"
    border.width: isActiveSession ? units.dp(2) : units.dp(1)
    border.color: isActiveSession ? "#0078D4" : (darkMode ? "#2B3548" : "#DCE2EC")
    clip: true

    Column {
        anchors.fill: parent
        spacing: 0

        // 16:9 Windows App Preview Banner
        Item {
            width: parent.width
            height: Math.round(parent.width * 0.52)
            clip: true

            Image {
                id: fallbackArt
                anchors.fill: parent
                source: "qrc:/assets/icons/pc-card.svg"
                fillMode: Image.PreserveAspectCrop
                visible: !thumbImage.visible
            }

            Image {
                id: thumbImage
                anchors.fill: parent
                source: (pcData && pcData.thumbnailPath && pcData.thumbnailPath.length > 0) ? pcData.thumbnailPath : ""
                fillMode: Image.PreserveAspectCrop
                cache: false
                visible: status === Image.Ready
            }

            // Subtle top gradient for badges
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: units.gu(4.5)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#99000000" }
                    GradientStop { position: 1.0; color: "#00000000" }
                }
            }

            // Status / Resolution Badge
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: units.gu(1)
                height: units.gu(2.6)
                width: badgeLabel.implicitWidth + units.gu(1.6)
                radius: units.gu(1.3)
                color: isActiveSession ? "#0078D4" : (pcData.isDemo ? "#0D9488" : "#AA11151C")

                Label {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: isActiveSession ? "ACTIVE SESSION" : (pcData.isDemo ? "INTERACTIVE DEMO" : (pcData.resolutionLabel || "Dynamic"))
                    fontSize: "x-small"
                    font.bold: true
                    color: "#FFFFFF"
                }
            }

            // Favorite Star Button
            AbstractButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: units.gu(0.6)
                width: units.gu(4)
                height: units.gu(4)
                onClicked: root.favoriteToggled(pcData.id)

                Rectangle {
                    anchors.centerIn: parent
                    width: units.gu(3.2)
                    height: units.gu(3.2)
                    radius: width / 2
                    color: "#88000000"

                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2)
                        height: units.gu(2)
                        name: pcData.favorite ? "starred" : "non-starred"
                        color: pcData.favorite ? "#FBBF24" : "#FFFFFF"
                    }
                }
            }

            // Tap on preview connects directly
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: units.gu(4.5)
                onClicked: root.connectClicked(pcData.id)
            }
        }

        // Card Info & Action Bar
        Item {
            width: parent.width
            height: parent.height - Math.round(parent.width * 0.52)

            Column {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: units.gu(1.4)
                spacing: units.gu(0.4)

                Label {
                    width: parent.width
                    text: pcData.displayTitle || "Remote PC"
                    fontSize: "medium"
                    font.bold: true
                    color: darkMode ? "#F3F6FA" : "#1B2028"
                    elide: Text.ElideRight
                }

                Label {
                    width: parent.width
                    text: (pcData.address || "") + " • " + (pcData.accountLabel || "Ask every time")
                    fontSize: "small"
                    color: darkMode ? "#9BA7B8" : "#5A6577"
                    elide: Text.ElideRight
                }
            }

            // Bottom Actions Row
            Row {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: units.gu(1.2)
                spacing: units.gu(0.8)

                Button {
                    width: parent.width - units.gu(11.5)
                    height: units.gu(3.8)
                    text: isActiveSession ? i18n.tr("Resume") : i18n.tr("Connect")
                    color: "#0078D4"
                    onClicked: root.connectClicked(pcData.id)
                }

                AbstractButton {
                    width: units.gu(3.4)
                    height: units.gu(3.8)
                    onClicked: root.editClicked(pcData)
                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(0.7)
                        color: darkMode ? "#263042" : "#E8EDF5"
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2)
                            height: units.gu(2)
                            name: "edit"
                            color: darkMode ? "#F3F6FA" : "#1B2028"
                        }
                    }
                }

                AbstractButton {
                    width: units.gu(3.4)
                    height: units.gu(3.8)
                    onClicked: root.duplicateClicked(pcData.id)
                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(0.7)
                        color: darkMode ? "#263042" : "#E8EDF5"
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2)
                            height: units.gu(2)
                            name: "edit-copy"
                            color: darkMode ? "#F3F6FA" : "#1B2028"
                        }
                    }
                }

                AbstractButton {
                    width: units.gu(3.4)
                    height: units.gu(3.8)
                    onClicked: root.deleteClicked(pcData.id)
                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(0.7)
                        color: darkMode ? "#3A1E24" : "#FEE2E2"
                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(2)
                            height: units.gu(2)
                            name: "delete"
                            color: "#EF4444"
                        }
                    }
                }
            }
        }
    }
}
