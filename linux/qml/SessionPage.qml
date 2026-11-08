import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import RdpClient 1.0
import OpenRdp 1.0

FocusScope {
    id: root
    property var appState
    property bool blocked: false
    property bool fullscreen: false
    property bool touchControls: false
    property bool dragLocked: false
    property bool precise: false
    readonly property bool inputEnabled: visible && appState.sessionStage === "connected" && !blocked
    readonly property bool dynamicResolution: appState.activePc !== null && appState.activePc.resolutionPreset === "dynamic"
    readonly property int viewportWidth: Math.round(viewport.width)
    readonly property int viewportHeight: Math.round(viewport.height)
    property alias remoteInput: hardware
    property alias viewportItem: viewport
    signal fullscreenRequested
    function refreshCanvas() {
        viewport.refreshCanvas();
    }
    function restoreFocus() {
        Qt.callLater(function () {
                if (root.inputEnabled && !softwareKeyboard.softwareKeyboardRequested)
                    hardware.forceActiveFocus();
            });
    }
    function releaseInput() {
        if (hardware)
            hardware.releaseAll();
        if (viewport)
            viewport.cancelInput();
        if (dragLocked && appState)
            appState.sendAction({
                    "action": "mouse_button",
                    "button": 1,
                    "pressed": false
                });
        dragLocked = false;
    }
    onInputEnabledChanged: {
        if (!inputEnabled) {
            releaseInput();
            softwareKeyboard.hideSoftwareKeyboard();
        } else {
            restoreFocus();
            resizeDelay.restart();
        }
    }
    onVisibleChanged: {
        if (!visible)
            releaseInput();
        else
            restoreFocus();
    }
    onWidthChanged: {
        releaseInput();
        resizeDelay.restart();
    }
    onHeightChanged: {
        releaseInput();
        resizeDelay.restart();
    }
    onTouchControlsChanged: if (!touchControls)
        softwareKeyboard.hideSoftwareKeyboard()
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive) {
                root.releaseInput();
                softwareKeyboard.hideSoftwareKeyboard();
            } else
                root.restoreFocus();
        }
    }
    Timer {
        id: resizeDelay
        interval: 350
        onTriggered: {
            if (root.inputEnabled && root.dynamicResolution && viewport.width >= 320 && viewport.height >= 240)
                root.appState.sendAction({
                        "action": "resize_session",
                        "width": root.viewportWidth,
                        "height": root.viewportHeight,
                        "scaleFactor": root.appState.activePc.scaleFactor || 100
                    });
        }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        ToolBar {
            Layout.fillWidth: true
            RowLayout {
                anchors.fill: parent
                ToolButton {
                    text: qsTr("PCs")
                    onClicked: {
                        root.appState.inSessionView = false;
                        root.releaseInput();
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: root.appState.activePcTitle
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Label {
                    visible: !!root.appState.appSettings.showStatsOverlay
                    text: root.appState.remoteWidth + "×" + root.appState.remoteHeight + " · " + root.appState.currentFps + " FPS"
                }
                ComboBox {
                    model: ["100%", "150%", "200%"]
                    implicitWidth: 90
                    onActivated: {
                        viewport.zoomFactor = [1, 1.5, 2][currentIndex];
                        root.restoreFocus();
                    }
                }
                ToolButton {
                    text: qsTr("Shortcuts")
                    onClicked: {
                        root.releaseInput();
                        shortcuts.open();
                    }
                    Menu {
                        id: shortcuts
                        onClosed: root.restoreFocus()
                        Repeater {
                            model: [{
                                    "label": "Ctrl+Alt+Del",
                                    "chord": "ctrl+alt+del"
                                }, {
                                    "label": "Alt+Tab",
                                    "chord": "alt+tab"
                                }, {
                                    "label": "Copy",
                                    "chord": "ctrl+c"
                                }, {
                                    "label": "Paste",
                                    "chord": "ctrl+v"
                                }, {
                                    "label": "Select all",
                                    "chord": "ctrl+a"
                                }, {
                                    "label": "Task manager",
                                    "chord": "ctrl+shift+esc"
                                }, {
                                    "label": "Show desktop",
                                    "chord": "win+d"
                                }, {
                                    "label": "Lock PC",
                                    "chord": "win+l"
                                }, {
                                    "label": "Terminal",
                                    "chord": "ctrl+alt+t"
                                }, {
                                    "label": "Run command",
                                    "chord": "alt+f2"
                                }, {
                                    "label": "Close window",
                                    "chord": "alt+f4"
                                }, {
                                    "label": "Terminal copy",
                                    "chord": "ctrl+shift+c"
                                }, {
                                    "label": "Terminal paste",
                                    "chord": "ctrl+shift+v"
                                }, {
                                    "label": "Ctrl+Alt+Enter (remote)",
                                    "chord": "ctrl+alt+enter"
                                }]
                            MenuItem {
                                required property var modelData
                                text: modelData.label
                                onTriggered: root.appState.sendAction({
                                        "action": "send_chord",
                                        "chord": modelData.chord
                                    })
                            }
                        }
                    }
                }
                ToolButton {
                    text: qsTr("Touch")
                    checkable: true
                    checked: root.touchControls
                    onClicked: {
                        root.touchControls = checked;
                        root.restoreFocus();
                    }
                }
                ToolButton {
                    text: root.fullscreen ? qsTr("Window") : qsTr("Fullscreen")
                    onClicked: root.fullscreenRequested()
                    ToolTip.visible: hovered
                    ToolTip.text: "Ctrl+Alt+Enter"
                }
                ToolButton {
                    text: qsTr("Disconnect")
                    onClicked: {
                        root.releaseInput();
                        root.appState.sendAction({
                                "action": "disconnect_session"
                            });
                    }
                }
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            RdpViewport {
                id: viewport
                objectName: "sessionViewport"
                anchors.fill: parent
                enabled: root.inputEnabled
                touchMode: root.appState.touchMode
                remoteWidth: root.appState.remoteWidth
                remoteHeight: root.appState.remoteHeight
                cursorX: root.appState.cursorX
                cursorY: root.appState.cursorY
                movementScale: root.precise ? 0.35 : 1
                dragLocked: root.dragLocked
                onRelativeMove: function (dx, dy) {
                    root.appState.sendAction({
                            "action": "trackpad_move",
                            "dx": dx,
                            "dy": dy
                        });
                }
                onAbsoluteMove: function (rx, ry) {
                    root.appState.sendAction({
                            "action": "pointer_move_abs",
                            "x": rx,
                            "y": ry
                        });
                }
                onMouseClick: function (button, doubleClick, rx, ry) {
                    root.appState.sendAction({
                            "action": "mouse_click",
                            "button": button,
                            "doubleClick": doubleClick,
                            "x": rx,
                            "y": ry
                        });
                }
                onMouseButton: function (button, pressed, rx, ry) {
                    if (pressed)
                        root.restoreFocus();
                    var action = {
                        "action": "mouse_button",
                        "button": button,
                        "pressed": pressed
                    };
                    if (rx >= 0 && ry >= 0) {
                        action.x = rx;
                        action.y = ry;
                    }
                    root.appState.sendAction(action);
                }
                onMouseScroll: function (v, h) {
                    root.appState.sendAction({
                            "action": "mouse_scroll",
                            "vertical": v,
                            "horizontal": h
                        });
                }
            }
            DesktopInput {
                id: hardware
                objectName: "desktopInput"
                anchors.fill: parent
                enabled: root.inputEnabled && !softwareKeyboard.softwareKeyboardRequested
                focus: enabled
                onActionRequested: function (action) {
                    root.appState.sendAction(action);
                }
                onFullscreenRequested: root.fullscreenRequested()
            }
            RemoteKeyboard {
                id: softwareKeyboard
                anchors.fill: parent
                enabled: root.inputEnabled && root.touchControls
                onDispatchAction: function (payload) {
                    root.appState.sendAction(payload);
                }
                onSoftwareKeyboardRequestedChanged: if (!softwareKeyboardRequested)
                    root.restoreFocus()
            }
            Pane {
                anchors.centerIn: parent
                visible: root.appState.sessionStage !== "connected"
                ColumnLayout {
                    Label {
                        text: root.appState.sessionStageDetail || root.appState.sessionStage
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        Layout.maximumWidth: 500
                    }
                    Button {
                        text: root.appState.sessionStage === "error" ? qsTr("Back to PCs") : qsTr("Cancel")
                        onClicked: {
                            root.appState.sendAction({
                                    "action": "disconnect_session"
                                });
                            root.appState.inSessionView = false;
                        }
                    }
                }
            }
        }
        Pane {
            visible: root.touchControls
            Layout.fillWidth: true
            implicitHeight: visible ? controls.implicitHeight + 16 : 0
            Flow {
                id: controls
                width: parent.width
                spacing: 6
                Button {
                    text: qsTr("Keyboard")
                    onClicked: softwareKeyboard.toggleSoftwareKeyboard()
                }
                Button {
                    text: root.appState.touchMode === "direct_touch" ? qsTr("Direct touch") : qsTr("Trackpad")
                    onClicked: {
                        root.releaseInput();
                        root.appState.sendAction({
                                "action": "set_touch_mode",
                                "mode": root.appState.touchMode === "direct_touch" ? "mouse_pointer" : "direct_touch"
                            });
                    }
                }
                Button {
                    text: qsTr("Precise")
                    checkable: true
                    onClicked: {
                        root.precise = checked;
                        root.restoreFocus();
                    }
                }
                Button {
                    text: root.dragLocked ? qsTr("Release drag") : qsTr("Drag")
                    onClicked: {
                        root.dragLocked = !root.dragLocked;
                        root.appState.sendAction({
                                "action": "mouse_button",
                                "button": 1,
                                "pressed": root.dragLocked
                            });
                        root.restoreFocus();
                    }
                }
                Repeater {
                    model: [{
                            "label": "Left",
                            "button": 1,
                            "doubleClick": false
                        }, {
                            "label": "Right",
                            "button": 2,
                            "doubleClick": false
                        }, {
                            "label": "Double",
                            "button": 1,
                            "doubleClick": true
                        }]
                    Button {
                        required property var modelData
                        text: modelData.label
                        onClicked: {
                            root.appState.sendAction({
                                    "action": "mouse_click",
                                    "button": modelData.button,
                                    "doubleClick": modelData.doubleClick
                                });
                            root.restoreFocus();
                        }
                    }
                }
                Repeater {
                    model: ["ctrl", "alt", "shift", "win"]
                    Button {
                        required property string modelData
                        property string stickyState: root.appState[modelData + "State"]
                        text: modelData + (stickyState === "latched" ? " •" : stickyState === "locked" ? " ••" : "")
                        onClicked: {
                            root.appState.sendAction({
                                    "action": "toggle_modifier",
                                    "modifier": modelData
                                });
                            root.restoreFocus();
                        }
                    }
                }
                Repeater {
                    model: ["Esc", "Tab", "Bksp", "Enter", "Up", "Down", "Left", "Right", "Home", "End", "PgUp", "PgDn", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]
                    Button {
                        required property string modelData
                        text: modelData
                        onClicked: {
                            root.appState.sendAction({
                                    "action": "send_virtual_key",
                                    "key": modelData
                                });
                            root.restoreFocus();
                        }
                    }
                }
            }
        }
    }
}
