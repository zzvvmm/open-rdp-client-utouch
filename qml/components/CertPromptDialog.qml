import QtQuick 2.12
import Lomiri.Components 1.3

Rectangle {
    id: root

    property var certData: null

    signal decisionMade(string decision) // "trust_always", "trust_once", "reject"

    visible: certData !== null
    anchors.fill: parent
    color: "#CC0B0E14"
    z: 90

    MouseArea {
        anchors.fill: parent
        onClicked: {} // Swallow clicks behind modal
    }

    Rectangle {
        width: Math.min(parent.width - units.gu(4), units.gu(54))
        height: contentCol.implicitHeight + units.gu(4)
        anchors.centerIn: parent
        radius: units.gu(1.6)
        color: "#1C2331"
        border.width: units.dp(2)
        border.color: (certData && certData.isMismatchWarning) ? "#EF4444" : "#F59E0B"

        Column {
            id: contentCol
            width: parent.width - units.gu(4)
            anchors.centerIn: parent
            spacing: units.gu(1.5)

            Row {
                spacing: units.gu(1.2)
                Icon {
                    width: units.gu(3.5)
                    height: units.gu(3.5)
                    name: "security-alert"
                    color: (certData && certData.isMismatchWarning) ? "#EF4444" : "#F59E0B"
                }
                Column {
                    width: contentCol.width - units.gu(5)
                    spacing: units.gu(0.3)
                    Label {
                        text: (certData && certData.isMismatchWarning)
                              ? i18n.tr("Certificate Fingerprint Changed!")
                              : i18n.tr("Verify Remote PC Certificate")
                        fontSize: "large"
                        font.bold: true
                        color: "#F3F6FA"
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                    Label {
                        text: certData ? (certData.host + ":" + certData.port) : ""
                        fontSize: "small"
                        color: "#29B6F6"
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: reasonLabel.implicitHeight + units.gu(1.6)
                radius: units.gu(0.8)
                color: (certData && certData.isMismatchWarning) ? "#3A1E24" : "#2B2518"

                Label {
                    id: reasonLabel
                    width: parent.width - units.gu(2)
                    anchors.centerIn: parent
                    text: certData ? certData.statusReason : ""
                    fontSize: "small"
                    color: (certData && certData.isMismatchWarning) ? "#FCA5A5" : "#FCD34D"
                    wrapMode: Text.WordWrap
                }
            }

            Column {
                width: parent.width
                spacing: units.gu(0.6)

                Label {
                    text: i18n.tr("Subject: ") + (certData ? certData.subjectCn : "")
                    fontSize: "small"
                    color: "#E2E8F0"
                    elide: Text.ElideRight
                    width: parent.width
                }
                Label {
                    text: i18n.tr("Issuer: ") + (certData ? certData.issuerCn : "")
                    fontSize: "small"
                    color: "#9BA7B8"
                    elide: Text.ElideRight
                    width: parent.width
                }
                Label {
                    text: i18n.tr("Valid: ") + (certData ? (certData.validFrom + " → " + certData.validUntil) : "")
                    fontSize: "x-small"
                    color: "#9BA7B8"
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Rectangle {
                width: parent.width
                height: fpLabel.implicitHeight + units.gu(1.6)
                radius: units.gu(0.8)
                color: "#11151C"
                border.width: units.dp(1)
                border.color: "#2B3548"

                Label {
                    id: fpLabel
                    width: parent.width - units.gu(2)
                    anchors.centerIn: parent
                    text: "SHA-256:\n" + (certData ? certData.sha256Fingerprint : "")
                    fontSize: "x-small"
                    font.family: "Ubuntu Mono"
                    color: "#60CDFF"
                    wrapMode: Text.WrapAnywhere
                }
            }

            Row {
                width: parent.width
                spacing: units.gu(1)

                Button {
                    width: (parent.width - units.gu(2)) / 3
                    text: i18n.tr("Cancel")
                    color: "#3A1E24"
                    onClicked: root.decisionMade("reject")
                }

                Button {
                    width: (parent.width - units.gu(2)) / 3
                    text: i18n.tr("Trust Once")
                    color: "#263248"
                    onClicked: root.decisionMade("trust_once")
                }

                Button {
                    width: (parent.width - units.gu(2)) / 3
                    text: i18n.tr("Trust Always")
                    color: "#0078D4"
                    onClicked: root.decisionMade("trust_always")
                }
            }
        }
    }
}
