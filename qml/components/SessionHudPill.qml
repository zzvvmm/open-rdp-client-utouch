import QtQuick 2.12
import Lomiri.Components 1.3

Item {
    id: root

    property string pcTitle: "Remote PC"
    property string touchMode: "mouse_pointer"
    property bool keyboardVisible: false
    property real zoomFactor: 1.0
    property int currentFps: 60
    property string resolutionText: "1280×720"
    property bool showStats: false

    property bool expanded: false
    property bool showChordsMenu: false

    signal toggleTouchMode()
    signal toggleKeyboard()
    signal cycleZoom()
    signal sendChordRequested(string chord)
    signal disconnectRequested()

    width: parent.width
    height: parent.height

    // Floating collapsed pill (draggable along top/sides)
    Rectangle {
        id: floatingPill
        x: Math.min(Math.max(units.gu(1.5), (parent.width - width) / 2), parent.width - width - units.gu(1.5))
        y: units.gu(1.2)
        width: pillRow.implicitWidth + units.gu(2.4)
        height: units.gu(4.2)
        radius: height / 2
        color: "#D8151B24"
        border.width: units.dp(1)
        border.color: root.expanded ? "#0078D4" : "#3A465E"
        z: 40

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: units.gu(1)

            Rectangle {
                width: units.gu(1)
                height: units.gu(1)
                radius: width / 2
                color: "#2ECC71"
                anchors.verticalCenter: parent.verticalCenter
            }

            Label {
                text: root.pcTitle
                fontSize: "small"
                font.bold: true
                color: "#F3F6FA"
                anchors.verticalCenter: parent.verticalCenter
            }

            Label {
                visible: root.showStats
                text: "• " + root.resolutionText + " • " + root.currentFps + " FPS"
                fontSize: "x-small"
                color: "#29B6F6"
                anchors.verticalCenter: parent.verticalCenter
            }

            Icon {
                width: units.gu(1.8)
                height: units.gu(1.8)
                name: root.expanded ? "up" : "down"
                color: "#F3F6FA"
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            drag.target: floatingPill
            drag.minimumX: units.gu(0.5)
            drag.maximumX: root.width - floatingPill.width - units.gu(0.5)
            drag.minimumY: units.gu(0.5)
            drag.maximumY: root.height - floatingPill.height - units.gu(0.5)
            onClicked: {
                root.expanded = !root.expanded
                if (!root.expanded) root.showChordsMenu = false
            }
        }
    }

    // Expanded Windows App In-Session Control Bar
    Rectangle {
        id: expandedDrawer
        objectName: "sessionDrawer"
        visible: root.expanded
        y: Math.max(units.gu(0.5), Math.min(floatingPill.y + floatingPill.height + units.gu(0.8),
                                          root.height - height - units.gu(0.5)))
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - units.gu(2), units.gu(56))
        height: Math.min(drawerCol.implicitHeight + units.gu(2.4), Math.max(0, root.height - units.gu(1)))
        radius: units.gu(1.5)
        color: "#EE161C26"
        border.width: units.dp(1)
        border.color: "#2B3548"
        z: 45

        Flickable {
            id: drawerScroll
            objectName: "sessionDrawerScroll"
            anchors.fill: parent
            anchors.margins: units.gu(1.2)
            contentWidth: width
            contentHeight: drawerCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
        }

        Column {
            id: drawerCol
            parent: drawerScroll.contentItem
            width: drawerScroll.width
            spacing: units.gu(1.2)

            Row {
                width: parent.width
                spacing: units.gu(0.8)

                // Touch Mode Button (Trackpad vs Direct Touch)
                AbstractButton {
                    width: (parent.width - units.gu(3.2)) / 5
                    height: units.gu(6.2)
                    onClicked: root.toggleTouchMode()
                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(1)
                        color: "#243044"
                        border.width: units.dp(1)
                        border.color: "#0078D4"
                        Column {
                            anchors.centerIn: parent
                            spacing: units.gu(0.4)
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(2.2)
                                height: units.gu(2.2)
                                name: root.touchMode === "mouse_pointer" ? "input-mouse-symbolic" : "input-touchpad-symbolic"
                                color: "#29B6F6"
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.touchMode === "mouse_pointer" ? i18n.tr("Trackpad") : i18n.tr("Touch")
                                fontSize: "x-small"
                                color: "#F3F6FA"
                            }
                        }
                    }
                }

                // Keyboard Toggle Button
                AbstractButton {
                    width: (parent.width - units.gu(3.2)) / 5
                    height: units.gu(6.2)
                    onClicked: root.toggleKeyboard()
                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(1)
                        color: root.keyboardVisible ? "#0078D4" : "#243044"
                        Column {
                            anchors.centerIn: parent
                            spacing: units.gu(0.4)
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(2.2)
                                height: units.gu(2.2)
                                name: "input-keyboard-symbolic"
                                color: "#FFFFFF"
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: i18n.tr("Keyboard")
                                fontSize: "x-small"
                                color: "#FFFFFF"
                            }
                        }
                    }
                }

                // Zoom Toggle Button
                AbstractButton {
                    width: (parent.width - units.gu(3.2)) / 5
                    height: units.gu(6.2)
                    onClicked: root.cycleZoom()
                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(1)
                        color: root.zoomFactor > 1.01 ? "#0078D4" : "#243044"
                        Column {
                            anchors.centerIn: parent
                            spacing: units.gu(0.4)
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(2.2)
                                height: units.gu(2.2)
                                name: "zoom-in"
                                color: "#FFFFFF"
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(root.zoomFactor * 100) + "%"
                                fontSize: "x-small"
                                color: "#FFFFFF"
                            }
                        }
                    }
                }

                // Special Chords Menu Button
                AbstractButton {
                    width: (parent.width - units.gu(3.2)) / 5
                    height: units.gu(6.2)
                    onClicked: root.showChordsMenu = !root.showChordsMenu
                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(1)
                        color: root.showChordsMenu ? "#0078D4" : "#243044"
                        Column {
                            anchors.centerIn: parent
                            spacing: units.gu(0.4)
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(2.2)
                                height: units.gu(2.2)
                                name: "settings"
                                color: "#FFFFFF"
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: i18n.tr("Shortcuts")
                                fontSize: "x-small"
                                color: "#FFFFFF"
                            }
                        }
                    }
                }

                // Disconnect Button
                AbstractButton {
                    width: (parent.width - units.gu(3.2)) / 5
                    height: units.gu(6.2)
                    onClicked: root.disconnectRequested()
                    Rectangle {
                        anchors.fill: parent
                        radius: units.gu(1)
                        color: "#3A1E24"
                        border.width: units.dp(1)
                        border.color: "#EF4444"
                        Column {
                            anchors.centerIn: parent
                            spacing: units.gu(0.4)
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: units.gu(2.2)
                                height: units.gu(2.2)
                                name: "system-shutdown"
                                color: "#EF4444"
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: i18n.tr("End")
                                fontSize: "x-small"
                                color: "#FCA5A5"
                            }
                        }
                    }
                }
            }

            // Expandable Windows Shortcuts Sub-Grid
            Grid {
                visible: root.showChordsMenu
                width: parent.width
                columns: 3
                spacing: units.gu(0.8)

                Repeater {
                    model: [
                        { label: i18n.tr("Copy"), chord: "ctrl+c" },
                        { label: i18n.tr("Paste"), chord: "ctrl+v" },
                        { label: i18n.tr("Select all"), chord: "ctrl+a" },
                        { label: "Ctrl+Alt+T", chord: "ctrl+alt+t" },
                        { label: "Alt+F2", chord: "alt+f2" },
                        { label: "Alt+F4", chord: "alt+f4" },
                        { label: "Ctrl+Shift+C", chord: "ctrl+shift+c" },
                        { label: "Ctrl+Shift+V", chord: "ctrl+shift+v" },
                        { label: "Ctrl+Alt+D", chord: "ctrl+alt+d" },
                        { label: "Ctrl+Alt+Del", chord: "ctrl+alt+del" },
                        { label: "Alt+Tab", chord: "alt+tab" },
                        { label: i18n.tr("Super / Win"), chord: "win" },
                        { label: "Win+D", chord: "win+d" },
                        { label: "Ctrl+Shift+Esc", chord: "ctrl+shift+esc" },
                        { label: "Win+L", chord: "win+l" }
                    ]
                    delegate: Button {
                        width: (drawerCol.width - units.gu(1.6)) / 3
                        height: units.gu(3.8)
                        text: modelData.label
                        color: "#263248"
                        onClicked: {
                            root.sendChordRequested(modelData.chord)
                            root.expanded = false
                            root.showChordsMenu = false
                        }
                    }
                }
            }
        }
    }
}
