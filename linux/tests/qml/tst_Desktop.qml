import QtQuick 2.15
import QtTest 1.2
import OpenRdp 1.0
import "../../qml" as Desktop

Item {
    id: fixture
    width: 1100
    height: 760
    AppState { id: state }
    Desktop.SessionPage { id: session; anchors.fill: parent; appState: state; visible: false }
    Desktop.PcEditorDialog { id: editor; accounts:[{id:"account-1", displayName:"Work"}] }
    Desktop.AccountsPage { id: accounts; anchors.fill:parent; visible:false }
    Desktop.CertificateDialog { id: certificate }
    Desktop.DevicesPage { id: devices; anchors.fill:parent; visible:false }
    SignalSpy { id: actions; target:RdpBridge; signalName:"actionDispatched" }
    SignalSpy { id: saved; target:editor; signalName:"saveRequested" }
    SignalSpy { id: accountSaved; target:accounts; signalName:"dispatchAction" }
    SignalSpy { id: trust; target:certificate; signalName:"decision" }
    TestCase {
        name: "DesktopWorkflows"
        when: windowShown
        function init() {
            session.visible = false
            session.blocked = false
            fixture.width = 1100
            fixture.height = 760
            state.profilesList = [{id:"pc-1",displayTitle:"PC",resolutionPreset:"dynamic",scaleFactor:125}]
            state.activeProfileId = "pc-1"
            state.sessionStage = "connected"
            editor.close()
            accounts.visible = false
            certificate.prompt = null
            wait(400)
            actions.clear(); saved.clear(); accountSaved.clear(); trust.clear()
        }
        function cleanup() { session.visible = false; editor.close(); certificate.prompt = null }
        function test_dashboard_search_filters_profiles() {
            devices.profiles = [{id:"a",displayTitle:"Work",address:"work.test",groupName:"Office",favorite:true},
                                {id:"b",displayTitle:"Home",address:"home.test",groupName:"Personal",favorite:false}]
            var search = findChild(devices,"pcSearch")
            search.text = ""
            compare(devices.filteredProfiles.length,2)
            search.text = "office"
            compare(devices.filteredProfiles.length,1)
            compare(devices.filteredProfiles[0].id,"a")
            search.text = "missing"
            compare(devices.filteredProfiles.length,0)
            search.text = ""
        }
        function test_pc_editor_validation_and_roundtrip() {
            editor.openForNew({defaultResolution:"native",defaultScaleFactor:100,defaultAudioMode:"disabled",defaultTouchMode:"direct_touch",defaultClipboardEnabled:false})
            verify(!editor.save())
            verify(editor.visible)
            verify(editor.validationError.length > 0)
            editor.openForEdit({id:"pc-2",address:"[2001:db8::1]:3390",friendlyName:"Work",accountId:"account-1",resolutionPreset:"1600x900",scaleFactor:150,audioMode:"play_on_remote",clipboardRedirection:false,defaultTouchMode:"mouse_pointer",enableNla:false})
            verify(editor.save())
            compare(saved.count, 1)
            var pc = saved.signalArguments[0][0]
            compare(pc.hostInput,"[2001:db8::1]:3390")
            compare(pc.resolutionPreset,"1600x900")
            compare(pc.accountId,"account-1")
            compare(pc.audioMode,"play_on_remote")
            compare(pc.enableNla,false)
            compare(pc.clipboardRedirection,false)
        }
        function test_account_editor_and_password_clear() {
            accounts.visible = true
            accounts.editAccount({id:"account-1",username:"alice",domain:"CORP",displayName:"Work"})
            var password = findChild(accounts,"accountPassword")
            password.text = "temporary"
            verify(accounts.saveAccount())
            compare(accountSaved.count,1)
            compare(accountSaved.signalArguments[0][0].domain,"CORP")
            compare(accountSaved.signalArguments[0][0].password,"temporary")
            compare(password.text,"")
        }
        function test_dynamic_resize_coalesces_and_fixed_does_not_resize() {
            session.visible = true
            fixture.width = 1000
            fixture.width = 950
            wait(450)
            var resizes = actions.signalArguments.map(function(args) { return args[0] }).filter(function(action) { return action.action === "resize_session" })
            compare(resizes.length,1)
            var resize = resizes[0]
            compare(resize.action,"resize_session")
            compare(resize.width,session.viewportWidth)
            compare(resize.height,session.viewportHeight)
            compare(resize.scaleFactor,125)
            state.profilesList = [{id:"pc-1",resolutionPreset:"1920x1080",scaleFactor:100}]
            actions.clear()
            fixture.width = 900
            wait(450)
            var fixedResizes = actions.signalArguments.filter(function(args) { return args[0].action === "resize_session" })
            compare(fixedResizes.length,0)
        }
        function test_modal_blocks_input_and_releases_held_keys() {
            session.visible = true
            session.remoteInput.forceActiveFocus()
            wait(400)
            actions.clear()
            keyPress(Qt.Key_Control)
            session.blocked = true
            verify(!session.remoteInput.enabled)
            compare(actions.count,2)
            compare(actions.signalArguments[0][0].pressed,true)
            compare(actions.signalArguments[1][0].pressed,false)
        }
        function test_certificate_mismatch_and_decision() {
            certificate.prompt = {host:"example.test",port:3389,subjectCn:"Server",issuerCn:"CA",sha256Fingerprint:"AB:CD",isMismatchWarning:true}
            verify(certificate.title.indexOf("changed") >= 0)
            certificate.decision("trust_once")
            compare(trust.count,1)
            compare(trust.signalArguments[0][0],"trust_once")
        }
    }
}
