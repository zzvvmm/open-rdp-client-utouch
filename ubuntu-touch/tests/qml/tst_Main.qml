import QtQuick 2.12
import QtTest 1.2
import RdpClient 1.0
import "../../qml" as Touch

Item {
    width:450; height:820
    Touch.Main { id: app; anchors.fill:parent }
    SignalSpy { id:actions; target:RdpBridge; signalName:"actionDispatched" }
    TestCase {
        name:"TouchMainState"
        when:windowShown
        function test_shared_snapshot_reaches_lomiri_root_and_dispatches_connections() {
            RdpBridge.deliverEvent({type:"state_snapshot",appVersion:"0.3.0",appArchitecture:"amd64",
                appFramework:"ubuntu-touch-24.04-1.x",appPlatform:"ubuntu-touch",updateProvider:"openstore",
                profiles:[{id:"pc",displayTitle:"Work",hostname:"example.test",address:"example.test",groupName:"Work",favorite:false}],
                accounts:[],knownCerts:[],settings:{themeMode:"dark",autoCheckUpdates:false}})
            compare(app.appVersion,"0.3.0")
            compare(app.profilesList.length,1)
            actions.clear()
            app.connectToProfile("pc","alice","temporary")
            compare(actions.count,1)
            var action=actions.signalArguments[0][0]
            compare(action.action,"connect_pc")
            compare(action.id,"pc")
            compare(action.viewportWidth,450)
            compare(action.viewportHeight,820)
            RdpBridge.deliverEvent({type:"credentials_required",profileId:"pc",displayTitle:"Work",prefillUsername:"alice"})
            verify(app.showCredPrompt)
            compare(app.credUsername,"alice")
            app.showCredPrompt=false
        }
    }
}
