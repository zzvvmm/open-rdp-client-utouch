import QtQuick 2.12
import QtTest 1.2
import "../../qml/pages" as Pages

Item {
    width: 450
    height: 820

    Pages.PcEditorDialog { id: editor }
    SignalSpy { id: saved; target: editor; signalName: "saveRequested" }

    TestCase {
        name: "PcEditor"
        when: windowShown

        function init() {
            editor.openForNew("dynamic", 100, "mouse_pointer", "play_on_device", true)
            saved.clear()
        }

        function cleanup() { editor.active = false }

        function test_address_input_disables_keyboard_rewriting() {
            var field = findChild(editor, "pcHostField")
            verify(field.inputMethodHints & Qt.ImhNoPredictiveText)
            verify(field.inputMethodHints & Qt.ImhNoAutoUppercase)
        }

        function test_save_literal_address_data() {
            return [
                { tag: "hyphen", address: "hostname-01" },
                { tag: "mixed-case-port", address: "Hostname-01.example.test:3390" },
                { tag: "vpn-ip", address: "192.168.1.50:3391" },
                { tag: "ipv6", address: "[fd00::1234]:3392" },
                { tag: "bare-ipv6", address: "fd00::1234" }
            ]
        }

        function test_save_literal_address(data) {
            var field = findChild(editor, "pcHostField")
            field.forceActiveFocus()
            field.remove(0, field.length)
            field.insert(0, data.address)
            mouseClick(findChild(editor, "savePcButton"))
            compare(saved.count, 1)
            compare(saved.signalArguments[0][0].hostInput, data.address)
            compare(editor.active, false)
        }

        function test_typing_hyphen_and_digits_saves_the_whole_hostname() {
            var field = findChild(editor, "pcHostField")
            field.forceActiveFocus()
            for (var i = 0; i < "hostname".length; i++) {
                keyClick("hostname".charCodeAt(i) - 32)
            }
            keyClick(Qt.Key_Minus)
            keyClick(Qt.Key_0)
            keyClick(Qt.Key_1)
            compare(field.text, "hostname-01")
            mouseClick(findChild(editor, "savePcButton"))
            compare(saved.signalArguments[0][0].hostInput, "hostname-01")
        }

        function test_edit_reopen_and_save_preserves_suffix() {
            editor.openForEdit({ id: "saved-id", address: "hostname-01:3390" })
            var field = findChild(editor, "pcHostField")
            compare(field.text, "hostname-01:3390")
            // Use editor operations: assigning .text would remove its QML binding.
            field.remove(0, field.length)
            field.insert(0, "hostname-02:3391")
            mouseClick(findChild(editor, "savePcButton"))
            compare(saved.signalArguments[0][0].hostInput, "hostname-02:3391")
            compare(saved.signalArguments[0][0].id, "saved-id")
            editor.openForEdit({ id: "another-id", address: "new-host-03" })
            compare(field.text, "new-host-03")
            mouseClick(findChild(editor, "savePcButton"))
            compare(saved.signalArguments[1][0].hostInput, "new-host-03")
        }

        function test_empty_address_keeps_editor_open() {
            var field = findChild(editor, "pcHostField")
            field.remove(0, field.length)
            field.insert(0, "   ")
            mouseClick(findChild(editor, "savePcButton"))
            compare(saved.count, 0)
            compare(editor.active, true)
            verify(editor.validationError.length > 0)
        }
    }
}
