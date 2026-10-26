import QtQuick 2.12
import QtTest 1.2
import "../../qml/components" as Components
import "../../qml/pages" as Pages

Item {
    id: fixture
    width: 450
    height: 820
    property real clock: 1800000000
    property var preferences: ({})
    property var requests: []

    function save(patch) {
        var next = {}
        for (var key in preferences) next[key] = preferences[key]
        for (var field in patch) if (field !== "action") next[field] = patch[field]
        preferences = next
    }

    function makeRequest() {
        var request = {
            readyState: 0, status: 0, responseText: "", aborted: false,
            onreadystatechange: null,
            open: function(method, url, async) { this.url = url; this.method = method; this.async = async },
            setRequestHeader: function() {},
            send: function() {},
            abort: function() { this.aborted = true }
        }
        requests.push(request)
        return request
    }

    function response(version) {
        return { success: true, data: {
            id: "rdp-client-ut.zzvvmm", published: true, version: version,
            changelog: "fallback notes",
            version_changelogs: [{ version: version, changelog: "Changes for " + version }],
            revisions: [{ version: version, architecture: "arm64", channel: "focal",
                framework: "ubuntu-touch-24.04-1.x" }]
        } }
    }

    function complete(payload, status) {
        var request = requests[requests.length - 1]
        request.status = status === undefined ? 200 : status
        request.responseText = typeof payload === "string" ? payload : JSON.stringify(payload)
        request.readyState = 4
        request.onreadystatechange()
    }

    Components.UpdateManager {
        id: manager
        automaticEnabled: fixture.preferences.autoCheckUpdates !== false
        skippedVersion: fixture.preferences.skippedUpdateVersion || ""
        lastCheckedAt: fixture.preferences.lastUpdateCheckEpoch || 0
        automaticDelayMs: 100000
        now: function() { return fixture.clock }
        onSavePreferences: fixture.save(patch)
    }

    Components.UpdatePrompt {
        id: prompt
        visible: tests.showDialog && manager.promptVisible
        version: manager.availableUpdate ? manager.availableUpdate.version : ""
        changelog: manager.availableUpdate ? manager.availableUpdate.changelog : ""
        installedVersion: manager.installedVersion
        openFailed: manager.status === "openFailed"
        onUpdateNow: manager.updateNow()
        onUpdateLater: manager.updateLater()
        onSkipVersion: manager.skipVersion()
    }

    Pages.SettingsPage {
        id: settings
        anchors.fill: parent
        visible: tests.showSettings
        settings: fixture.preferences
        appVersion: manager.installedVersion
        updateReady: manager.ready
        updateChecking: manager.checking
        updateStatus: manager.status
        skippedVersion: manager.skippedVersion
        onUpdateSettings: fixture.save(payload)
        onCheckUpdatesRequested: manager.checkForUpdates(true)
    }

    SignalSpy { id: openStore; target: manager; signalName: "openStoreRequested" }

    TestCase {
        id: tests
        name: "Updates"
        when: windowShown
        property bool showDialog: false
        property bool showSettings: false

        function init() {
            manager.ready = false
            manager.cancelRequest()
            fixture.width = 450
            fixture.height = 820
            fixture.clock = 1800000000
            fixture.preferences = { autoCheckUpdates: true, skippedUpdateVersion: "", lastUpdateCheckEpoch: 0 }
            fixture.requests = []
            manager.requestFactory = function() { return fixture.makeRequest() }
            manager.requestTimeoutMs = 100000
            manager.installedVersion = "0.1.3"
            manager.architecture = "arm64"
            manager.framework = "ubuntu-touch-24.04-1.x"
            manager.appActive = true
            manager.canPrompt = true
            manager.lastAttemptAt = 0
            manager.availableUpdate = null
            manager.promptRequested = false
            manager.manualPrompt = false
            manager.status = "idle"
            showDialog = false
            showSettings = false
            settings.contentY = 0
            openStore.clear()
            manager.ready = true
        }

        function cleanup() {
            manager.ready = false
            manager.cancelRequest()
            showDialog = false
            showSettings = false
        }

        function test_numeric_versions_data() {
            return [
                { tag: "numeric", a: "0.1.10", b: "0.1.9", expected: 1 },
                { tag: "same", a: "1.2", b: "1.2.0", expected: 0 },
                { tag: "older", a: "0.1.2", b: "0.1.3", expected: -1 },
                { tag: "prerelease", a: "0.2.0-beta", b: "0.1.3", expected: null },
                { tag: "invalid", a: "latest", b: "0.1.3", expected: null },
                { tag: "overflow", a: "0.2.99999999999", b: "0.1.3", expected: null }
            ]
        }

        function test_numeric_versions(data) {
            compare(manager.compareVersions(data.a, data.b), data.expected)
        }

        function test_selects_device_release_and_matching_changelog() {
            var payload = fixture.response("0.1.4")
            payload.data.version = "0.2.0"
            payload.data.changelog = "Wrong architecture notes"
            payload.data.revisions.push({ version: "0.2.0", architecture: "amd64", channel: "focal", framework: manager.framework })
            payload.data.revisions.push({ version: "0.3.0", architecture: "arm64", channel: "focal", framework: "ubuntu-sdk-20.04" })
            payload.data.revisions.push({ version: "0.4.0", architecture: "arm64", channel: "xenial", framework: manager.framework })
            payload.data.revisions.push({ version: "0.5.0-beta", architecture: "arm64", channel: "focal", framework: manager.framework })
            verify(manager.checkAutomatically())
            fixture.complete(payload)
            compare(manager.availableUpdate.version, "0.1.4")
            compare(manager.availableUpdate.changelog, "Changes for 0.1.4")
            verify(manager.promptVisible)
            compare(fixture.preferences.lastUpdateCheckEpoch, fixture.clock)
        }

        function test_auto_default_enabled_and_daily_throttling() {
            fixture.preferences = {} // Legacy settings without the new preference.
            verify(manager.automaticEnabled)
            verify(manager.checkAutomatically())
            fixture.complete(fixture.response("0.1.3"))
            compare(manager.status, "upToDate")
            verify(!manager.promptVisible)
            verify(!manager.checkAutomatically())
            fixture.clock += 86401
            verify(manager.checkAutomatically())
        }

        function test_manual_check_works_when_automatic_disabled_and_skipped() {
            fixture.preferences = { autoCheckUpdates: false, skippedUpdateVersion: "0.1.4" }
            verify(!manager.checkAutomatically())
            showSettings = true
            var button = findChild(settings, "checkUpdatesButton")
            settings.contentY = Math.max(0, button.mapToItem(settings.contentItem, 0, 0).y - 100)
            wait(20)
            mouseClick(button)
            verify(manager.checking)
            verify(!button.enabled)
            fixture.complete(fixture.response("0.1.4"))
            verify(manager.promptVisible)
        }

        function test_skip_suppresses_only_that_version_and_manual_bypasses() {
            manager.checkForUpdates(true)
            fixture.complete(fixture.response("0.1.4"))
            manager.skipVersion()
            compare(fixture.preferences.skippedUpdateVersion, "0.1.4")
            verify(!manager.promptVisible)
            fixture.clock += 86401
            manager.checkAutomatically()
            fixture.complete(fixture.response("0.1.4"))
            verify(!manager.promptVisible)
            manager.checkForUpdates(true)
            fixture.complete(fixture.response("0.1.4"))
            verify(manager.promptVisible)
            manager.updateLater()
            fixture.clock += 86401
            manager.checkAutomatically()
            fixture.complete(fixture.response("0.1.5"))
            verify(manager.promptVisible)
        }

        function test_update_later_reminds_at_next_due_check() {
            manager.checkAutomatically()
            fixture.complete(fixture.response("0.1.4"))
            manager.updateLater()
            compare(fixture.preferences.skippedUpdateVersion, "")
            verify(!manager.promptVisible)
            verify(!manager.checkAutomatically())
            fixture.clock += 86401
            manager.checkAutomatically()
            fixture.complete(fixture.response("0.1.4"))
            verify(manager.promptVisible)
        }

        function test_defers_prompt_during_sessions_and_background() {
            manager.checkForUpdates(true)
            manager.canPrompt = false
            fixture.complete(fixture.response("0.1.4"))
            verify(!manager.promptVisible)
            manager.canPrompt = true
            verify(manager.promptVisible)
            manager.appActive = false
            verify(!manager.promptVisible)
            verify(!manager.checkForUpdates(true))
            manager.appActive = true
            verify(manager.promptVisible)
        }

        function test_update_now_uses_fixed_store_uri_and_handles_failure() {
            manager.checkForUpdates(true)
            fixture.complete(fixture.response("0.1.4"))
            manager.updateNow()
            compare(openStore.count, 1)
            compare(openStore.signalArguments[0][0], "openstore://rdp-client-ut.zzvvmm")
            manager.storeOpened(false)
            compare(manager.status, "openFailed")
            verify(manager.promptVisible)
            manager.updateNow()
            manager.storeOpened(true)
            compare(openStore.count, 2)
            verify(!manager.promptVisible)
        }

        function test_dialog_update_now_later_and_escape() {
            manager.checkForUpdates(true)
            fixture.complete(fixture.response("0.1.4"))
            showDialog = true
            wait(20)
            mouseClick(findChild(prompt, "updateNowButton"))
            compare(openStore.count, 1)
            mouseClick(findChild(prompt, "updateLaterButton"))
            verify(!manager.promptVisible)
            manager.promptRequested = true
            wait(20)
            keyClick(Qt.Key_Escape)
            verify(!manager.promptVisible)
        }

        function test_bad_responses_do_not_claim_up_to_date_data() {
            var wrongApp = fixture.response("0.1.4")
            wrongApp.data.id = "another.app"
            var unpublished = fixture.response("0.1.4")
            unpublished.data.published = false
            var incompatible = fixture.response("0.1.4")
            incompatible.data.revisions[0].architecture = "amd64"
            return [
                { tag: "offline", payload: "", http: 0 },
                { tag: "http", payload: "error", http: 500 },
                { tag: "invalidJson", payload: "{bad", http: 200 },
                { tag: "wrongApp", payload: wrongApp, http: 200 },
                { tag: "unpublished", payload: unpublished, http: 200 },
                { tag: "wrongDevice", payload: incompatible, http: 200 }
            ]
        }

        function test_bad_responses_do_not_claim_up_to_date(data) {
            manager.checkForUpdates(true)
            fixture.complete(data.payload, data.http)
            verify(!manager.checking)
            verify(!manager.promptVisible)
            verify(manager.status === "error" || manager.status === "unavailable")
            compare(fixture.preferences.lastUpdateCheckEpoch, 0)
        }

        function test_timeout_aborts_and_ignores_late_response() {
            manager.requestTimeoutMs = 20
            manager.checkForUpdates(true)
            tryCompare(manager, "checking", false, 1000)
            verify(fixture.requests[0].aborted)
            compare(manager.status, "error")
            fixture.complete(fixture.response("0.1.4"))
            verify(!manager.promptVisible)
            compare(fixture.preferences.lastUpdateCheckEpoch, 0)
        }

        function test_disable_auto_cancels_only_background_request() {
            manager.checkAutomatically()
            fixture.save({ autoCheckUpdates: false })
            verify(!manager.checking)
            verify(fixture.requests[0].aborted)
            fixture.complete(fixture.response("0.1.4"))
            verify(!manager.promptVisible)
            fixture.save({ autoCheckUpdates: true })
            fixture.clock += 3601
            manager.checkAutomatically()
            manager.checkForUpdates(true)
            fixture.save({ autoCheckUpdates: false })
            verify(manager.checking)
            fixture.complete(fixture.response("0.1.4"))
            verify(manager.promptVisible)
        }

        function test_dialog_layout_data() {
            return [ { tag: "phone", w: 360, h: 640 }, { tag: "portrait", w: 450, h: 820 }, { tag: "landscape", w: 820, h: 450 } ]
        }

        function test_dialog_layout(data) {
            fixture.width = data.w
            fixture.height = data.h
            manager.availableUpdate = { version: "0.1.4", changelog: "<b>Plain changelog</b>\n" + new Array(80).join("A long release note line.\n") }
            manager.promptRequested = true
            showDialog = true
            wait(30)
            var dialog = findChild(prompt, "updateDialog")
            var scroll = findChild(prompt, "updateDialogScroll")
            verify(dialog.x >= 0 && dialog.y >= 0)
            verify(dialog.x + dialog.width <= fixture.width)
            verify(dialog.y + dialog.height <= fixture.height)
            compare(findChild(prompt, "updateChangelog").textFormat, Text.PlainText)
            scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
            wait(20)
            var skip = findChild(prompt, "skipUpdateButton")
            var pos = skip.mapToItem(scroll, 0, 0)
            verify(pos.y >= -1 && pos.y + skip.height <= scroll.height + 1)
            mouseClick(skip)
            compare(fixture.preferences.skippedUpdateVersion, "0.1.4")
            verify(!manager.promptVisible)
        }
    }
}
