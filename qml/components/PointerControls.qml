import QtQuick 2.12
import Lomiri.Components 1.3

Rectangle {
    id: root
    property bool dragLocked: false
    property bool precisionMode: false
    signal clickRequested(int button, bool doubleClick)
    signal toggleDragRequested()
    signal togglePrecisionRequested()

    height: units.gu(5.6)
    color: "#F2141923"
    border.width: units.dp(1)
    border.color: "#2B3548"

    Row {
        anchors.fill: parent
        anchors.margins: units.gu(0.6)
        spacing: units.gu(0.6)

        Repeater {
            model: [
                { key: "left", label: i18n.tr("Left"), active: false },
                { key: "right", label: i18n.tr("Right"), active: false },
                { key: "double", label: i18n.tr("Double"), active: false },
                { key: "drag", label: root.dragLocked ? i18n.tr("Release") : i18n.tr("Drag"), active: root.dragLocked },
                { key: "precision", label: i18n.tr("Precise"), active: root.precisionMode }
            ]
            delegate: AbstractButton {
                objectName: "pointer_" + modelData.key
                width: (root.width - units.gu(3.6)) / 5
                height: parent.height
                onClicked: {
                    if (modelData.key === "drag") root.toggleDragRequested()
                    else if (modelData.key === "precision") root.togglePrecisionRequested()
                    else root.clickRequested(modelData.key === "right" ? 2 : 1, modelData.key === "double")
                }
                Rectangle {
                    anchors.fill: parent
                    radius: units.gu(0.7)
                    color: modelData.active ? "#0078D4" : (parent.pressed ? "#344156" : "#232C3D")
                    border.width: units.dp(1)
                    border.color: modelData.active ? "#60CDFF" : "#344156"
                    Label {
                        anchors.centerIn: parent
                        text: modelData.label
                        fontSize: "small"
                        color: "#F3F6FA"
                    }
                }
            }
        }
    }
}
