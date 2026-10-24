import QtQuick 2.12
import Lomiri.Components 1.3
import "../components"

Item {
    id: root

    property string pcTitle: "Remote PC"
    property string sessionStage: "disconnected"
    property string stageDetail: ""
    property string touchMode: "mouse_pointer"
    property int remoteWidth: 1280
    property int remoteHeight: 720
    property int cursorX: 640
    property int cursorY: 360
    property int currentFps: 60
    property bool showStats: false
    property string ctrlState: "off"
    property string altState: "off"
    property string shiftState: "off"
    property string winState: "off"
    property var pendingCert: null
    property bool keyBarVisible: true

    signal dispatchAction(var payload)
    signal exitSessionView()

    function notifyFrameUpdated() {
        viewport.refreshCanvas()
    }

    // Dynamic Display Resize (DISP DVC) debounce when phone rotates or Convergence window resizes
    Timer {
        id: resizeDebounce
        interval: 350
        repeat: false
        onTriggered: {
            if (root.sessionStage === "connected" && viewport.width >= 320 && viewport.height >= 240) {
                root.dispatchAction({
                    action: "resize_session",
                    width: Math.round(viewport.width),
                    height: Math.round(viewport.height),
                    scaleFactor: 100
                })
            }
        }
    }

    onWidthChanged: resizeDebounce.restart()
    onHeightChanged: resizeDebounce.restart()

    // Hidden input to summon Lomiri OSK and capture hardware/OSK keyboard input
    TextInput {
        id: oskInput
        width: 1
        height: 1
        opacity: 0
        focus: root.visible && root.pendingCert === null
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

        onTextChanged: {
            if (text.length > 0) {
                root.dispatchAction({
                    action: "send_qt_key",
                    qtKey: 0,
                    text: text,
                    pressed: true
                })
                text = ""
            }
        }

        Keys.onPressed: {
            if (event.key === Qt.Key_Backspace) {
                root.dispatchAction({ action: "send_virtual_key", key: "Bksp" })
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.dispatchAction({ action: "send_virtual_key", key: "Enter" })
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                root.dispatchAction({ action: "send_virtual_key", key: "Esc" })
                event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
                root.dispatchAction({ action: "send_virtual_key", key: "Tab" })
                event.accepted = true
            } else if (event.key >= Qt.Key_Home && event.key <= Qt.Key_PageDown) {
                root.dispatchAction({
                    action: "send_qt_key",
                    qtKey: event.key,
                    text: "",
                    pressed: true
                })
                event.accepted = true
            }
        }
    }

    // Remote Desktop Canvas Viewport
    RdpViewport {
        id: viewport
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: vKeyBar.visible ? vKeyBar.top : parent.bottom

        touchMode: root.touchMode
        remoteWidth: root.remoteWidth
        remoteHeight: root.remoteHeight
        cursorX: root.cursorX
        cursorY: root.cursorY

        onRelativeMove: {
            root.dispatchAction({
                action: "trackpad_move",
                dx: dx,
                dy: dy
            })
        }
        onAbsoluteMove: {
            root.dispatchAction({
                action: "pointer_move_abs",
                x: rx,
                y: ry
            })
        }
        onMouseClick: {
            root.dispatchAction({
                action: "mouse_click",
                button: button,
                doubleClick: doubleClick,
                x: rx,
                y: ry
            })
        }
        onMouseButton: {
            root.dispatchAction({
                action: "mouse_button",
                button: button,
                pressed: pressed,
                x: rx,
                y: ry
            })
        }
        onMouseScroll: {
            root.dispatchAction({
                action: "mouse_scroll",
                vertical: verticalDelta,
                horizontal: horizontalDelta
            })
        }
    }

    // Floating Windows App Session HUD Pill & Control Bar
    SessionHudPill {
        anchors.fill: viewport
        pcTitle: root.pcTitle
        touchMode: root.touchMode
        keyboardVisible: root.keyBarVisible
        zoomFactor: viewport.zoomFactor
        currentFps: root.currentFps
        resolutionText: root.remoteWidth + "×" + root.remoteHeight
        showStats: root.showStats

        onToggleTouchMode: {
            var nextMode = root.touchMode === "mouse_pointer" ? "direct_touch" : "mouse_pointer"
            root.dispatchAction({
                action: "set_touch_mode",
                mode: nextMode
            })
        }
        onToggleKeyboard: {
            root.keyBarVisible = !root.keyBarVisible
            if (root.keyBarVisible) {
                oskInput.forceActiveFocus()
                Qt.inputMethod.show()
            } else {
                Qt.inputMethod.hide()
            }
        }
        onCycleZoom: {
            if (viewport.zoomFactor < 1.4) {
                viewport.zoomFactor = 1.5
            } else if (viewport.zoomFactor < 1.9) {
                viewport.zoomFactor = 2.0
            } else {
                viewport.resetZoom()
            }
        }
        onSendChordRequested: {
            root.dispatchAction({
                action: "send_chord",
                chord: chord
            })
        }
        onDisconnectRequested: {
            root.dispatchAction({ action: "disconnect_session" })
            root.exitSessionView()
        }
    }

    // Extended Modifier & Function Key Bar
    VirtualKeyBar {
        id: vKeyBar
        visible: root.keyBarVisible
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        ctrlState: root.ctrlState
        altState: root.altState
        shiftState: root.shiftState
        winState: root.winState

        onModifierTapped: {
            root.dispatchAction({
                action: "toggle_modifier",
                modifier: modifierName
            })
        }
        onVirtualKeyTapped: {
            root.dispatchAction({
                action: "send_virtual_key",
                key: keyName
            })
        }
        onChordTapped: {
            root.dispatchAction({
                action: "send_chord",
                chord: chordName
            })
        }
        onSummonOskRequested: {
            oskInput.forceActiveFocus()
            Qt.inputMethod.show()
        }
    }

    // Connection Progress / Handshake Overlay
    Rectangle {
        visible: root.sessionStage !== "connected" && root.pendingCert === null
        anchors.fill: parent
        color: "#E60E131B"
        z: 70

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - units.gu(6), units.gu(44))
            spacing: units.gu(2)

            ActivityIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.sessionStage !== "error" && root.sessionStage !== "disconnected"
            }

            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.pcTitle
                fontSize: "large"
                font.bold: true
                color: "#F3F6FA"
            }

            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.stageDetail.length > 0 ? root.stageDetail : i18n.tr("Connecting to remote PC…")
                fontSize: "small"
                color: root.sessionStage === "error" ? "#FCA5A5" : "#29B6F6"
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(20)
                text: root.sessionStage === "error" ? i18n.tr("Back to PCs") : i18n.tr("Cancel")
                color: "#3A1E24"
                onClicked: {
                    root.dispatchAction({ action: "disconnect_session" })
                    root.exitSessionView()
                }
            }
        }
    }

    // TOFU Certificate Inspection & Trust Dialog
    CertPromptDialog {
        certData: root.pendingCert
        onDecisionMade: {
            root.pendingCert = null
            root.dispatchAction({
                action: "respond_certificate",
                decision: decision
            })
            if (decision === "reject") {
                root.exitSessionView()
            }
        }
    }
}
