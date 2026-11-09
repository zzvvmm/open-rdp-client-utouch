import QtQuick 2.12
import Lomiri.Components 1.3
import OpenRdp 1.0 as Shared

Item {
    id: root
    readonly property bool shortLayout: height < 450
    property var profiles: []
    property var settings: ({})
    property bool darkMode: true
    property string activeProfileId: ""
    property string sessionStage: "disconnected"
    property string searchQuery: ""
    property string selectedFilter: "all"
    property var selectedPc: ({})
    property bool deleting: false
    property string operationError: ""
    property bool operationBusy: false
    readonly property var visibleList: library.visibleProfiles
    property alias filtersVisible: filters.visible
    signal connectPc(string pcId)
    signal addPcRequested
    signal quickConnectRequested
    signal editPcRequested(var pcData)
    signal duplicatePcRequested(string pcId)
    signal deletePcRequested(string pcId)
    signal favoriteToggled(string pcId)
    signal dispatchAction(var payload)
    Shared.PcLibrary {
        id: library
        profiles: root.profiles
        query: root.searchQuery
        view: root.selectedFilter
        sort: root.settings.librarySort || "name"
    }
    function completeAction(result) {
        operationBusy = false;
        if (result.ok) {
            library.group = "";
            filters.visible = false;
        } else
            operationError = result.message;
    }
    Column {
        id: controls
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        spacing: root.shortLayout ? 8 : 12
        Row {
            visible: !root.shortLayout
            width: parent.width
            spacing: 8
            Label {
                text: i18n.tr("Your PCs")
                width: parent.width - quickButton.width - 8
                fontSize: "x-large"
                font.bold: true
                color: Shared.Design.text
                anchors.verticalCenter: parent.verticalCenter
            }
            Shared.ActionButton {
                id: quickButton
                objectName: "quickConnectButton"
                text: i18n.tr("Quick Connect")
                selected: true
                onClicked: root.quickConnectRequested()
            }
        }
        Row {
            width: parent.width
            spacing: 8
            TextField {
                objectName: "pcSearch"
                width: parent.width - (root.shortLayout ? landscapeQuick.width + 8 : 0)
                height: Math.max(48, units.gu(6))
                placeholderText: i18n.tr("Search names, addresses, or groups")
                onTextChanged: root.searchQuery = text
            }
            Shared.ActionButton {
                id: landscapeQuick
                visible: root.shortLayout
                text: i18n.tr("Quick Connect")
                selected: true
                onClicked: root.quickConnectRequested()
            }
        }
        Row {
            width: parent.width
            spacing: 0
            Repeater {
                model: [{
                        "key": "all",
                        "label": i18n.tr("All")
                    }, {
                        "key": "favorites",
                        "label": i18n.tr("Favorites")
                    }, {
                        "key": "recent",
                        "label": i18n.tr("Recent")
                    }]
                delegate: Shared.ActionButton {
                    width: (controls.width - 56) / 3
                    text: modelData.label
                    selected: root.selectedFilter === modelData.key
                    onClicked: root.selectedFilter = modelData.key
                }
            }
            Shared.ActionButton {
                text: "⋯"
                width: 56
                accessibleName: i18n.tr("Filters, sorting, and groups")
                selected: library.group.length > 0
                onClicked: {
                    root.operationError = "";
                    filters.visible = true;
                }
            }
        }
        Label {
            visible: !root.shortLayout
            text: (library.group ? library.group + " · " : "") + i18n.tr("%1 PCs").arg(library.visibleProfiles.length)
            color: Shared.Design.secondaryText
            fontSize: "small"
        }
    }
    GridView {
        id: grid
        objectName: "pcGrid"
        anchors.top: controls.bottom
        anchors.topMargin: 16
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 8
        clip: true
        model: library.visibleProfiles
        property bool compact: root.shortLayout || root.settings.libraryLayout === "list"
        cellWidth: compact ? width : width / Math.max(1, Math.floor(width / 280))
        cellHeight: (compact ? 116 : Math.round((cellWidth - 8) * 9 / 16) + 176) + Math.max(0, Shared.Design.textSize - 14) * 5
        delegate: Shared.PcTile {
            pc: modelData
            width: grid.cellWidth - 8
            height: grid.cellHeight - 12
            compact: grid.compact
            connectText: i18n.tr("Connect")
            favoriteName: i18n.tr("Toggle favorite")
            actionsName: i18n.tr("PC actions")
            neverConnectedText: i18n.tr("Never connected")
            lastConnectedText: i18n.tr("Last connected")
            demoText: i18n.tr("Offline demo")
            sessionBadge: pc.id === root.activeProfileId && root.sessionStage !== "error" && root.sessionStage !== "disconnected" ? (root.sessionStage === "connected" ? i18n.tr("Connected") : i18n.tr("Connecting")) : ""
            onConnectRequested: root.connectPc(pc.id)
            onFavoriteRequested: root.favoriteToggled(pc.id)
            onActionsRequested: {
                root.selectedPc = pc;
                root.deleting = false;
                actions.visible = true;
            }
        }
    }
    Column {
        anchors.centerIn: grid
        width: grid.width - 24
        spacing: 16
        visible: library.visibleProfiles.length === 0
        Image {
            visible: grid.height > 250
            anchors.horizontalCenter: parent.horizontalCenter
            width: 112
            height: 72
            source: "qrc:/assets/icons/pc-card.svg"
        }
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            fontSize: "large"
            font.bold: true
            color: Shared.Design.text
            text: root.searchQuery.trim() || library.group ? i18n.tr("No matching PCs") : root.selectedFilter === "favorites" ? i18n.tr("Your favorites belong here") : root.selectedFilter === "recent" ? i18n.tr("Your recent connections") : i18n.tr("Add your first PC")
        }
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: Shared.Design.secondaryText
            text: root.searchQuery.trim() || library.group ? i18n.tr("Try another search or clear your filters.") : root.selectedFilter === "favorites" ? i18n.tr("Star a PC to keep it within easy reach.") : root.selectedFilter === "recent" ? i18n.tr("PCs appear here after a successful connection.") : i18n.tr("Save a Windows or Linux PC, or use Quick Connect.")
        }
        Shared.ActionButton {
            anchors.horizontalCenter: parent.horizontalCenter
            text: i18n.tr("Add PC")
            primary: true
            onClicked: root.addPcRequested()
        }
    }
    Rectangle {
        id: actions
        visible: false
        anchors.fill: parent
        color: "#B0000000"
        z: 30
        MouseArea {
            anchors.fill: parent
            onClicked: actions.visible = false
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: menuColumn.implicitHeight + 32
            radius: 12
            color: Shared.Design.surface
            Column {
                id: menuColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 4
                Label {
                    text: root.selectedPc.displayTitle || ""
                    width: parent.width
                    elide: Text.ElideRight
                    color: Shared.Design.text
                    font.bold: true
                }
                Repeater {
                    model: [i18n.tr("Connect"), i18n.tr("Edit"), i18n.tr("Duplicate"), i18n.tr("Clear thumbnail")]
                    delegate: Shared.ActionButton {
                        width: parent.width
                        text: modelData
                        onClicked: {
                            actions.visible = false;
                            if (index === 0)
                                root.connectPc(root.selectedPc.id);
                            if (index === 1)
                                root.editPcRequested(root.selectedPc);
                            if (index === 2)
                                root.duplicatePcRequested(root.selectedPc.id);
                            if (index === 3)
                                root.dispatchAction({
                                        "action": "clear_thumbnail",
                                        "id": root.selectedPc.id
                                    });
                        }
                    }
                }
                Shared.ActionButton {
                    width: parent.width
                    destructive: true
                    text: root.deleting ? i18n.tr("Confirm delete PC") : i18n.tr("Delete PC…")
                    onClicked: {
                        if (!root.deleting)
                            root.deleting = true;
                        else {
                            actions.visible = false;
                            root.deletePcRequested(root.selectedPc.id);
                        }
                    }
                }
                Shared.ActionButton {
                    width: parent.width
                    text: i18n.tr("Cancel")
                    onClicked: actions.visible = false
                }
            }
        }
    }
    Rectangle {
        id: filters
        visible: false
        anchors.fill: parent
        color: "#B0000000"
        z: 40
        MouseArea {
            anchors.fill: parent
            onClicked: if (!root.operationBusy)
                filters.visible = false
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 24
            height: Math.min(parent.height - 24, 620)
            radius: 12
            color: Shared.Design.surface
            Flickable {
                anchors.fill: parent
                anchors.margins: 16
                contentWidth: width
                contentHeight: filterColumn.implicitHeight
                clip: true
                Column {
                    id: filterColumn
                    width: parent.width
                    spacing: 12
                    Row {
                        width: parent.width
                        Label {
                            text: i18n.tr("Library options")
                            color: Shared.Design.text
                            fontSize: "large"
                            width: parent.width - 64
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Shared.ActionButton {
                            text: i18n.tr("Done")
                            onClicked: filters.visible = false
                        }
                    }
                    Label {
                        text: i18n.tr("Layout")
                        color: Shared.Design.secondaryText
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: [{
                                    "key": "grid",
                                    "label": i18n.tr("Grid")
                                }, {
                                    "key": "list",
                                    "label": i18n.tr("List")
                                }]
                            delegate: Shared.ActionButton {
                                text: modelData.label
                                selected: (root.settings.libraryLayout || "grid") === modelData.key
                                onClicked: root.dispatchAction({
                                        "action": "save_settings",
                                        "libraryLayout": modelData.key
                                    })
                            }
                        }
                    }
                    Label {
                        text: i18n.tr("Sort by")
                        color: Shared.Design.secondaryText
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: [{
                                    "key": "name",
                                    "label": i18n.tr("Name")
                                }, {
                                    "key": "address",
                                    "label": i18n.tr("Address")
                                }, {
                                    "key": "recent",
                                    "label": i18n.tr("Last connected")
                                }]
                            delegate: Shared.ActionButton {
                                text: modelData.label
                                selected: (root.settings.librarySort || "name") === modelData.key
                                enabled: root.selectedFilter !== "recent"
                                onClicked: root.dispatchAction({
                                        "action": "save_settings",
                                        "librarySort": modelData.key
                                    })
                            }
                        }
                    }
                    Label {
                        text: i18n.tr("Group")
                        color: Shared.Design.secondaryText
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        Shared.ActionButton {
                            text: i18n.tr("All groups")
                            selected: library.group === ""
                            onClicked: library.group = ""
                        }
                        Repeater {
                            model: library.groupNames
                            delegate: Shared.ActionButton {
                                text: modelData
                                selected: library.group === modelData
                                onClicked: {
                                    library.group = modelData;
                                    renameField.text = modelData;
                                }
                            }
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 12
                        visible: library.group.length > 0
                        Label {
                            text: i18n.tr("Manage selected group")
                            color: Shared.Design.text
                        }
                        TextField {
                            id: renameField
                            width: parent.width
                            height: 48
                            placeholderText: i18n.tr("Group name")
                        }
                        Shared.ActionButton {
                            text: i18n.tr("Rename group")
                            enabled: !root.operationBusy && renameField.text.trim().length > 0
                            selected: true
                            onClicked: {
                                root.operationBusy = true;
                                root.dispatchAction({
                                        "action": "rename_group",
                                        "groupName": library.group,
                                        "newName": renameField.text
                                    });
                            }
                        }
                        Label {
                            text: i18n.tr("Removing a group moves its PCs to Saved PCs.")
                            width: parent.width
                            wrapMode: Text.Wrap
                            color: Shared.Design.secondaryText
                        }
                        Shared.ActionButton {
                            text: i18n.tr("Remove group")
                            destructive: true
                            enabled: !root.operationBusy && library.group !== "Saved PCs"
                            onClicked: {
                                root.operationBusy = true;
                                root.dispatchAction({
                                        "action": "remove_group",
                                        "groupName": library.group
                                    });
                            }
                        }
                    }
                    Label {
                        text: root.operationError
                        visible: text.length > 0
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: Shared.Design.danger
                        textFormat: Text.PlainText
                    }
                }
            }
        }
    }
}
