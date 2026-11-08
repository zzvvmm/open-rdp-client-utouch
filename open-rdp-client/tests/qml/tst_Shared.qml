import QtQuick 2.12
import QtTest 1.2
import OpenRdp 1.0

Item {
    width:600; height:500
    QtObject {
        id: testBridge
        signal eventJsonReceived(string jsonString)
        signal actionDispatched(var action)
        function dispatchJson(value) { actionDispatched(JSON.parse(value)) }
        function deliverEvent(value) { eventJsonReceived(JSON.stringify(value)) }
    }
    AppState { id: state; bridge:testBridge; width:600; height:500 }
    VirtualTrackpad { id:pad; width:400; height:300; canvasX:20; canvasY:10; canvasW:360; canvasH:280; remoteWidth:1280; remoteHeight:720 }
    SignalSpy { id:buttons; target:pad; signalName:"mouseButton" }
    SignalSpy { id:actions; target:testBridge; signalName:"actionDispatched" }
    TestCase {
        name:"SharedCore"
        when:windowShown
        function init() { pad.cancelInput();buttons.clear();actions.clear() }
        function test_zero_cursor_coordinates_and_platform_metadata() {
            state.cursorX = 400;state.cursorY = 300
            testBridge.deliverEvent({type:"frame_updated",cursorX:0,cursorY:0})
            compare(state.cursorX,0);compare(state.cursorY,0)
            testBridge.deliverEvent({type:"state_snapshot",appPlatform:"linux",updateProvider:"manual",appVersion:"0.3.0",settings:{}})
            compare(state.appPlatform,"linux");compare(state.updateProvider,"manual")
        }
        function test_mouse_drag_cancellation_has_matching_release() {
            mousePress(pad,100,100,Qt.LeftButton)
            pad.cancelInput()
            compare(buttons.count,2)
            compare(buttons.signalArguments[0][1],true)
            compare(buttons.signalArguments[1][1],false)
        }
        function test_credentials_prompt_and_connection_viewport() {
            testBridge.deliverEvent({type:"credentials_required",profileId:"pc",displayTitle:"Work",prefillUsername:"alice"})
            verify(state.showCredPrompt)
            compare(state.credUsername,"alice")
            state.connectToProfile("pc","alice","secret")
            var action=actions.signalArguments[actions.count-1][0]
            compare(action.action,"connect_pc")
            compare(action.viewportWidth,600)
            compare(action.viewportHeight,500)
        }
    }
}
