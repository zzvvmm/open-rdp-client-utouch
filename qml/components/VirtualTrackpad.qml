import QtQuick 2.12
import Lomiri.Components 1.3

Item {
    id: root

    property string touchMode: "direct_touch" // "mouse_pointer" or "direct_touch"
    property int remoteWidth: 1280
    property int remoteHeight: 720
    property int cursorX: 640
    property int cursorY: 360
    property real canvasX: 0
    property real canvasY: 0
    property real canvasW: width
    property real canvasH: height
    property real movementScale: 1.0
    property bool dragLocked: false
    property int gestureState: 0
    property bool dragSelecting: false
    property bool holdTriggered: false
    property bool singleFingerMoved: false
    property bool twoFingerMoved: false
    property real startX: 0
    property real startY: 0
    property real lastX: 0
    property real lastY: 0
    property real scrollRemainderX: 0
    property real scrollRemainderY: 0
    property double pressTimestamp: 0

    signal relativeMove(real dx, real dy)
    signal absoluteMove(int rx, int ry)
    signal mouseClick(int button, bool doubleClick, int rx, int ry)
    signal mouseButton(int button, bool pressed, int rx, int ry)
    signal mouseScroll(int verticalDelta, int horizontalDelta)

    function toRemoteX(localX) {
        if (canvasW <= 1) return 0
        var norm = (localX - canvasX) / canvasW
        norm = Math.max(0.0, Math.min(1.0, norm))
        return Math.round(norm * (remoteWidth - 1))
    }

    function toRemoteY(localY) {
        if (canvasH <= 1) return 0
        var norm = (localY - canvasY) / canvasH
        norm = Math.max(0.0, Math.min(1.0, norm))
        return Math.round(norm * (remoteHeight - 1))
    }

    function insideCanvas(localX, localY) {
        return localX >= canvasX && localX <= canvasX + canvasW
                && localY >= canvasY && localY <= canvasY + canvasH
    }

    function releaseTouchButton() {
        if (dragSelecting) root.mouseButton(1, false, -1, -1)
        dragSelecting = false
    }

    function cancelTouch() {
        longPressTimer.stop()
        releaseTouchButton()
        gestureState = 0
        holdRing.visible = false
    }

    function cancelInput() {
        cancelTouch()
        if (desktopMouse) desktopMouse.releaseButtons()
    }

    function beginSingle(localX, localY) {
        cancelTouch()
        if (touchMode === "direct_touch" && !insideCanvas(localX, localY)) return
        gestureState = 1
        startX = lastX = localX
        startY = lastY = localY
        pressTimestamp = Date.now()
        holdTriggered = false
        singleFingerMoved = false
        longPressTimer.restart()
    }

    function beginTwo(localX, localY) {
        if (touchMode === "direct_touch" && !insideCanvas(localX, localY)) {
            cancelTouch()
            gestureState = 3
            return
        }
        longPressTimer.stop()
        releaseTouchButton()
        holdRing.visible = false
        gestureState = 2
        twoFingerMoved = false
        startX = lastX = localX
        startY = lastY = localY
        scrollRemainderX = scrollRemainderY = 0
        pressTimestamp = Date.now()
        if (touchMode === "direct_touch" && insideCanvas(localX, localY))
            absoluteMove(toRemoteX(localX), toRemoteY(localY))
    }

    function updateSingle(localX, localY) {
        if (gestureState !== 1) return
        var deltaX = localX - lastX
        var deltaY = localY - lastY
        lastX = localX
        lastY = localY
        var moved = Math.hypot(localX - startX, localY - startY) > units.gu(1.2)
        if (moved) {
            singleFingerMoved = true
            longPressTimer.stop()
            if (touchMode === "direct_touch" && !holdTriggered && !dragSelecting && !dragLocked) {
                dragSelecting = true
                mouseButton(1, true, toRemoteX(startX), toRemoteY(startY))
            }
        }
        if (touchMode === "mouse_pointer") {
            relativeMove(deltaX * remoteWidth / Math.max(1, canvasW) * movementScale,
                         deltaY * remoteHeight / Math.max(1, canvasH) * movementScale)
        } else if (!holdTriggered) {
            absoluteMove(toRemoteX(localX), toRemoteY(localY))
        }
    }

    function updateTwo(localX, localY) {
        if (gestureState !== 2) return
        if (!twoFingerMoved && Math.hypot(localX - startX, localY - startY) < units.gu(0.6)) return
        twoFingerMoved = true
        var vertical = (localY - lastY) * 3 + scrollRemainderY
        var horizontal = (lastX - localX) * 3 + scrollRemainderX
        var verticalUnits = Math.round(vertical)
        var horizontalUnits = Math.round(horizontal)
        scrollRemainderY = vertical - verticalUnits
        scrollRemainderX = horizontal - horizontalUnits
        lastX = localX
        lastY = localY
        if (verticalUnits || horizontalUnits) mouseScroll(verticalUnits, horizontalUnits)
    }

    function finishTouch() {
        longPressTimer.stop()
        holdRing.visible = false
        var elapsed = Date.now() - pressTimestamp
        if (gestureState === 2) {
            if (!twoFingerMoved && elapsed < 350 && !dragLocked)
                mouseClick(2, false, touchMode === "direct_touch" ? toRemoteX(startX) : -1,
                           touchMode === "direct_touch" ? toRemoteY(startY) : -1)
        } else if (gestureState === 1) {
            if (dragSelecting) {
                releaseTouchButton()
            } else if (!holdTriggered && !dragLocked && !singleFingerMoved && elapsed < 350) {
                mouseClick(1, false, touchMode === "direct_touch" ? toRemoteX(startX) : -1,
                           touchMode === "direct_touch" ? toRemoteY(startY) : -1)
            }
        }
        gestureState = 0
    }

    onTouchModeChanged: cancelInput()
    onDragLockedChanged: cancelTouch()
    onVisibleChanged: if (!visible) cancelInput()

    Timer {
        id: longPressTimer
        interval: 520
        repeat: false
        onTriggered: {
            if (root.gestureState !== 1 || root.dragLocked) return
            if (root.touchMode === "direct_touch") {
                root.holdTriggered = true
                holdRing.x = root.startX - holdRing.width / 2
                holdRing.y = root.startY - holdRing.height / 2
                holdRing.visible = true
                root.mouseClick(2, false, root.toRemoteX(root.startX), root.toRemoteY(root.startY))
            } else {
                root.dragSelecting = true
                root.mouseButton(1, true, -1, -1)
            }
        }
    }

    // Visual Local Cursor in Mouse Pointer (Trackpad) Mode
    Item {
        id: pointerCursor
        visible: root.touchMode === "mouse_pointer" || desktopMouse.containsMouse
        x: root.canvasX + (root.cursorX / Math.max(1, root.remoteWidth - 1)) * root.canvasW
        y: root.canvasY + (root.cursorY / Math.max(1, root.remoteHeight - 1)) * root.canvasH
        z: 20

        // Crisp white pointer arrow with dark outline
        Canvas {
            width: units.gu(3)
            height: units.gu(3)
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.beginPath()
                ctx.moveTo(1, 1)
                ctx.lineTo(1, 20)
                ctx.lineTo(6, 15)
                ctx.lineTo(10, 23)
                ctx.lineTo(13, 21)
                ctx.lineTo(9, 13)
                ctx.lineTo(16, 13)
                ctx.closePath()
                ctx.fillStyle = "#FFFFFF"
                ctx.fill()
                ctx.lineWidth = 1.6
                ctx.strokeStyle = "#11151C"
                ctx.stroke()
            }
        }
    }

    // Visual Right-Click Hold Indicator Square (Windows App Direct Touch style)
    Rectangle {
        id: holdRing
        width: units.gu(5)
        height: units.gu(5)
        radius: units.gu(0.8)
        color: "#330078D4"
        border.width: units.dp(2)
        border.color: "#29B6F6"
        visible: false
        z: 25
    }

    MouseArea {
        id: desktopMouse
        objectName: "desktopMouse"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.BlankCursor
        property int remoteButtons: 0

        function releaseButtons() {
            for (var button = 1; button <= 4; button *= 2) {
                if (remoteButtons & button) root.mouseButton(button, false, -1, -1)
            }
            remoteButtons = 0
        }

        onPressed: {
            if (!root.insideCanvas(mouse.x, mouse.y)) return
            remoteButtons |= mouse.button
            root.mouseButton(mouse.button, true, root.toRemoteX(mouse.x), root.toRemoteY(mouse.y))
        }
        onPositionChanged: {
            if (root.insideCanvas(mouse.x, mouse.y) || remoteButtons)
                root.absoluteMove(root.toRemoteX(mouse.x), root.toRemoteY(mouse.y))
        }
        onReleased: {
            if (remoteButtons & mouse.button) {
                remoteButtons &= ~mouse.button
                root.mouseButton(mouse.button, false, root.toRemoteX(mouse.x), root.toRemoteY(mouse.y))
            }
        }
        onCanceled: releaseButtons()
        onWheel: root.mouseScroll(wheel.angleDelta.y, wheel.angleDelta.x)
    }

    MultiPointTouchArea {
        id: touchArea
        anchors.fill: parent
        minimumTouchPoints: 1
        maximumTouchPoints: 2
        mouseEnabled: false

        touchPoints: [
            TouchPoint { id: tp1 },
            TouchPoint { id: tp2 }
        ]

        onPressed: {
            if (tp1.pressed && tp2.pressed) {
                root.beginTwo((tp1.x + tp2.x) / 2, (tp1.y + tp2.y) / 2)
            } else if (root.gestureState === 0) {
                var point = tp1.pressed ? tp1 : tp2
                root.beginSingle(point.x, point.y)
            }
        }
        onUpdated: {
            if (tp1.pressed && tp2.pressed) {
                root.updateTwo((tp1.x + tp2.x) / 2, (tp1.y + tp2.y) / 2)
            } else if (root.gestureState === 1) {
                var point = tp1.pressed ? tp1 : tp2
                root.updateSingle(point.x, point.y)
            }
        }
        onReleased: {
            if (!tp1.pressed && !tp2.pressed) root.finishTouch()
        }
        onCanceled: root.cancelTouch()
        onGestureStarted: gesture.grab()
    }
}
