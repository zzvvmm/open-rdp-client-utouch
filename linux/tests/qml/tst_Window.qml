import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtTest 1.2
import "../../qml" as Desktop

TestCase {
    id: tests
    name: "DesktopWindow"
    when: windowShown
    property var app
    Component { id: factory; Desktop.Main { visible: false } }
    function initTestCase() { app = factory.createObject(null); verify(app !== null) }
    function cleanupTestCase() { app.destroy() }
    function cleanup() {
        app.appState.showCredPrompt = false
        app.appState.pendingCertPrompt = null
        app.appState.inSessionView = false
        app.visible = false
    }
    function test_repeated_certificate_prompts_close_and_reopen() {
        app.visible = true
        for (var i = 0; i < 2; ++i) {
            RdpBridge.deliverEvent({type:"certificate_prompt", host:"example.test", port:3389,
                subjectCn:"PC", issuerCn:"CA", sha256Fingerprint:"AB:CD", isMismatchWarning:i > 0})
            var dialog = findChild(app,"certificateDialog")
            verify(dialog.visible)
            dialog.decision("trust_once")
            tryCompare(dialog,"visible",false)
            compare(app.appState.pendingCertPrompt,null)
        }
    }
    function test_credentials_cancel_clears_password_and_reopens() {
        app.visible = true
        for (var i = 0; i < 2; ++i) {
            RdpBridge.deliverEvent({type:"credentials_required", profileId:"pc", displayTitle:"Work", prefillUsername:"alice"})
            var dialog = findChild(app,"credentialsDialog")
            verify(dialog.visible)
            var password = findChild(app,"credentialPassword")
            password.text = "temporary"
            dialog.reject()
            tryCompare(dialog,"visible",false)
            compare(password.text,"")
            compare(app.appState.showCredPrompt,false)
        }
    }
    function test_fullscreen_returns_to_window_and_theme_changes() {
        app.visible = true
        app.toggleFullscreen()
        tryCompare(app,"visibility",Window.FullScreen)
        app.toggleFullscreen()
        tryCompare(app,"visibility",Window.Windowed)
        app.appState.appSettings = {themeMode:"light"}
        compare(app.palette.text,"#1b2028")
        app.appState.appSettings = {themeMode:"dark"}
        compare(app.palette.text,"#f3f6fa")
    }
}
