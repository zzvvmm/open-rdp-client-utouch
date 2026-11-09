import QtQuick 2.12

Rectangle {
    id: root
    property var pc: ({})
    property bool compact: false
    readonly property bool hidePreview: compact && width < 500 && Design.textSize > 20
    property string sessionBadge: ""
    property string connectText: qsTr("Connect")
    property string favoriteName: qsTr("Toggle favorite")
    property string actionsName: qsTr("PC actions")
    property string neverConnectedText: qsTr("Never connected")
    property string lastConnectedText: qsTr("Last connected")
    property string demoText: qsTr("Offline demo")
    activeFocusOnTab: true
    Accessible.role: Accessible.ListItem
    Accessible.name: (pc.displayTitle || "") + " " + (pc.address || "")
    Accessible.onPressAction: connectRequested()
    Keys.onReturnPressed: connectRequested()
    Keys.onEnterPressed: connectRequested()
    signal connectRequested
    signal favoriteRequested
    signal actionsRequested
    implicitHeight: (compact ? 104 : Math.round(width * 9 / 16) + 164) + Math.max(0, Design.textSize - 14) * 5
    radius: Design.radius
    color: Design.surface
    border.color: sessionBadge || activeFocus ? Design.accent : Design.border
    border.width: sessionBadge || activeFocus ? 2 : 1
    PcLibrary {
        id: urls
    }
    Rectangle {
        id: preview
        visible: !root.hidePreview
        x: root.compact ? 12 : 1
        y: root.compact ? 20 : 1
        width: root.compact ? 60 : root.width - 2
        height: root.compact ? 62 : Math.round(width * 9 / 16)
        color: Design.navigation
        radius: Design.radius
        clip: true
        Image {
            anchors.fill: parent
            anchors.margins: 8
            source: "qrc:/assets/icons/pc-card.svg"
            fillMode: Image.PreserveAspectFit
            visible: thumbnail.status !== Image.Ready
        }
        Image {
            id: thumbnail
            anchors.fill: parent
            source: urls.thumbnailUrl(root.pc.thumbnailPath)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }
        Rectangle {
            visible: !root.compact && (root.sessionBadge.length > 0 || !!root.pc.isDemo)
            x: 10
            y: 10
            width: badge.implicitWidth + 16
            height: 26
            radius: 8
            color: root.sessionBadge ? Design.accent : "#17665F"
            Text {
                id: badge
                anchors.centerIn: parent
                text: root.sessionBadge || root.demoText
                color: "white"
                font.pixelSize: Design.textSize - 2
            }
        }
    }
    Column {
        x: root.compact ? (root.hidePreview ? 16 : 84) : 16
        y: root.compact ? 8 : preview.height + 14
        width: root.width - x - (root.compact ? (root.width > 650 ? 250 : 108) : 16)
        spacing: 5
        Text {
            width: parent.width
            text: root.pc.displayTitle || ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Design.text
            font.pixelSize: Design.textSize + 2
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: root.pc.address || ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Design.secondaryText
            font.pixelSize: Design.textSize - 1
        }
        Text {
            width: parent.width
            text: (root.pc.groupName || "Saved PCs") + (root.sessionBadge && root.compact ? " · " + root.sessionBadge : "")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Design.secondaryText
            font.pixelSize: Design.textSize - 2
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: root.pc.lastConnectedEpoch > 0 ? root.lastConnectedText + ": " + new Date(root.pc.lastConnectedEpoch * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat) : root.neverConnectedText
            color: Design.secondaryText
            font.pixelSize: Design.textSize - 2
        }
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.compact ? 28 : 8
        spacing: 0
        ActionButton {
            visible: !root.compact || root.width > 650
            text: root.connectText
            primary: true
            onClicked: root.connectRequested()
        }
        ActionButton {
            width: 48
            text: root.pc.favorite ? "★" : "☆"
            accessibleName: root.favoriteName
            onClicked: root.favoriteRequested()
        }
        ActionButton {
            width: 48
            text: "⋯"
            accessibleName: root.actionsName
            onClicked: root.actionsRequested()
        }
    }
    MouseArea {
        x: root.compact ? 0 : preview.x
        y: root.compact ? 0 : preview.y
        width: root.compact ? Math.max(0, root.width - (root.width > 650 ? 250 : 108)) : preview.width
        height: root.compact ? root.height : preview.height
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.connectRequested();
        }
    }
}
