import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Pane {
    id: root
    property var profiles: []
    property string activeProfileId: ""
    readonly property var filteredProfiles: profiles.filter(function (pc) {
            return (!favorites.checked || pc.favorite) && (pc.displayTitle + " " + pc.address + " " + pc.groupName).toLowerCase().indexOf(search.text.toLowerCase()) >= 0;
        })
    signal connectRequested(string id)
    signal editRequested(var pc)
    signal addRequested
    signal dispatchAction(var payload)
    padding: 24
    ColumnLayout {
        anchors.fill: parent
        spacing: 18
        RowLayout {
            Layout.fillWidth: true
            Label {
                text: qsTr("Saved PCs")
                font.pixelSize: 26
                font.bold: true
                Layout.fillWidth: true
            }
            Button {
                objectName: "addPcButton"
                text: qsTr("Add PC")
                highlighted: true
                onClicked: root.addRequested()
            }
        }
        RowLayout {
            TextField {
                id: search
                objectName: "pcSearch"
                placeholderText: qsTr("Search PCs, addresses, or groups")
                Layout.fillWidth: true
            }
            CheckBox {
                id: favorites
                text: qsTr("Favorites")
            }
        }
        Label {
            visible: grid.count === 0
            text: qsTr("No PCs found. Add a PC or try a different search.")
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        GridView {
            id: grid
            objectName: "pcGrid"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: width / Math.max(1, Math.floor(width / 275))
            cellHeight: 280
            model: root.filteredProfiles
            ScrollBar.vertical: ScrollBar {
            }
            delegate: Pane {
                required property var modelData
                width: grid.cellWidth - 12
                height: grid.cellHeight - 12
                background: Rectangle {
                    color: palette.base
                    radius: 10
                    border.color: modelData.id === root.activeProfileId ? palette.highlight : palette.mid
                }
                ColumnLayout {
                    anchors.fill: parent
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 112
                        color: "#0a0d12"
                        Image {
                            anchors.fill: parent
                            source: modelData.thumbnailPath ? "file://" + modelData.thumbnailPath : "qrc:/assets/icons/pc-card.svg"
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            onDoubleClicked: root.connectRequested(modelData.id)
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.displayTitle
                        textFormat: Text.PlainText
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.address
                        textFormat: Text.PlainText
                        opacity: 0.65
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.groupName
                        textFormat: Text.PlainText
                        opacity: 0.65
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        Button {
                            text: qsTr("Connect")
                            highlighted: true
                            onClicked: root.connectRequested(modelData.id)
                        }
                        ToolButton {
                            text: modelData.favorite ? "★" : "☆"
                            Accessible.name: qsTr("Toggle favorite")
                            onClicked: root.dispatchAction({
                                    "action": "toggle_favorite_pc",
                                    "id": modelData.id
                                })
                        }
                        ToolButton {
                            text: "⋯"
                            Accessible.name: qsTr("PC actions")
                            onClicked: menu.open()
                            Menu {
                                id: menu
                                MenuItem {
                                    text: qsTr("Edit")
                                    onTriggered: root.editRequested(modelData)
                                }
                                MenuItem {
                                    text: qsTr("Duplicate")
                                    onTriggered: root.dispatchAction({
                                            "action": "duplicate_pc",
                                            "id": modelData.id
                                        })
                                }
                                MenuItem {
                                    text: qsTr("Delete")
                                    onTriggered: root.dispatchAction({
                                            "action": "delete_pc",
                                            "id": modelData.id
                                        })
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
