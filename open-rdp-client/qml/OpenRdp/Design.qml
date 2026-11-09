pragma Singleton
import QtQuick 2.12

QtObject {
    property bool darkMode: true
    property QtObject systemMetrics: FontMetrics {
        font: Qt.application.font
    }
    property real fontScale: 1.0
    readonly property int textSize: Math.round(Math.max(14, systemMetrics.height * 0.9) * fontScale)
    readonly property color background: darkMode ? "#11151C" : "#F3F5F8"
    readonly property color navigation: darkMode ? "#171C26" : "#EAF0F6"
    readonly property color surface: darkMode ? "#1C2331" : "#FFFFFF"
    readonly property color hover: darkMode ? "#27344A" : "#EAF2FC"
    readonly property color border: darkMode ? "#334057" : "#CDD7E5"
    readonly property color text: darkMode ? "#F3F6FA" : "#1B2028"
    readonly property color secondaryText: darkMode ? "#AAB6C8" : "#526077"
    readonly property color accent: "#0078D4"
    readonly property color danger: darkMode ? "#FF9191" : "#B42332"
    readonly property color selected: darkMode ? "#173B5D" : "#DCEEFF"
    readonly property int radius: 12
    readonly property int spacing: 8
    readonly property int targetSize: 48
}
