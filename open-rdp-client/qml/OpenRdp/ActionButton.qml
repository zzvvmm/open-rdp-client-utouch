import QtQuick 2.12

Rectangle {
    id: root
    property string text: ""
    property url iconSource: ""
    property string accessibleName: text
    property bool primary: false
    property bool selected: false
    property bool destructive: false
    signal clicked
    implicitHeight: Math.max(Design.targetSize, label.implicitHeight + 24)
    implicitWidth: Math.max(Design.targetSize, label.implicitWidth + (icon.visible ? 28 : 0) + 28)
    radius: 8
    color: primary ? (mouse.pressed ? "#005DA6" : mouse.containsMouse ? "#1688DF" : Design.accent) : (mouse.pressed || mouse.containsMouse ? Design.hover : selected ? Design.selected : "transparent")
    border.width: activeFocus ? 2 : selected ? 1 : 0
    border.color: Design.accent
    opacity: enabled ? 1 : 0.45
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.onPressAction: if (enabled)
        clicked()
    Keys.onPressed: {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat)
                root.clicked();
            event.accepted = true;
        }
    }
    Row {
        anchors.centerIn: parent
        spacing: 8
        Image {
            id: icon
            visible: root.iconSource.toString().length > 0
            source: root.iconSource
            width: 20
            height: 20
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            id: label
            text: root.text
            textFormat: Text.PlainText
            color: root.primary ? "white" : root.destructive ? Design.danger : Design.text
            font.pixelSize: Design.textSize
            font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.clicked();
        }
    }
}
