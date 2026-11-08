import QtQuick 2.12
import Lomiri.Components 1.3

Rectangle {
    id: root

    property string ctrlState: "off"
    property string altState: "off"
    property string shiftState: "off"
    property string winState: "off"

    signal modifierTapped(string modifierName)
    signal virtualKeyTapped(string keyName)
    signal chordTapped(string chordName)
    signal summonOskRequested()

    height: units.gu(5.6)
    color: "#F2141923"
    border.width: units.dp(1)
    border.color: "#2B3548"

    function modColor(stateStr) {
        if (stateStr === "locked") return "#0078D4"
        if (stateStr === "latched") return "#29B6F6"
        return "#232C3D"
    }

    function modBadge(label, stateStr) {
        if (stateStr === "locked") return label + " ••"
        if (stateStr === "latched") return label + " •"
        return label
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: units.gu(0.6)
        contentWidth: keyRow.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        clip: true

        Row {
            id: keyRow
            height: parent.height
            spacing: units.gu(0.6)

            // OSK Summon Button
            AbstractButton {
                width: units.gu(5.2)
                height: parent.height
                onClicked: root.summonOskRequested()
                Rectangle {
                    anchors.fill: parent
                    radius: units.gu(0.7)
                    color: "#0078D4"
                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(2.2)
                        height: units.gu(2.2)
                        name: "input-keyboard-symbolic"
                        color: "#FFFFFF"
                    }
                }
            }

            // 3-State Sticky Modifiers (Ctrl, Alt, Shift, Win)
            Repeater {
                model: [
                    { id: "ctrl", label: "Ctrl", state: root.ctrlState },
                    { id: "alt", label: "Alt", state: root.altState },
                    { id: "shift", label: "Shift", state: root.shiftState },
                    { id: "win", label: "Win", state: root.winState }
                ]
                delegate: AbstractButton {
                    width: units.gu(6.4)
                    height: keyRow.height
                    onClicked: root.modifierTapped(modelData.id)
                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(0.7)
                        color: root.modColor(modelData.state)
                        border.width: units.dp(1)
                        border.color: modelData.state === "off" ? "#344156" : "#60CDFF"
                        Label {
                            anchors.centerIn: parent
                            text: root.modBadge(modelData.label, modelData.state)
                            fontSize: "small"
                            font.bold: true
                            color: "#FFFFFF"
                        }
                    }
                }
            }

            // Utility & Arrow & Function Keys
            Repeater {
                model: [
                    "Esc", "Tab", "←", "↑", "↓", "→", "Del", "Bksp", "Enter",
                    "Home", "End", "PgUp", "PgDn",
                    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"
                ]
                delegate: AbstractButton {
                    width: units.gu(5.4)
                    height: keyRow.height
                    onClicked: root.virtualKeyTapped(modelData)
                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(0.7)
                        color: parent.pressed ? "#0078D4" : "#1E2636"
                        border.width: units.dp(1)
                        border.color: "#2E3A4F"
                        Label {
                            anchors.centerIn: parent
                            text: modelData
                            fontSize: "small"
                            color: "#E2E8F0"
                        }
                    }
                }
            }

            // Quick Ctrl+Alt+Del Button
            AbstractButton {
                width: units.gu(7.5)
                height: keyRow.height
                onClicked: root.chordTapped("ctrl+alt+del")
                Rectangle {
                    anchors.fill: parent
                    radius: units.gu(0.7)
                    color: "#3A1E24"
                    border.width: units.dp(1)
                    border.color: "#EF4444"
                    Label {
                        anchors.centerIn: parent
                        text: "C+A+Del"
                        fontSize: "x-small"
                        font.bold: true
                        color: "#FCA5A5"
                    }
                }
            }
        }
    }
}
