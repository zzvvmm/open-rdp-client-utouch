import QtQuick 2.12
import Lomiri.Components 1.3

Item {
    id: root

    property string touchMode: "mouse_pointer" // "mouse_pointer" or "direct_touch"
    property int remoteWidth: 1280
    property int remoteHeight: 720
    property int cursorX: 640
    property int cursorY: 360
    property real canvasX: 0
    property real canvasY: 0
    property real canvasW: width
    property real canvasH: height

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

    // Visual Local Cursor in Mouse Pointer (Trackpad) Mode
    Item {
        id: pointerCursor
        visible: root.touchMode === "mouse_pointer"
        x: root.canvasX + (root.cursorX / Math.max(1, root.remoteWidth)) * root.canvasW
        y: root.canvasY + (root.cursorY / Math.max(1, root.remoteHeight)) * root.canvasH
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

    MultiPointTouchArea {
        id: touchArea
        anchors.fill: parent
        minimumTouchPoints: 1
        maximumTouchPoints: 2

        property real lastP1X: 0
        property real lastP1Y: 0
        property real startP1X: 0
        property real startP1Y: 0
        property real lastP2Y: 0
        property real lastP2X: 0
        property bool twoFingerActive: false
        property bool twoFingerMoved: false
        property bool dragSelecting: false
        property double pressTimestamp: 0
        property double lastTapTimestamp: 0

        touchPoints: [
            TouchPoint { id: tp1 },
            TouchPoint { id: tp2 }
        ]

        Timer {
            id: longPressTimer
            interval: 520
            repeat: false
            onTriggered: {
                if (touchArea.twoFingerActive) return
                var dist = Math.hypot(tp1.x - touchArea.startP1X, tp1.y - touchArea.startP1Y)
                if (dist < units.gu(1.5)) {
                    if (root.touchMode === "direct_touch") {
                        holdRing.x = tp1.x - holdRing.width / 2
                        holdRing.y = tp1.y - holdRing.height / 2
                        holdRing.visible = true
                        var rx = root.toRemoteX(tp1.x)
                        var ry = root.toRemoteY(tp1.y)
                        root.mouseClick(2, false, rx, ry)
                    } else {
                        touchArea.dragSelecting = true
                        root.mouseButton(1, true, root.cursorX, root.cursorY)
                    }
                }
            }
        }

        onPressed: {
            holdRing.visible = false
            if (tp1.pressed && tp2.pressed) {
                twoFingerActive = true
                twoFingerMoved = false
                longPressTimer.stop()
                lastP2X = (tp1.x + tp2.x) / 2
                lastP2Y = (tp1.y + tp2.y) / 2
            } else if (tp1.pressed) {
                twoFingerActive = false
                dragSelecting = false
                startP1X = tp1.x
                startP1Y = tp1.y
                lastP1X = tp1.x
                lastP1Y = tp1.y
                pressTimestamp = Date.now()
                longPressTimer.restart()
            }
        }

        onUpdated: {
            if (tp1.pressed && tp2.pressed) {
                twoFingerActive = true
                var midX = (tp1.x + tp2.x) / 2
                var midY = (tp1.y + tp2.y) / 2
                var dy = midY - lastP2Y
                var dx = midX - lastP2X
                if (Math.abs(dy) > units.gu(0.8) || Math.abs(dx) > units.gu(0.8)) {
                    twoFingerMoved = true
                    var vUnits = Math.round(dy * 2.5)
                    var hUnits = Math.round(-dx * 2.5)
                    root.mouseScroll(vUnits, hUnits)
                    lastP2X = midX
                    lastP2Y = midY
                }
                return
            }

            if (tp1.pressed && !twoFingerActive) {
                var deltaX = tp1.x - lastP1X
                var deltaY = tp1.y - lastP1Y
                lastP1X = tp1.x
                lastP1Y = tp1.y

                if (Math.hypot(tp1.x - startP1X, tp1.y - startP1Y) > units.gu(1.2)) {
                    longPressTimer.stop()
                }

                if (root.touchMode === "mouse_pointer") {
                    var scaleX = root.remoteWidth / Math.max(1, root.canvasW)
                    var scaleY = root.remoteHeight / Math.max(1, root.canvasH)
                    root.relativeMove(deltaX * scaleX, deltaY * scaleY)
                } else {
                    var rx = root.toRemoteX(tp1.x)
                    var ry = root.toRemoteY(tp1.y)
                    root.absoluteMove(rx, ry)
                }
            }
        }

        onReleased: {
            longPressTimer.stop()
            holdRing.visible = false

            if (twoFingerActive && !tp1.pressed && !tp2.pressed) {
                if (!twoFingerMoved) {
                    // 2-finger tap = Right Click
                    root.mouseClick(2, false, root.cursorX, root.cursorY)
                }
                twoFingerActive = false
                return
            }

            if (dragSelecting) {
                dragSelecting = false
                root.mouseButton(1, false, root.cursorX, root.cursorY)
                return
            }

            var elapsed = Date.now() - pressTimestamp
            var totalMove = Math.hypot(tp1.x - startP1X, tp1.y - startP1Y)
            if (elapsed < 350 && totalMove < units.gu(1.5)) {
                var now = Date.now()
                var isDouble = (now - lastTapTimestamp) < 320
                lastTapTimestamp = now

                if (root.touchMode === "direct_touch") {
                    var rx = root.toRemoteX(startP1X)
                    var ry = root.toRemoteY(startP1Y)
                    root.mouseClick(1, isDouble, rx, ry)
                } else {
                    root.mouseClick(1, isDouble, root.cursorX, root.cursorY)
                }
            }
        }
    }

    // Support desktop mouse wheel in Lomiri Convergence mode
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.MiddleButton
        hoverEnabled: false
        onClicked: {
            var btn = (mouse.button === Qt.RightButton) ? 2 : 4
            if (root.touchMode === "direct_touch") {
                root.mouseClick(btn, false, root.toRemoteX(mouse.x), root.toRemoteY(mouse.y))
            } else {
                root.mouseClick(btn, false, root.cursorX, root.cursorY)
            }
        }
        onWheel: {
            var vDelta = Math.round(wheel.angleDelta.y / 2)
            var hDelta = Math.round(wheel.angleDelta.x / 2)
            root.mouseScroll(vDelta, hDelta)
        }
    }
}
