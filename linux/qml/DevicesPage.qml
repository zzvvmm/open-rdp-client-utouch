import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import OpenRdp 1.0

Pane {
    id: root
    property var profiles: []
    property var settings: ({})
    property var appState
    property string activeProfileId: ""
    property string sessionStage: "disconnected"
    property var selectedPc: ({})
    readonly property var filteredProfiles: library.visibleProfiles
    readonly property bool modalOpen: groupDialog.visible || deleteDialog.visible
    signal connectRequested(string id)
    signal editRequested(var pc)
    signal addRequested
    signal quickConnectRequested
    signal dispatchAction(var payload)
    padding: width < 850 ? 20 : 32
    background: Rectangle {
        color: Design.background
    }
    PcLibrary {
        id: library
        profiles: root.profiles
        query: search.text
        sort: root.settings.librarySort || "name"
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 20
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 6
                Label {
                    text: qsTr("Your PCs")
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: qsTr("Your desktops, one connection away.")
                    color: Design.secondaryText
                }
            }
            ActionButton {
                objectName: "quickConnectButton"
                text: qsTr("Quick Connect")
                selected: true
                onClicked: root.quickConnectRequested()
            }
            ActionButton {
                objectName: "addPcButton"
                text: qsTr("Add PC")
                primary: true
                onClicked: root.addRequested()
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: [{
                        "key": "all",
                        "label": qsTr("All PCs")
                    }, {
                        "key": "favorites",
                        "label": qsTr("Favorites")
                    }, {
                        "key": "recent",
                        "label": qsTr("Recent")
                    }]
                ActionButton {
                    required property var modelData
                    text: modelData.label
                    selected: library.view === modelData.key
                    onClicked: library.view = modelData.key
                }
            }
            Item {
                Layout.fillWidth: true
            }
            ActionButton {
                text: qsTr("Grid")
                selected: (root.settings.libraryLayout || "grid") === "grid"
                onClicked: root.dispatchAction({
                        "action": "save_settings",
                        "libraryLayout": "grid"
                    })
            }
            ActionButton {
                text: qsTr("List")
                selected: root.settings.libraryLayout === "list"
                onClicked: root.dispatchAction({
                        "action": "save_settings",
                        "libraryLayout": "list"
                    })
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            TextField {
                id: search
                objectName: "pcSearch"
                Layout.fillWidth: true
                implicitHeight: 48
                placeholderText: qsTr("Search names, addresses, or groups")
                selectByMouse: true
            }
            ComboBox {
                objectName: "groupFilter"
                implicitHeight: 48
                Layout.preferredWidth: 150
                model: [qsTr("All groups")].concat(library.groupNames)
                currentIndex: library.group ? Math.max(0, model.indexOf(library.group)) : 0
                onActivated: library.group = currentIndex === 0 ? "" : currentText
            }
            ActionButton {
                text: "⋯"
                accessibleName: qsTr("Manage selected group")
                enabled: library.group.length > 0
                onClicked: {
                    groupName.text = library.group;
                    groupDialog.errorMessage = "";
                    groupDialog.open();
                }
            }
            ComboBox {
                objectName: "librarySort"
                implicitHeight: 48
                Layout.preferredWidth: 155
                model: [qsTr("Name A–Z"), qsTr("Address A–Z"), qsTr("Last connected")]
                property var keys: ["name", "address", "recent"]
                currentIndex: library.view === "recent" ? 2 : Math.max(0, keys.indexOf(root.settings.librarySort || "name"))
                enabled: library.view !== "recent"
                onActivated: root.dispatchAction({
                        "action": "save_settings",
                        "librarySort": keys[currentIndex]
                    })
            }
        }
        Label {
            text: qsTr("%n PC(s)", "", library.visibleProfiles.length)
            color: Design.secondaryText
        }
        GridView {
            id: grid
            objectName: "pcGrid"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            property bool compact: root.settings.libraryLayout === "list"
            cellWidth: compact ? width : width / Math.max(1, Math.floor(width / 290))
            cellHeight: (compact ? 116 : Math.round((cellWidth - 16) * 9 / 16) + 180) + Math.max(0, Design.textSize - 14) * 5
            model: library.visibleProfiles
            ScrollBar.vertical: ScrollBar {
            }
            delegate: PcTile {
                id: tile
                required property var modelData
                width: grid.cellWidth - (grid.compact ? 0 : 16)
                height: grid.cellHeight - 12
                pc: modelData
                compact: grid.compact
                sessionBadge: modelData.id === root.activeProfileId && root.sessionStage !== "disconnected" && root.sessionStage !== "error" ? (root.sessionStage === "connected" ? qsTr("Connected") : qsTr("Connecting")) : ""
                onConnectRequested: root.connectRequested(pc.id)
                onFavoriteRequested: root.dispatchAction({
                        "action": "toggle_favorite_pc",
                        "id": pc.id
                    })
                onActionsRequested: {
                    root.selectedPc = pc;
                    var point = tile.mapToItem(root, tile.width - 180, tile.height - 48);
                    pcMenu.popup(point.x, point.y);
                }
            }
        }
    }
    Column {
        parent: grid
        visible: library.visibleProfiles.length === 0
        anchors.centerIn: parent
        width: Math.min(400, grid.width - 32)
        spacing: 16
        Image {
            visible: grid.height > 260
            source: "qrc:/assets/icons/pc-card.svg"
            width: 112
            height: 72
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.pixelSize: 22
            font.bold: true
            text: search.text.trim() || library.group ? qsTr("No matching PCs") : library.view === "favorites" ? qsTr("Your favorites belong here") : library.view === "recent" ? qsTr("Your recent connections") : qsTr("Add your first PC")
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Design.secondaryText
            text: search.text.trim() || library.group ? qsTr("Try another search or clear your filters.") : library.view === "favorites" ? qsTr("Star a PC to keep it within easy reach.") : library.view === "recent" ? qsTr("PCs appear here after a successful connection.") : qsTr("Save a Windows or Linux PC, or use Quick Connect for a temporary session.")
        }
        ActionButton {
            anchors.horizontalCenter: parent.horizontalCenter
            text: search.text.trim() || library.group ? qsTr("Clear filters") : qsTr("Add PC")
            primary: true
            onClicked: {
                if (search.text.trim() || library.group) {
                    search.clear();
                    library.group = "";
                } else
                    root.addRequested();
            }
        }
    }
    Menu {
        id: pcMenu
        MenuItem {
            text: qsTr("Connect")
            onTriggered: root.connectRequested(root.selectedPc.id)
        }
        MenuItem {
            text: qsTr("Edit")
            onTriggered: root.editRequested(root.selectedPc)
        }
        MenuItem {
            text: qsTr("Duplicate")
            onTriggered: root.dispatchAction({
                    "action": "duplicate_pc",
                    "id": root.selectedPc.id
                })
        }
        MenuItem {
            text: qsTr("Clear thumbnail")
            onTriggered: root.dispatchAction({
                    "action": "clear_thumbnail",
                    "id": root.selectedPc.id
                })
        }
        MenuSeparator {
        }
        MenuItem {
            text: qsTr("Delete PC…")
            onTriggered: deleteDialog.open()
        }
    }
    Dialog {
        id: deleteDialog
        anchors.centerIn: parent
        modal: true
        width: Math.min(440, root.width - 32)
        title: qsTr("Delete saved PC?")
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: qsTr("Remove %1 from this device?").arg(root.selectedPc.displayTitle || "")
        }
        onAccepted: root.dispatchAction({
                "action": "delete_pc",
                "id": root.selectedPc.id
            })
    }
    Dialog {
        id: groupDialog
        anchors.centerIn: parent
        modal: true
        width: Math.min(440, root.width - 32)
        title: qsTr("Manage group")
        property string errorMessage: ""
        property bool busy: false
        function updateGroup(remove) {
            var payload = {
                "action": remove ? "remove_group" : "rename_group",
                "groupName": library.group,
                "newName": groupName.text
            };
            if (!root.appState) {
                root.dispatchAction(payload);
                return;
            }
            busy = true;
            root.appState.submitAction(payload, function (result) {
                    groupDialog.busy = false;
                    if (result.ok) {
                        library.group = "";
                        groupDialog.close();
                    } else
                        groupDialog.errorMessage = result.message;
                });
        }
        contentItem: ColumnLayout {
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: qsTr("Renaming updates every PC in this group. Removing moves its PCs to Saved PCs.")
            }
            TextField {
                id: groupName
                Layout.fillWidth: true
                implicitHeight: 48
                placeholderText: qsTr("Group name")
            }
            Label {
                text: groupDialog.errorMessage
                color: Design.danger
                visible: text.length > 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            RowLayout {
                ActionButton {
                    text: qsTr("Remove group")
                    destructive: true
                    enabled: !groupDialog.busy && library.group !== "Saved PCs"
                    onClicked: groupDialog.updateGroup(true)
                }
                ActionButton {
                    text: qsTr("Rename")
                    primary: true
                    enabled: !groupDialog.busy && groupName.text.trim().length > 0
                    onClicked: groupDialog.updateGroup(false)
                }
            }
        }
    }
}
