import QtQuick 2.12
import QtTest 1.2
import "../../qml/components" as Components

Item {
    width: 600
    height: 700

    Components.VirtualTrackpad {
        id: pad
        width: 400
        height: 300
    }

    QtObject {
        id: mockInputMethod
        property bool visible: false
        property int showCount: 0
        property int hideCount: 0
        function show() {
            showCount++
            visible = true
        }
        function hide() {
            hideCount++
            visible = false
        }
    }

    Components.RemoteKeyboard {
        id: keyboard
        inputMethod: mockInputMethod
    }

    Components.PointerControls {
        id: controls
        y: 350
        width: 400
    }

    Components.SessionHudPill {
        id: hud
        visible: false
        width: 600
        height: 200
    }

    SignalSpy { id: clicks; target: pad; signalName: "mouseClick" }
    SignalSpy { id: buttons; target: pad; signalName: "mouseButton" }
    SignalSpy { id: movement; target: pad; signalName: "relativeMove" }
    SignalSpy { id: absolute; target: pad; signalName: "absoluteMove" }
    SignalSpy { id: scroll; target: pad; signalName: "mouseScroll" }
    SignalSpy { id: keys; target: keyboard; signalName: "dispatchAction" }
    SignalSpy { id: controlClicks; target: controls; signalName: "clickRequested" }
    SignalSpy { id: dragToggles; target: controls; signalName: "toggleDragRequested" }

    TestCase {
        name: "RemoteInteraction"
        when: windowShown

        function init() {
            pad.cancelInput()
            pad.visible = true
            pad.touchMode = "mouse_pointer"
            pad.dragLocked = false
            pad.movementScale = 1.0
            pad.canvasX = 0
            pad.canvasY = 0
            pad.canvasW = 400
            pad.canvasH = 300
            controls.dragLocked = false
            keyboard.hideSoftwareKeyboard()
            mockInputMethod.visible = false
            mockInputMethod.showCount = 0
            mockInputMethod.hideCount = 0
            keyboard.restoreFocus()
            clicks.clear()
            buttons.clear()
            movement.clear()
            absolute.clear()
            scroll.clear()
            keys.clear()
            controlClicks.clear()
            dragToggles.clear()
        }

        function cleanup() {
            pad.cancelInput()
        }

        function test_double_tap_does_not_send_three_clicks() {
            var sequence = touchEvent(pad)
            sequence.press(0, pad, 100, 100).commit()
            sequence.release(0, pad, 100, 100).commit()
            sequence.press(0, pad, 100, 100).commit()
            sequence.release(0, pad, 100, 100).commit()
            compare(clicks.count, 2)
            compare(clicks.signalArguments[0][1], false)
            compare(clicks.signalArguments[1][1], false)
            compare(buttons.count, 0)
        }

        function test_shortcuts_drawer_stays_inside_landscape_viewport() {
            hud.expanded = true
            hud.showChordsMenu = true
            var drawer = findChild(hud, "sessionDrawer")
            var scrollArea = findChild(hud, "sessionDrawerScroll")
            verify(drawer.y >= 0)
            verify(drawer.y + drawer.height <= hud.height)
            verify(scrollArea.contentHeight > scrollArea.height)
            scrollArea.contentY = scrollArea.contentHeight - scrollArea.height
            verify(scrollArea.contentY > 0)
            hud.expanded = false
            hud.showChordsMenu = false
        }

        function test_two_finger_tap_waits_for_both_releases() {
            var sequence = touchEvent(pad)
            sequence.press(0, pad, 100, 100).commit()
            sequence.stationary(0).press(1, pad, 140, 100).commit()
            sequence.release(0, pad, 100, 100).stationary(1).commit()
            compare(clicks.count, 0)
            sequence.release(1, pad, 140, 100).commit()
            compare(clicks.count, 1)
            compare(clicks.signalArguments[0][0], 2)
            compare(buttons.count, 0)
        }

        function test_long_press_drag_releases_on_cancel() {
            pad.beginSingle(100, 100)
            tryCompare(buttons, "count", 1, 800)
            compare(buttons.signalArguments[0][1], true)
            pad.updateSingle(160, 120)
            pad.cancelInput()
            compare(buttons.count, 2)
            compare(buttons.signalArguments[1][1], false)
            compare(buttons.signalArguments[1][2], -1)
            compare(clicks.count, 0)
        }

        function test_direct_touch_drag_and_mode_switch_release() {
            pad.touchMode = "direct_touch"
            pad.beginSingle(100, 100)
            pad.updateSingle(160, 120)
            compare(buttons.count, 1)
            compare(buttons.signalArguments[0][1], true)
            pad.touchMode = "mouse_pointer"
            compare(buttons.count, 2)
            compare(buttons.signalArguments[1][1], false)
            pad.finishTouch()
            compare(clicks.count, 0)
        }

        function test_direct_touch_hold_is_only_a_right_click() {
            pad.touchMode = "direct_touch"
            pad.beginSingle(100, 100)
            tryCompare(clicks, "count", 1, 800)
            pad.finishTouch()
            compare(clicks.count, 1)
            compare(clicks.signalArguments[0][0], 2)
            compare(buttons.count, 0)
        }

        function test_letterbox_tap_is_ignored() {
            pad.touchMode = "direct_touch"
            pad.canvasX = 60
            pad.canvasW = 280
            var sequence = touchEvent(pad)
            sequence.press(0, pad, 20, 100).commit()
            sequence.release(0, pad, 20, 100).commit()
            compare(clicks.count, 0)
            compare(buttons.count, 0)
        }

        function test_scroll_keeps_small_deltas_after_threshold() {
            pad.beginTwo(100, 100)
            pad.updateTwo(100, 120)
            pad.updateTwo(100, 120.2)
            compare(scroll.count, 2)
            compare(scroll.signalArguments[0][0], 60)
            compare(scroll.signalArguments[1][0], 1)
            pad.finishTouch()
            compare(clicks.count, 0)
        }

        function test_precision_reduces_pointer_movement() {
            pad.movementScale = 0.35
            pad.beginSingle(100, 100)
            pad.updateSingle(120, 100)
            compare(movement.count, 1)
            fuzzyCompare(movement.signalArguments[0][0], 22.4, 0.01)
        }

        function test_swipe_returning_to_start_does_not_click() {
            pad.beginSingle(100, 100)
            pad.updateSingle(160, 100)
            pad.updateSingle(100, 100)
            pad.finishTouch()
            compare(clicks.count, 0)
        }

        function test_two_finger_letterbox_tap_is_ignored() {
            pad.touchMode = "direct_touch"
            pad.canvasX = 60
            pad.canvasW = 280
            pad.beginTwo(20, 100)
            pad.finishTouch()
            compare(clicks.count, 0)
        }

        function test_drag_lock_does_not_emit_extra_clicks() {
            pad.dragLocked = true
            pad.beginSingle(100, 100)
            pad.finishTouch()
            compare(clicks.count, 0)
            compare(buttons.count, 0)
        }

        function test_physical_mouse_drag_has_down_and_up() {
            mousePress(pad, 100, 100, Qt.LeftButton)
            mouseMove(pad, 160, 120)
            mouseRelease(pad, 160, 120, Qt.LeftButton)
            compare(buttons.count, 2)
            compare(buttons.signalArguments[0][0], 1)
            compare(buttons.signalArguments[0][1], true)
            compare(buttons.signalArguments[1][1], false)
            verify(absolute.count > 0)
            compare(clicks.count, 0)
        }

        function test_physical_mouse_double_click_is_balanced() {
            mouseDoubleClickSequence(pad, 100, 100, Qt.LeftButton)
            compare(buttons.count, 4)
            compare(buttons.signalArguments[0][1], true)
            compare(buttons.signalArguments[1][1], false)
            compare(buttons.signalArguments[2][1], true)
            compare(buttons.signalArguments[3][1], false)
        }

        function test_hardware_shortcuts_and_navigation() {
            keyClick(Qt.Key_C, Qt.ControlModifier)
            compare(keys.count, 1)
            compare(keys.signalArguments[0][0].action, "send_chord")
            compare(keys.signalArguments[0][0].chord, "ctrl+c")
            keyClick(Qt.Key_Right)
            compare(keys.count, 2)
            compare(keys.signalArguments[1][0].action, "send_virtual_key")
            compare(keys.signalArguments[1][0].key, "Right")
            keyClick(Qt.Key_C, Qt.ControlModifier | Qt.ShiftModifier)
            compare(keys.count, 3)
            compare(keys.signalArguments[2][0].chord, "ctrl+shift+c")
        }

        function test_keyboard_text_is_committed_once() {
            keyboard.showSoftwareKeyboard()
            var input = findChild(keyboard, "remoteTextInput")
            verify(input !== null)
            input.text = "hello world"
            compare(keys.count, 1)
            compare(keys.signalArguments[0][0].qtKey, 0)
            compare(keys.signalArguments[0][0].text, "hello world")
            compare(input.text, "")
        }

        function test_software_keyboard_lifecycle_and_focus_restoration() {
            verify(!keyboard.softwareKeyboardRequested)
            compare(mockInputMethod.showCount, 0)
            keyboard.restoreFocus()
            compare(mockInputMethod.showCount, 0)
            verify(!keyboard.softwareKeyboardRequested)

            keyClick(Qt.Key_A)
            compare(keys.count, 1)
            compare(keys.signalArguments[0][0].text, "a")
            compare(mockInputMethod.showCount, 0)

            keyboard.toggleSoftwareKeyboard()
            verify(keyboard.softwareKeyboardRequested)
            compare(mockInputMethod.showCount, 1)

            keyboard.restoreFocus()
            compare(mockInputMethod.showCount, 1)

            mockInputMethod.hide()
            verify(!keyboard.softwareKeyboardRequested)

            keyboard.restoreFocus()
            compare(mockInputMethod.showCount, 1)
            verify(!keyboard.softwareKeyboardRequested)
        }

        function test_explicit_mouse_controls() {
            mouseClick(findChild(controls, "pointer_right"))
            compare(controlClicks.count, 1)
            compare(controlClicks.signalArguments[0][0], 2)
            mouseClick(findChild(controls, "pointer_double"))
            compare(controlClicks.count, 2)
            compare(controlClicks.signalArguments[1][1], true)
            mouseClick(findChild(controls, "pointer_drag"))
            compare(dragToggles.count, 1)
        }
    }
}
