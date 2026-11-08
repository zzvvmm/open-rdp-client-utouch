import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Pane {
    id: root
    property var settings: ({})
    property string appVersion: ""
    signal dispatchAction(var payload)
    function save(patch) {
        var action = {
            "action": "save_settings"
        };
        for (var key in patch)
            action[key] = patch[key];
        dispatchAction(action);
    }
    padding: 24
    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            width: parent.width
            spacing: 16
            Label {
                text: qsTr("Settings")
                font.pixelSize: 26
                font.bold: true
            }
            GroupBox {
                title: qsTr("Appearance")
                Layout.fillWidth: true
                RowLayout {
                    RadioButton {
                        text: qsTr("Dark")
                        checked: root.settings.themeMode !== "light"
                        onClicked: root.save({
                                "themeMode": "dark"
                            })
                    }
                    RadioButton {
                        text: qsTr("Light")
                        checked: root.settings.themeMode === "light"
                        onClicked: root.save({
                                "themeMode": "light"
                            })
                    }
                }
            }
            GroupBox {
                title: qsTr("Defaults for new PCs")
                Layout.fillWidth: true
                ColumnLayout {
                    RowLayout {
                        Label {
                            text: qsTr("Resolution")
                        }
                        ComboBox {
                            property var keys: ["native", "dynamic", "1920x1080", "1600x900", "1366x768", "1280x720"]
                            model: [qsTr("Match viewport"), qsTr("Dynamic (fit window)"), "1920×1080", "1600×900", "1366×768", "1280×720"]
                            currentIndex: Math.max(0, keys.indexOf(root.settings.defaultResolution || "native"))
                            onActivated: root.save({
                                    "defaultResolution": keys[currentIndex]
                                })
                        }
                    }
                    RowLayout {
                        Label {
                            text: qsTr("Remote scaling (%)")
                        }
                        SpinBox {
                            from: 100
                            to: 200
                            stepSize: 25
                            value: root.settings.defaultScaleFactor || 100
                            onValueModified: root.save({
                                    "defaultScaleFactor": value
                                })
                        }
                    }
                    RowLayout {
                        Label {
                            text: qsTr("Touch input")
                        }
                        ComboBox {
                            model: [qsTr("Direct touch"), qsTr("Virtual trackpad")]
                            currentIndex: root.settings.defaultTouchMode === "mouse_pointer" ? 1 : 0
                            onActivated: root.save({
                                    "defaultTouchMode": currentIndex === 1 ? "mouse_pointer" : "direct_touch"
                                })
                        }
                    }
                    RowLayout {
                        Label {
                            text: qsTr("Audio")
                        }
                        ComboBox {
                            property var keys: ["play_on_device", "play_on_remote", "disabled"]
                            model: [qsTr("Play locally"), qsTr("Play on remote PC"), qsTr("Disabled")]
                            currentIndex: Math.max(0, keys.indexOf(root.settings.defaultAudioMode || "play_on_device"))
                            onActivated: root.save({
                                    "defaultAudioMode": keys[currentIndex]
                                })
                        }
                    }
                    CheckBox {
                        text: qsTr("Synchronize clipboard text")
                        checked: root.settings.defaultClipboardEnabled !== false
                        onClicked: root.save({
                                "defaultClipboardEnabled": checked
                            })
                    }
                }
            }
            GroupBox {
                title: qsTr("Session controls")
                Layout.fillWidth: true
                ColumnLayout {
                    CheckBox {
                        text: qsTr("Show resolution and FPS")
                        checked: !!root.settings.showStatsOverlay
                        onClicked: root.save({
                                "showStatsOverlay": checked
                            })
                    }
                    CheckBox {
                        text: qsTr("Strict certificate checks")
                        checked: !!root.settings.strictCertCheck
                        onClicked: root.save({
                                "strictCertCheck": checked
                            })
                    }
                    RowLayout {
                        Label {
                            text: qsTr("Trackpad speed (%)")
                        }
                        SpinBox {
                            from: 25
                            to: 300
                            stepSize: 25
                            value: root.settings.trackpadSpeedPercent || 100
                            onValueModified: root.save({
                                    "trackpadSpeedPercent": value
                                })
                        }
                    }
                }
            }
            GroupBox {
                title: qsTr("Error reporting")
                Layout.fillWidth: true
                ColumnLayout {
                    width: parent.width
                    CheckBox {
                        objectName: "reportErrorsCheckBox"
                        text: qsTr("Report errors to Sentry")
                        checked: root.settings.reportErrors !== false
                        onClicked: root.save({
                                "reportErrors": checked
                            })
                    }
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Reports exclude credentials, PC addresses, screen contents, and clipboard text. Changes apply immediately.")
                        wrapMode: Text.Wrap
                        opacity: 0.65
                    }
                }
            }
            GroupBox {
                title: qsTr("About & updates")
                Layout.fillWidth: true
                ColumnLayout {
                    width: parent.width
                    Label {
                        text: qsTr("Open RDP Client ") + root.appVersion
                        font.bold: true
                    }
                    Label {
                        text: qsTr("Powered by IronRDP and Qt Quick · GPL-3.0-or-later")
                    }
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Download and install a newer .deb to upgrade. Your saved PCs and accounts are retained.")
                        wrapMode: Text.Wrap
                    }
                    Button {
                        text: qsTr("Open releases")
                        onClicked: Qt.openUrlExternally("https://github.com/zzvvmm/open-rdp-client-utouch/releases")
                    }
                }
            }
        }
    }
}
