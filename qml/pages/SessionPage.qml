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
    property bool dragLocked: false
    property bool precisionMode: false

    signal dispatchAction(var payload)
    signal exitSessionView()

    function notifyFrameUpdated() {
        viewport.refreshCanvas()
    }

    function restoreKeyboardFocus() {
        Qt.callLater(function() {
            oskInput.restoreFocus()
        })
    }

    function releasePointer() {
        if (dragLocked) root.dispatchAction({ action: "mouse_button", button: 1, pressed: false })
        dragLocked = false
        if (viewport) viewport.cancelInput()
    }

    onVisibleChanged: {
        if (!visible) {
            releasePointer()
            oskInput.hideSoftwareKeyboard()
        } else restoreKeyboardFocus()
    }
    onSessionStageChanged: {
        if (sessionStage !== "connected") releasePointer()
        else restoreKeyboardFocus()
    }
    onPendingCertChanged: {
        if (pendingCert !== null) releasePointer()
        else restoreKeyboardFocus()
    }

    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive) {
                root.releasePointer()
                oskInput.hideSoftwareKeyboard()
            } else root.restoreKeyboardFocus()
        }
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
    RemoteKeyboard {
        id: oskInput
        enabled: root.visible && root.sessionStage === "connected" && root.pendingCert === null
        focus: enabled
        onDispatchAction: root.dispatchAction(payload)
    }

    // Remote Desktop Canvas Viewport
    RdpViewport {
        id: viewport
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: pointerControls.top
        enabled: root.visible && root.sessionStage === "connected" && root.pendingCert === null

        touchMode: root.touchMode
        remoteWidth: root.remoteWidth
        remoteHeight: root.remoteHeight
        cursorX: root.cursorX
        cursorY: root.cursorY
        movementScale: root.precisionMode ? 0.35 : 1.0
        dragLocked: root.dragLocked

        onRelativeMove: {
            if (!oskInput.activeFocus) root.restoreKeyboardFocus()
            root.dispatchAction({
                action: "trackpad_move",
                dx: dx,
                dy: dy
            })
        }
        onAbsoluteMove: {
            if (!oskInput.activeFocus) root.restoreKeyboardFocus()
            root.dispatchAction({
                action: "pointer_move_abs",
                x: rx,
                y: ry
            })
        }
        onMouseClick: {
            root.restoreKeyboardFocus()
            root.dispatchAction({
                action: "mouse_click",
                button: button,
                doubleClick: doubleClick,
                x: rx,
                y: ry
            })
        }
        onMouseButton: {
            root.restoreKeyboardFocus()
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
        keyboardVisible: oskInput.softwareKeyboardRequested
        zoomFactor: viewport.zoomFactor
        currentFps: root.currentFps
        resolutionText: root.remoteWidth + "×" + root.remoteHeight
        showStats: root.showStats

        onToggleTouchMode: {
            root.releasePointer()
            var nextMode = root.touchMode === "mouse_pointer" ? "direct_touch" : "mouse_pointer"
            root.dispatchAction({
                action: "set_touch_mode",
                mode: nextMode
            })
            root.restoreKeyboardFocus()
        }
        onToggleKeyboard: oskInput.toggleSoftwareKeyboard()
        onCycleZoom: {
            if (viewport.zoomFactor < 1.4) {
                viewport.zoomFactor = 1.5
            } else if (viewport.zoomFactor < 1.9) {
                viewport.zoomFactor = 2.0
            } else {
                viewport.resetZoom()
            }
            root.restoreKeyboardFocus()
        }
        onSendChordRequested: {
            root.dispatchAction({
                action: "send_chord",
                chord: chord
            })
            root.restoreKeyboardFocus()
        }
        onDisconnectRequested: {
            root.releasePointer()
            root.dispatchAction({ action: "disconnect_session" })
            root.exitSessionView()
        }
    }

    PointerControls {
        id: pointerControls
        visible: root.sessionStage === "connected" && root.pendingCert === null
        height: visible ? units.gu(5.6) : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: vKeyBar.visible ? vKeyBar.top : parent.bottom
        dragLocked: root.dragLocked
        precisionMode: root.precisionMode

        onClickRequested: {
            root.releasePointer()
            root.dispatchAction({ action: "mouse_click", button: button, doubleClick: doubleClick })
            root.restoreKeyboardFocus()
        }
        onToggleDragRequested: {
            viewport.cancelInput()
            root.dragLocked = !root.dragLocked
            root.dispatchAction({ action: "mouse_button", button: 1, pressed: root.dragLocked })
            root.restoreKeyboardFocus()
        }
        onTogglePrecisionRequested: {
            root.precisionMode = !root.precisionMode
            root.restoreKeyboardFocus()
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
            root.restoreKeyboardFocus()
        }
        onVirtualKeyTapped: {
            root.dispatchAction({
                action: "send_virtual_key",
                key: keyName
            })
            root.restoreKeyboardFocus()
        }
        onChordTapped: {
            root.dispatchAction({
                action: "send_chord",
                chord: chordName
            })
            root.restoreKeyboardFocus()
        }
        onSummonOskRequested: oskInput.toggleSoftwareKeyboard()
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
