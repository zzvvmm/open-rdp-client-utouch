import QtQuick 2.12

FocusScope {
    id: root
    width: 1
    height: 1
    opacity: 0
    property var inputMethod: Qt.inputMethod
    property bool softwareKeyboardRequested: false
    property bool keyboardWasVisible: false

    signal dispatchAction(var payload)

    function restoreFocus() {
        if (!enabled || !visible) return
        if (softwareKeyboardRequested && editorLoader.item) {
            editorLoader.item.forceActiveFocus()
        } else {
            root.forceActiveFocus()
            if (inputMethod.visible) inputMethod.hide()
        }
    }

    function showSoftwareKeyboard() {
        if (!enabled || !visible) return
        if (softwareKeyboardRequested) return
        keyboardWasVisible = false
        softwareKeyboardRequested = true
        restoreFocus()
        inputMethod.show()
        keyboardWasVisible = inputMethod.visible
    }

    function hideSoftwareKeyboard() {
        if (!softwareKeyboardRequested) return
        softwareKeyboardRequested = false
        keyboardWasVisible = false
        inputMethod.hide()
        restoreFocus()
    }

    function toggleSoftwareKeyboard() {
        if (softwareKeyboardRequested) hideSoftwareKeyboard()
        else showSoftwareKeyboard()
    }

    function sendText(value) {
        if (enabled && visible && value.length > 0)
            root.dispatchAction({ action: "send_qt_key", qtKey: 0, text: value, pressed: true })
    }

    onEnabledChanged: if (!enabled) hideSoftwareKeyboard()
    onVisibleChanged: if (!visible) hideSoftwareKeyboard()

    Connections {
        target: root.inputMethod
        function onVisibleChanged() {
            if (!root.softwareKeyboardRequested) return
            if (root.inputMethod.visible) root.keyboardWasVisible = true
            else if (root.keyboardWasVisible) root.hideSoftwareKeyboard()
        }
    }

    function specialKeyName(qtKey) {
        switch (qtKey) {
        case Qt.Key_Escape: return "Esc"
        case Qt.Key_Tab:
        case Qt.Key_Backtab: return "Tab"
        case Qt.Key_Backspace: return "Bksp"
        case Qt.Key_Return:
        case Qt.Key_Enter: return "Enter"
        case Qt.Key_Insert: return "Ins"
        case Qt.Key_Delete: return "Del"
        case Qt.Key_Home: return "Home"
        case Qt.Key_End: return "End"
        case Qt.Key_Left: return "Left"
        case Qt.Key_Right: return "Right"
        case Qt.Key_Up: return "Up"
        case Qt.Key_Down: return "Down"
        case Qt.Key_PageUp: return "PgUp"
        case Qt.Key_PageDown: return "PgDn"
        }
        if (qtKey >= Qt.Key_F1 && qtKey <= Qt.Key_F12)
            return "F" + (qtKey - Qt.Key_F1 + 1)
        return ""
    }

    function handleKey(qtKey, modifiers) {
        if (qtKey === Qt.Key_Control || qtKey === Qt.Key_Alt
                || qtKey === Qt.Key_Shift || qtKey === Qt.Key_Meta) return true
        var special = specialKeyName(qtKey)
        var shortcut = modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
        if (!special && !shortcut) return false
        var keyName = special
        if (!keyName && qtKey >= Qt.Key_Space && qtKey <= Qt.Key_AsciiTilde)
            keyName = qtKey === Qt.Key_Space ? "Space" : String.fromCharCode(qtKey).toLowerCase()
        if (!keyName) return false
        var chord = []
        if (modifiers & Qt.ControlModifier) chord.push("ctrl")
        if (modifiers & Qt.AltModifier) chord.push("alt")
        if (modifiers & Qt.MetaModifier) chord.push("win")
        if ((modifiers & Qt.ShiftModifier) || qtKey === Qt.Key_Backtab) chord.push("shift")
        if (chord.length) {
            chord.push(keyName)
            root.dispatchAction({ action: "send_chord", chord: chord.join("+") })
        } else {
            root.dispatchAction({ action: "send_virtual_key", key: keyName })
        }
        return true
    }

    Loader {
        id: editorLoader
        active: root.softwareKeyboardRequested
        sourceComponent: TextInput {
            objectName: "remoteTextInput"
            width: 1
            height: 1
            focus: true
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            onTextChanged: {
                if (text.length > 0) {
                    root.sendText(text)
                    text = ""
                }
            }

            Keys.priority: Keys.BeforeItem
            Keys.onShortcutOverride: event.accepted = !!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            Keys.onPressed: event.accepted = root.handleKey(event.key, event.modifiers)
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onShortcutOverride: event.accepted = !!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
    Keys.onPressed: {
        if (root.handleKey(event.key, event.modifiers)) {
            event.accepted = true
        } else if (event.text.length > 0) {
            root.sendText(event.text)
            event.accepted = true
        } else {
            event.accepted = false
        }
    }
}
