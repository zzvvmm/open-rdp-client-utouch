import QtQuick 2.12
import QtTest 1.2
import OpenRdp 1.0

Item {
    width: 600
    height: 500
    QtObject {
        id: testBridge
        signal eventJsonReceived(string jsonString)
        signal actionDispatched(var action)
        function dispatchJson(value) {
            actionDispatched(JSON.parse(value));
        }
        function deliverEvent(value) {
            eventJsonReceived(JSON.stringify(value));
        }
    }
    AppState {
        id: state
        bridge: testBridge
        width: 600
        height: 500
    }
    VirtualTrackpad {
        id: pad
        width: 400
        height: 300
        canvasX: 20
        canvasY: 10
        canvasW: 360
        canvasH: 280
        remoteWidth: 1280
        remoteHeight: 720
    }
    SignalSpy {
        id: buttons
        target: pad
        signalName: "mouseButton"
    }
    SignalSpy {
        id: actions
        target: testBridge
        signalName: "actionDispatched"
    }
    TestCase {
        name: "SharedCore"
        when: windowShown
        function init() {
            pad.cancelInput();
            state.activeProfileId = "";
            state.sessionProfile = null;
            state.sessionStage = "disconnected";
            state.cancelReplacement();
            state.cancelCredentials();
            state.requestHandlers = ({});
            buttons.clear();
            actions.clear();
        }
        function test_zero_cursor_coordinates_and_platform_metadata() {
            state.cursorX = 400;
            state.cursorY = 300;
            testBridge.deliverEvent({
                    "type": "frame_updated",
                    "cursorX": 0,
                    "cursorY": 0
                });
            compare(state.cursorX, 0);
            compare(state.cursorY, 0);
            testBridge.deliverEvent({
                    "type": "state_snapshot",
                    "appPlatform": "linux",
                    "updateProvider": "manual",
                    "appVersion": "0.3.0",
                    "settings": {}
                });
            compare(state.appPlatform, "linux");
            compare(state.updateProvider, "manual");
        }
        function test_mouse_drag_cancellation_has_matching_release() {
            mousePress(pad, 100, 100, Qt.LeftButton);
            pad.cancelInput();
            compare(buttons.count, 2);
            compare(buttons.signalArguments[0][1], true);
            compare(buttons.signalArguments[1][1], false);
        }
        function test_action_results_complete_only_the_matching_request() {
            var completed = 0;
            var resultMessage = "";
            var request = state.submitAction({
                    "action": "save_pc",
                    "hostInput": "host"
                }, function (result) {
                    completed++;
                    resultMessage = result.message;
                });
            testBridge.deliverEvent({
                    "type": "action_result",
                    "requestId": "other",
                    "ok": true
                });
            compare(completed, 0);
            testBridge.deliverEvent({
                    "type": "action_result",
                    "requestId": request,
                    "ok": false,
                    "message": "Disk full"
                });
            compare(completed, 1);
            compare(resultMessage, "Disk full");
            testBridge.deliverEvent({
                    "type": "action_result",
                    "requestId": request,
                    "ok": true
                });
            compare(completed, 1);
        }
        function test_replacement_is_explicit_and_cancel_does_not_disconnect() {
            state.activeProfileId = "old";
            state.sessionStage = "connected";
            state.activePcTitle = "Current PC";
            state.profilesList = [{
                    "id": "other",
                    "displayTitle": "Another PC"
                }];
            state.connectToProfile("other", "", "");
            compare(state.activePcTitle, "Current PC");
            state.cancelReplacement();
            state.quickConnect("new-host", "");
            verify(state.replacementPromptVisible);
            compare(actions.count, 0);
            state.cancelReplacement();
            compare(actions.count, 0);
            state.quickConnect("new-host", "");
            state.confirmReplacement();
            compare(actions.count, 1);
            compare(actions.signalArguments[0][0].action, "quick_connect");
        }
        function test_temporary_snapshot_and_retry_do_not_depend_on_saved_profiles() {
            testBridge.deliverEvent({
                    "type": "state_snapshot",
                    "profiles": [],
                    "session": {
                        "activeProfileId": "temp",
                        "activeProfile": {
                            "id": "temp",
                            "displayTitle": "Temporary",
                            "resolutionPreset": "dynamic"
                        },
                        "isTemporary": true,
                        "stage": "error",
                        "stageDetail": "Connection refused"
                    }
                });
            compare(state.activePc.displayTitle, "Temporary");
            verify(state.temporarySession);
            compare(state.sessionStageDetail, "Connection refused");
            state.retryConnection();
            compare(actions.signalArguments[0][0].id, "temp");
            compare(actions.signalArguments[0][0].password, undefined);
            state.credPassword = "temporary";
            state.cancelCredentials();
            compare(state.credPassword, "");
            state.cancelConnection();
            verify(!state.inSessionView);
            compare(actions.signalArguments[actions.count - 1][0].action, "disconnect_session");
        }
        function test_pending_prompts_belong_to_their_connection() {
            testBridge.deliverEvent({type:"credentials_required",profileId:"new",displayTitle:"New PC"})
            state.credPassword = "temporary"
            testBridge.deliverEvent({type:"session_ended",profileId:"old",isError:true,reason:"Old session closed"})
            verify(state.showCredPrompt)
            compare(state.credPassword,"temporary")
            testBridge.deliverEvent({type:"session_ended",profileId:"new",isError:true})
            verify(!state.showCredPrompt)
            compare(state.credPassword,"")
            state.activeProfileId = "old"
            state.pendingCertPrompt = {profileId:"old",host:"old.test"}
            testBridge.deliverEvent({type:"state_snapshot",session:{activeProfileId:"new",stage:"resolving"}})
            compare(state.pendingCertPrompt,null)
        }
        function test_credentials_prompt_and_connection_viewport() {
            testBridge.deliverEvent({
                    "type": "credentials_required",
                    "profileId": "pc",
                    "displayTitle": "Work",
                    "prefillUsername": "alice"
                });
            verify(state.showCredPrompt);
            compare(state.credUsername, "alice");
            state.connectToProfile("pc", "alice", "secret");
            var action = actions.signalArguments[actions.count - 1][0];
            compare(action.action, "connect_pc");
            compare(action.viewportWidth, 600);
            compare(action.viewportHeight, 500);
        }
    }
}
