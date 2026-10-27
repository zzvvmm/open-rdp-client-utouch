import QtQuick 2.12
import Lomiri.Components 1.3
import RdpClient 1.0

Item {
    id: root

    property string touchMode: "direct_touch"
    property int remoteWidth: 1280
    property int remoteHeight: 720
    property int cursorX: 640
    property int cursorY: 360
    property real zoomFactor: 1.0
    property real movementScale: 1.0
    property bool dragLocked: false

    signal relativeMove(real dx, real dy)
    signal absoluteMove(int rx, int ry)
    signal mouseClick(int button, bool doubleClick, int rx, int ry)
    signal mouseButton(int button, bool pressed, int rx, int ry)
    signal mouseScroll(int verticalDelta, int horizontalDelta)

    function refreshCanvas() {
        rdpCanvas.requestRepaint()
    }

    function resetZoom() {
        root.zoomFactor = 1.0
        viewportFlickable.contentX = 0
        viewportFlickable.contentY = 0
    }

    function cancelInput() {
        trackpad.cancelInput()
    }

    function followCursor() {
        if (!viewportFlickable || !rdpCanvas) return
        if (zoomFactor <= 1.01) {
            viewportFlickable.contentX = 0
            viewportFlickable.contentY = 0
            return
        }
        if (touchMode !== "mouse_pointer") return
        var pointerX = rdpCanvas.x + cursorX / Math.max(1, remoteWidth - 1) * rdpCanvas.width
        var pointerY = rdpCanvas.y + cursorY / Math.max(1, remoteHeight - 1) * rdpCanvas.height
        var marginX = Math.min(units.gu(6), width / 4)
        var marginY = Math.min(units.gu(6), height / 4)
        var offsetX = viewportFlickable.contentX
        var offsetY = viewportFlickable.contentY
        if (pointerX < offsetX + marginX) offsetX = pointerX - marginX
        else if (pointerX > offsetX + width - marginX) offsetX = pointerX - width + marginX
        if (pointerY < offsetY + marginY) offsetY = pointerY - marginY
        else if (pointerY > offsetY + height - marginY) offsetY = pointerY - height + marginY
        viewportFlickable.contentX = Math.max(0, Math.min(viewportFlickable.contentWidth - width, offsetX))
        viewportFlickable.contentY = Math.max(0, Math.min(viewportFlickable.contentHeight - height, offsetY))
    }

    onCursorXChanged: followCursor()
    onCursorYChanged: followCursor()
    onZoomFactorChanged: Qt.callLater(followCursor)
    onWidthChanged: Qt.callLater(followCursor)
    onHeightChanged: Qt.callLater(followCursor)
    onRemoteWidthChanged: Qt.callLater(followCursor)
    onRemoteHeightChanged: Qt.callLater(followCursor)
    onTouchModeChanged: Qt.callLater(followCursor)

    Rectangle {
        anchors.fill: parent
        color: "#0A0D12"
    }

    Flickable {
        id: viewportFlickable
        anchors.fill: parent
        contentWidth: Math.max(width, width * root.zoomFactor)
        contentHeight: Math.max(height, height * root.zoomFactor)
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Item {
            id: stageContainer
            width: viewportFlickable.contentWidth
            height: viewportFlickable.contentHeight

            readonly property real aspect: root.remoteWidth / Math.max(1, root.remoteHeight)
            readonly property real fittedW: Math.min(width, height * aspect)
            readonly property real fittedH: fittedW / Math.max(0.1, aspect)

            RdpCanvas {
                id: rdpCanvas
                width: stageContainer.fittedW
                height: stageContainer.fittedH
                anchors.centerIn: parent
                controller: RdpBridge
            }

            VirtualTrackpad {
                id: trackpad
                anchors.fill: parent
                touchMode: root.touchMode
                remoteWidth: root.remoteWidth
                remoteHeight: root.remoteHeight
                cursorX: root.cursorX
                cursorY: root.cursorY
                canvasX: rdpCanvas.x
                canvasY: rdpCanvas.y
                canvasW: rdpCanvas.width
                canvasH: rdpCanvas.height
                movementScale: root.movementScale
                dragLocked: root.dragLocked

                onRelativeMove: root.relativeMove(dx, dy)
                onAbsoluteMove: root.absoluteMove(rx, ry)
                onMouseClick: root.mouseClick(button, doubleClick, rx, ry)
                onMouseButton: root.mouseButton(button, pressed, rx, ry)
                onMouseScroll: root.mouseScroll(verticalDelta, horizontalDelta)
            }
        }
    }
}
