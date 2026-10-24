pragma Singleton
import QtQuick 2.12

QtObject {
    id: theme

    property bool darkMode: true

    // Windows App Fluent + Ubuntu Touch Suru Palette
    readonly property color primaryAccent: "#0078D4"
    readonly property color primaryAccentHover: "#1084DF"
    readonly property color secondaryAccent: "#29B6F6"

    readonly property color windowBg: darkMode ? "#11151C" : "#F3F5F8"
    readonly property color navBarBg: darkMode ? "#171C26" : "#FFFFFF"
    readonly property color cardBg: darkMode ? "#1C2331" : "#FFFFFF"
    readonly property color cardHoverBg: darkMode ? "#232C3D" : "#F8FAFC"
    readonly property color cardBorder: darkMode ? "#2B3548" : "#DCE2EC"
    readonly property color inputBg: darkMode ? "#141923" : "#FFFFFF"
    readonly property color modalBg: darkMode ? "#1E2533" : "#FFFFFF"
    readonly property color pillHudBg: "#D8151B24"

    readonly property color textPrimary: darkMode ? "#F3F6FA" : "#1B2028"
    readonly property color textSecondary: darkMode ? "#9BA7B8" : "#5A6577"
    readonly property color textMuted: darkMode ? "#697588" : "#8792A2"

    readonly property color successGreen: "#2ECC71"
    readonly property color warningAmber: "#F59E0B"
    readonly property color dangerRed: "#EF4444"

    readonly property int radiusSmall: 6
    readonly property int radiusMedium: 10
    readonly property int radiusLarge: 14
    readonly property int radiusPill: 22
}
