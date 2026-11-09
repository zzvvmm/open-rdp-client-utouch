import QtQuick 2.12
import QtTest 1.2
import RdpClient 1.0
import OpenRdp 1.0 as Shared
import "../../qml/components" as Components
import "../../qml/pages" as Pages

Item {
    width: 390
    height: 844
    Shared.AppState {
        id: state
        bridge: RdpBridge
        anchors.fill: parent
    }
    Components.ConnectionDialogs {
        id: dialogs
        appState: state
    }
    Pages.DevicesPage {
        id: devices
        anchors.fill: parent
        visible: false
    }
    SignalSpy {
        id: actions
        target: RdpBridge
        signalName: "actionDispatched"
    }
    TestCase {
        name: "TouchLibraryWorkflows"
        when: windowShown
        function init() {
            dialogs.mode = "";
            dialogs.busy = false;
            state.activeProfileId = "";
            state.sessionStage = "disconnected";
            state.cancelReplacement();
            state.requestHandlers = ({});
            actions.clear();
        }
        function finish(result) {
            var action = actions.signalArguments[actions.count - 1][0];
            RdpBridge.deliverEvent({
                    "type": "action_result",
                    "requestId": action.requestId,
                    "action": action.action,
                    "ok": result,
                    "message": result ? "" : "Address rejected"
                });
        }
        function test_quick_connect_preserves_rejected_input_and_closes_after_success() {
            dialogs.openQuick();
            var host = findChild(dialogs, "quickConnectHost");
            host.text = "[fd00::1234]:3390";
            mouseClick(findChild(dialogs, "quickConnectSubmit"));
            compare(actions.count, 1);
            compare(actions.signalArguments[0][0].action, "quick_connect");
            compare(actions.signalArguments[0][0].hostInput, "[fd00::1234]:3390");
            verify(dialogs.visible);
            verify(dialogs.busy);
            finish(false);
            compare(dialogs.errorMessage, "Address rejected");
            compare(host.text, "[fd00::1234]:3390");
            verify(!dialogs.busy);
            mouseClick(findChild(dialogs, "quickConnectSubmit"));
            finish(true);
            verify(!dialogs.visible);
        }
        function test_replacing_a_session_requires_the_second_explicit_action() {
            state.activeProfileId = "active";
            state.sessionStage = "connected";
            dialogs.openQuick();
            findChild(dialogs, "quickConnectHost").text = "other-pc";
            mouseClick(findChild(dialogs, "quickConnectSubmit"));
            verify(dialogs.replacing);
            compare(actions.count, 0);
            mouseClick(findChild(dialogs, "quickConnectSubmit"));
            compare(actions.count, 1);
            compare(actions.signalArguments[0][0].action, "quick_connect");
            finish(true);
            verify(!dialogs.visible);
        }
        function test_save_temporary_pc_requires_a_successful_result() {
            state.activePcTitle = "Temporary PC";
            dialogs.openSave();
            mouseClick(findChild(dialogs, "quickConnectSubmit"));
            compare(actions.signalArguments[0][0].action, "save_temporary_pc");
            compare(actions.signalArguments[0][0].friendlyName, "Temporary PC");
            finish(false);
            verify(dialogs.visible);
            mouseClick(findChild(dialogs, "quickConnectSubmit"));
            finish(true);
            verify(!dialogs.visible);
        }
        function test_library_recent_search_and_phone_landscape_layout() {
            devices.profiles = [{
                    "id": "a",
                    "displayTitle": "Alpha",
                    "address": "a.test",
                    "groupName": "Office",
                    "favorite": true,
                    "lastConnectedEpoch": 0
                }, {
                    "id": "b",
                    "displayTitle": "Beta",
                    "address": "b.test",
                    "groupName": "Office",
                    "favorite": false,
                    "lastConnectedEpoch": 20
                }];
            devices.searchQuery = " office ";
            compare(devices.visibleList.length, 2);
            devices.selectedFilter = "recent";
            compare(devices.visibleList.length, 1);
            compare(devices.visibleList[0].id, "b");
            devices.anchors.fill = undefined;
            devices.width = 820;
            devices.height = 346;
            verify(devices.shortLayout);
            verify(findChild(devices, "pcGrid").compact);
            devices.width = 390;
            devices.height = 740;
        }
    }
}
