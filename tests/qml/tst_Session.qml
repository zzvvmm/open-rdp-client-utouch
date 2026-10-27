import QtQuick 2.12
import QtTest 1.2
import "../../qml/pages" as Pages

Item {
    id: fixture
    width: 450
    height: 820

    Pages.SessionPage { id: session; anchors.fill: parent }
    SignalSpy { id: actions; target: session; signalName: "dispatchAction" }

    TestCase {
        name: "SessionLayout"
        when: windowShown

        function init() {
            session.visible = false
            session.sessionStage = "disconnected"
            fixture.width = 450
            fixture.height = 820
            session.touchMode = "direct_touch"
            session.dynamicResolution = true
            session.desktopScaleFactor = 125
            session.visible = true
            session.sessionStage = "connected"
            actions.clear()
        }

        function cleanup() {
            session.visible = false
            session.sessionStage = "disconnected"
        }

        function test_rotation_coalesces_resize_and_keeps_session_connected() {
            fixture.width = 820
            fixture.height = 450
            fixture.width = 800
            wait(450)
            compare(actions.count, 1)
            var request = actions.signalArguments[0][0]
            compare(request.action, "resize_session")
            compare(request.width, 800)
            compare(request.height, Math.round(findChild(session, "sessionViewport").height))
            compare(request.scaleFactor, 125)
            compare(session.sessionStage, "connected")
        }

        function test_fixed_resolution_rotation_does_not_request_remote_resize() {
            session.dynamicResolution = false
            fixture.width = 820
            fixture.height = 450
            wait(450)
            compare(actions.count, 0)
            compare(session.sessionStage, "connected")
        }

        function test_key_bar_stays_visible_with_keyboard_and_after_rotation() {
            var bar = findChild(session, "sessionVirtualKeyBar")
            var keyboard = findChild(session, "sessionKeyboard")
            verify(bar.visible)
            bar.summonOskRequested()
            compare(keyboard.softwareKeyboardRequested, true)
            verify(bar.visible)
            // Model the area left above a visible keyboard, then rotate it.
            fixture.height = 450
            fixture.width = 820
            verify(bar.y >= 0)
            compare(bar.y + bar.height, session.height)
            var viewport = findChild(session, "sessionViewport")
            verify(viewport.y + viewport.height <= bar.y)
            bar.virtualKeyTapped("Bksp")
            var request = actions.signalArguments[actions.count - 1][0]
            compare(request.action, "send_virtual_key")
            compare(request.key, "Bksp")
            keyboard.hideSoftwareKeyboard()
            verify(bar.visible)
            session.touchMode = "mouse_pointer"
            verify(bar.visible)
        }

        function test_hidden_session_does_not_resize_or_keep_dragging() {
            session.dragLocked = true
            session.visible = false
            compare(session.dragLocked, false)
            compare(actions.signalArguments[0][0].action, "mouse_button")
            actions.clear()
            fixture.width = 820
            fixture.height = 450
            wait(450)
            compare(actions.count, 0)
        }
    }
}
