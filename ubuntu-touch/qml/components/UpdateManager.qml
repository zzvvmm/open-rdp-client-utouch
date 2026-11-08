import QtQuick 2.12

QtObject {
    id: root
    objectName: "updateManager"

    property bool ready: false
    property bool automaticEnabled: true
    property string skippedVersion: ""
    property real lastCheckedAt: 0
    property string installedVersion: ""
    property string architecture: ""
    property string framework: ""
    property bool appActive: true
    property bool canPrompt: true
    property bool checking: false
    property string status: "idle"
    property var availableUpdate: null
    property bool promptRequested: false
    readonly property bool promptVisible: promptRequested && canPrompt && appActive
    readonly property string storeUri: "openstore://rdp-client-ut.zzvvmm"

    // Injectable transport and clock keep the update policy testable offline.
    property var requestFactory: function() { return new XMLHttpRequest() }
    property var now: function() { return Math.floor(Date.now() / 1000) }
    property int automaticDelayMs: 1000
    property int requestTimeoutMs: 15000
    property var activeRequest: null
    property bool manualRequest: false
    property bool manualPrompt: false
    property real lastAttemptAt: 0

    signal savePreferences(var patch)
    signal openStoreRequested(string uri)

    property Timer automaticTimer: Timer {
        interval: root.automaticDelayMs
        onTriggered: root.checkAutomatically()
    }
    property Timer requestTimer: Timer {
        interval: root.requestTimeoutMs
        onTriggered: root.failRequest(root.activeRequest)
    }

    function scheduleAutomaticCheck() {
        if (ready && automaticEnabled && appActive && canPrompt)
            automaticTimer.restart()
    }

    onReadyChanged: scheduleAutomaticCheck()
    onAppActiveChanged: scheduleAutomaticCheck()
    onCanPromptChanged: scheduleAutomaticCheck()
    onAutomaticEnabledChanged: {
        if (automaticEnabled) scheduleAutomaticCheck()
        else {
            automaticTimer.stop()
            if (!manualPrompt) promptRequested = false
            if (checking && !manualRequest) cancelRequest()
        }
    }
    Component.onCompleted: scheduleAutomaticCheck()
    Component.onDestruction: cancelRequest()

    function compareVersions(left, right) {
        var pattern = /^\d+(\.\d+)*$/
        if (typeof left !== "string" || typeof right !== "string"
                || !pattern.test(left) || !pattern.test(right)) return null
        var a = left.split(".")
        var b = right.split(".")
        for (var part = 0; part < a.length + b.length; ++part) {
            var value = part < a.length ? a[part] : b[part - a.length]
            if (Number(value) > 2147483647) return null
        }
        for (var i = 0; i < Math.max(a.length, b.length); ++i) {
            var x = i < a.length ? Number(a[i]) : 0
            var y = i < b.length ? Number(b[i]) : 0
            if (x !== y) return x > y ? 1 : -1
        }
        return 0
    }

    function selectRelease(payload) {
        if (!payload || payload.success !== true || !payload.data
                || payload.data.id !== "rdp-client-ut.zzvvmm"
                || payload.data.published !== true
                || !Array.isArray(payload.data.revisions)) return null
        var data = payload.data
        var selected = null
        for (var i = 0; i < data.revisions.length; ++i) {
            var revision = data.revisions[i]
            if (!revision || revision.channel !== "focal"
                    || (revision.architecture !== architecture && revision.architecture !== "all")
                    || revision.framework !== framework
                    || compareVersions(revision.version, installedVersion) === null) continue
            if (!selected || compareVersions(revision.version, selected.version) > 0)
                selected = revision
        }
        if (!selected) return null
        var changelog = typeof selected.changelog === "string" ? selected.changelog : ""
        var logs = Array.isArray(data.version_changelogs) ? data.version_changelogs : []
        for (var j = 0; j < logs.length; ++j) {
            if (logs[j] && logs[j].version === selected.version && typeof logs[j].changelog === "string") {
                changelog = logs[j].changelog
                break
            }
        }
        if (!changelog && data.version === selected.version && typeof data.changelog === "string")
            changelog = data.changelog
        return { version: selected.version, changelog: changelog }
    }

    function checkAutomatically() {
        if (!ready || !automaticEnabled || !appActive || !canPrompt || checking) return false
        var elapsed = now() - lastCheckedAt
        if (lastCheckedAt > 0 && elapsed >= 0 && elapsed < 86400) return false
        var sinceAttempt = now() - lastAttemptAt
        if (lastAttemptAt > 0 && sinceAttempt >= 0 && sinceAttempt < 3600) return false
        return checkForUpdates(false)
    }

    function checkForUpdates(manual) {
        if (!ready || !appActive) return false
        if (checking) {
            // An explicit check takes precedence over an automatic request in flight.
            if (manual) manualRequest = true
            return false
        }
        if (compareVersions(installedVersion, installedVersion) === null || !architecture || !framework) {
            status = "unavailable"
            return false
        }
        manualRequest = !!manual
        checking = true
        status = "checking"
        lastAttemptAt = now()
        var request = null
        try {
            request = requestFactory()
            activeRequest = request
            request.onreadystatechange = function() {
                if (root.activeRequest !== request || request.readyState !== 4) return
                if (request.status < 200 || request.status >= 300) {
                    root.failRequest(request)
                    return
                }
                var release = null
                try { release = root.selectRelease(JSON.parse(request.responseText)) }
                catch (error) { root.failRequest(request); return }
                if (!release) { root.failRequest(request, "unavailable"); return }
                var explicit = root.manualRequest
                root.finishRequest()
                root.savePreferences({ lastUpdateCheckEpoch: root.now() })
                if (root.compareVersions(release.version, root.installedVersion) <= 0) {
                    root.availableUpdate = null
                    root.promptRequested = false
                    root.status = "upToDate"
                    return
                }
                root.availableUpdate = release
                root.status = "available"
                root.manualPrompt = explicit
                root.promptRequested = explicit || root.compareVersions(release.version, root.skippedVersion) !== 0
            }
            request.open("GET", "https://open-store.io/api/v3/apps/rdp-client-ut.zzvvmm", true)
            request.setRequestHeader("Accept", "application/json")
            requestTimer.restart()
            request.send()
        } catch (error) {
            failRequest(request)
        }
        return true
    }

    function finishRequest() {
        requestTimer.stop()
        activeRequest = null
        checking = false
    }

    function cancelRequest() {
        var request = activeRequest
        finishRequest()
        if (request) request.abort()
        if (status === "checking") status = "idle"
    }

    function failRequest(request, reason) {
        if (request !== activeRequest) return
        cancelRequest()
        status = reason || "error"
    }

    function updateLater() {
        promptRequested = false
    }

    function skipVersion() {
        if (!availableUpdate) return
        savePreferences({ skippedUpdateVersion: availableUpdate.version })
        promptRequested = false
    }

    function updateNow() {
        if (!availableUpdate) return
        openStoreRequested(storeUri)
    }

    function storeOpened(success) {
        if (success) {
            promptRequested = false
            status = "openingStore"
        } else {
            // Keep the dialog open so the user can retry or choose Later.
            status = "openFailed"
        }
    }
}
