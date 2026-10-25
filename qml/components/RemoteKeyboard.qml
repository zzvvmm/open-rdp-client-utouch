import QtQuick 2.12

TextInput {
    id: root
    width: 1
    height: 1
    opacity: 0
    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

    signal dispatchAction(var payload)

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

    onTextChanged: {
        if (text.length > 0) {
            if (enabled) root.dispatchAction({ action: "send_qt_key", qtKey: 0, text: text, pressed: true })
            text = ""
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onShortcutOverride: event.accepted = !!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
    Keys.onPressed: event.accepted = root.handleKey(event.key, event.modifiers)
}
