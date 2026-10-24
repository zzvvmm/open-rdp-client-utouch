import QtQuick 2.12
import Lomiri.Components 1.3
import "../components"

Item {
    id: root

    property var profiles: []
    property bool darkMode: true
    property string activeProfileId: ""
    property string searchQuery: ""
    property string selectedFilter: "all" // "all", "favorites"

    signal connectPc(string pcId)
    signal addPcRequested()
    signal editPcRequested(var pcData)
    signal duplicatePcRequested(string pcId)
    signal deletePcRequested(string pcId)
    signal favoriteToggled(string pcId)

    function filteredProfiles() {
        var out = []
        var q = searchQuery.trim().toLowerCase()
        for (var i = 0; i < profiles.length; i++) {
            var p = profiles[i]
            if (selectedFilter === "favorites" && !p.favorite) continue
            if (q.length > 0) {
                var title = (p.displayTitle || "").toLowerCase()
                var addr = (p.address || "").toLowerCase()
                var grp = (p.groupName || "").toLowerCase()
                if (title.indexOf(q) === -1 && addr.indexOf(q) === -1 && grp.indexOf(q) === -1) {
                    continue
                }
            }
            out.push(p)
        }
        return out
    }

    readonly property var visibleList: filteredProfiles()
    readonly property int columnCount: width >= units.gu(105) ? 3 : (width >= units.gu(62) ? 2 : 1)

    Column {
        anchors.fill: parent
        anchors.margins: units.gu(2)
        spacing: units.gu(1.6)

        // Top Search & Filter Bar (Windows App style)
        Row {
            width: parent.width
            spacing: units.gu(1)

            TextField {
                id: searchField
                width: parent.width - filterRow.width - units.gu(1)
                placeholderText: i18n.tr("Search saved PCs or IP addresses…")
                onTextChanged: root.searchQuery = text
            }

            Row {
                id: filterRow
                spacing: units.gu(0.8)

                Button {
                    text: i18n.tr("All")
                    color: root.selectedFilter === "all" ? "#0078D4" : (root.darkMode ? "#232C3D" : "#DCE2EC")
                    onClicked: root.selectedFilter = "all"
                }

                Button {
                    text: i18n.tr("Favorites")
                    color: root.selectedFilter === "favorites" ? "#0078D4" : (root.darkMode ? "#232C3D" : "#DCE2EC")
                    onClicked: root.selectedFilter = "favorites"
                }
            }
        }

        // Responsive Grid of PC Cards
        Flickable {
            id: gridFlick
            width: parent.width
            height: parent.height - units.gu(6)
            contentWidth: width
            contentHeight: pcGrid.implicitHeight + units.gu(4)
            clip: true
            visible: root.visibleList.length > 0

            Grid {
                id: pcGrid
                width: parent.width
                columns: root.columnCount
                spacing: units.gu(1.8)

                readonly property real cardWidth: (width - (columns - 1) * spacing) / columns

                Repeater {
                    model: root.visibleList
                    delegate: PcCard {
                        width: pcGrid.cardWidth
                        height: Math.round(width * 0.52) + units.gu(13.5)
                        pcData: modelData
                        darkMode: root.darkMode
                        isActiveSession: modelData.id === root.activeProfileId

                        onConnectClicked: root.connectPc(pcId)
                        onEditClicked: root.editPcRequested(pc)
                        onDuplicateClicked: root.duplicatePcRequested(pcId)
                        onDeleteClicked: root.deletePcRequested(pcId)
                        onFavoriteToggled: root.favoriteToggled(pcId)
                    }
                }
            }
        }

        // Empty State
        Item {
            width: parent.width
            height: parent.height - units.gu(6)
            visible: root.visibleList.length === 0

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - units.gu(4), units.gu(42))
                spacing: units.gu(1.6)

                Image {
                    width: units.gu(16)
                    height: units.gu(9)
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: "qrc:/assets/icons/pc-card.svg"
                    fillMode: Image.PreserveAspectFit
                }

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: i18n.tr("No Remote PCs Found")
                    fontSize: "large"
                    font.bold: true
                    color: root.darkMode ? "#F3F6FA" : "#1B2028"
                }

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: i18n.tr("Add a Windows 10/11 PC, Server, or xrdp Linux host to connect from Ubuntu Touch.")
                    fontSize: "small"
                    color: root.darkMode ? "#9BA7B8" : "#5A6577"
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(22)
                    text: i18n.tr("+ Add PC")
                    color: "#0078D4"
                    onClicked: root.addPcRequested()
                }
            }
        }
    }
}
