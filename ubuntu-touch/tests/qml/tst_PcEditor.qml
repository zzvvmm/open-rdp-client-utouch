import QtQuick 2.12
import QtTest 1.2
import "../../qml/pages" as Pages

Item {
    width: 450
    height: 820

    Pages.PcEditorDialog {
        id: editor
    }
    SignalSpy {
        id: saved
        target: editor
        signalName: "saveRequested"
    }

    TestCase {
        name: "PcEditor"
        when: windowShown

        function init() {
            editor.openForNew("dynamic", 100, "mouse_pointer", "play_on_device", true);
            saved.clear();
        }

        function cleanup() {
            editor.active = false;
        }

        function test_default_options_are_first_and_selected() {
            editor.openForNew();
            var nativeOption = findChild(editor, "resolutionOption_native");
            var dynamicOption = findChild(editor, "resolutionOption_dynamic");
            var directOption = findChild(editor, "directTouchOption");
            var trackpadOption = findChild(editor, "trackpadOption");
            compare(editor.resolutionPreset, "native");
            compare(editor.defaultTouchMode, "direct_touch");
            compare(nativeOption.x, 0);
            compare(nativeOption.y, 0);
            verify(dynamicOption.x > nativeOption.x || dynamicOption.y > nativeOption.y);
            verify(directOption.x < trackpadOption.x);
            compare(nativeOption.color, "#0078d4");
            compare(directOption.color, "#0078d4");
        }

        function test_address_input_disables_keyboard_rewriting() {
            var field = findChild(editor, "pcHostField");
            verify(field.inputMethodHints & Qt.ImhNoPredictiveText);
            verify(field.inputMethodHints & Qt.ImhNoAutoUppercase);
        }

        function test_direct_touch_default_preserves_explicit_trackpad_choice() {
            editor.openForNew();
            compare(editor.defaultTouchMode, "direct_touch");
            compare(editor.resolutionPreset, "native");
            var field = findChild(editor, "pcHostField");
            field.insert(0, "host-01");
            mouseClick(findChild(editor, "savePcButton"));
            compare(saved.signalArguments[0][0].resolutionPreset, "native");
            compare(saved.signalArguments[0][0].defaultTouchMode, "direct_touch");
            editor.openForEdit({
                    "id": "old-pc",
                    "hostname": "host",
                    "defaultTouchMode": "mouse_pointer"
                });
            compare(editor.defaultTouchMode, "mouse_pointer");
        }

        function test_explicit_dynamic_resolution_is_preserved() {
            compare(editor.resolutionPreset, "dynamic");
            editor.openForEdit({
                    "id": "old-pc",
                    "hostname": "host",
                    "resolutionPreset": "dynamic"
                });
            compare(editor.resolutionPreset, "dynamic");
            mouseClick(findChild(editor, "savePcButton"));
            compare(saved.signalArguments[0][0].resolutionPreset, "dynamic");
        }

        function test_save_literal_address_data() {
            return [{
                    "tag": "hyphen",
                    "address": "hostname-01"
                }, {
                    "tag": "mixed-case-port",
                    "address": "Hostname-01.example.test:3390"
                }, {
                    "tag": "vpn-ip",
                    "address": "192.168.1.50:3391"
                }, {
                    "tag": "ipv6",
                    "address": "[fd00::1234]:3392"
                }, {
                    "tag": "bare-ipv6",
                    "address": "fd00::1234"
                }];
        }

        function test_save_literal_address(data) {
            var field = findChild(editor, "pcHostField");
            field.forceActiveFocus();
            field.remove(0, field.length);
            field.insert(0, data.address);
            mouseClick(findChild(editor, "savePcButton"));
            compare(saved.count, 1);
            compare(saved.signalArguments[0][0].hostInput, data.address);
            verify(editor.active);
            verify(editor.busy);
            editor.completeSave({
                    "ok": true,
                    "entityId": "saved-pc"
                });
            compare(editor.active, false);
        }

        function test_typing_hyphen_and_digits_saves_the_whole_hostname() {
            var field = findChild(editor, "pcHostField");
            field.forceActiveFocus();
            for (var i = 0; i < "hostname".length; i++) {
                keyClick("hostname".charCodeAt(i) - 32);
            }
            keyClick(Qt.Key_Minus);
            keyClick(Qt.Key_0);
            keyClick(Qt.Key_1);
            compare(field.text, "hostname-01");
            mouseClick(findChild(editor, "savePcButton"));
            compare(saved.signalArguments[0][0].hostInput, "hostname-01");
        }

        function test_edit_reopen_and_save_preserves_suffix() {
            editor.openForEdit({
                    "id": "saved-id",
                    "address": "hostname-01:3390"
                });
            var field = findChild(editor, "pcHostField");
            compare(field.text, "hostname-01:3390");
            // Use editor operations: assigning .text would remove its QML binding.
            field.remove(0, field.length);
            field.insert(0, "hostname-02:3391");
            mouseClick(findChild(editor, "savePcButton"));
            compare(saved.signalArguments[0][0].hostInput, "hostname-02:3391");
            compare(saved.signalArguments[0][0].id, "saved-id");
            editor.openForEdit({
                    "id": "another-id",
                    "address": "new-host-03"
                });
            compare(field.text, "new-host-03");
            mouseClick(findChild(editor, "savePcButton"));
            compare(saved.signalArguments[1][0].hostInput, "new-host-03");
        }

        function test_backend_rejection_keeps_form_and_save_connect_waits_for_success() {
            editor.hostInput = "work-pc";
            verify(editor.save(true));
            verify(editor.active);
            editor.completeSave({
                    "ok": false,
                    "message": "Storage is full"
                });
            verify(editor.active);
            verify(!editor.busy);
            compare(editor.validationError, "Storage is full");
            compare(editor.hostInput, "work-pc");
            verify(editor.save(true));
            editor.completeSave({
                    "ok": true,
                    "entityId": "saved-pc"
                });
            verify(!editor.active);
        }

        function test_save_buttons_remain_inside_phone_and_landscape() {
            for (var size of [[390, 844], [820, 450]]) {
                editor.parent.width = size[0];
                editor.parent.height = size[1];
                wait(20);
                var button = findChild(editor, "saveConnectPcButton");
                var point = button.mapToItem(editor, 0, 0);
                verify(point.x >= 0 && point.y >= 0);
                verify(point.x + button.width <= editor.width);
                verify(point.y + button.height <= editor.height);
                verify(button.height >= 48);
            }
            editor.parent.width = 450;
            editor.parent.height = 820;
        }

        function test_empty_address_keeps_editor_open() {
            var field = findChild(editor, "pcHostField");
            field.remove(0, field.length);
            field.insert(0, "   ");
            mouseClick(findChild(editor, "savePcButton"));
            compare(saved.count, 0);
            compare(editor.active, true);
            verify(editor.validationError.length > 0);
        }
    }
}
