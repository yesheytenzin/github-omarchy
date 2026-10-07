import QtQuick
import Quickshell
import Quickshell.Io
import "GithubModel.js" as GithubModel

// One poller for the whole plugin.
//
// The bar widget exists once per monitor, so polling from the widget would
// shell out to `gh` once per screen and let each screen drift. This service
// is the single owner of the helper process, the cache, and the toggle state;
// the bar widget and the panel only read it.
//
// Data comes from bin/github-oma (see its docstring). The cache file paints
// the first frame, a refresh lands behind it, and a failed refresh leaves the
// last good list in place with the error beside it — never an empty panel.
Item {
  id: root

  readonly property string pluginId: "tenzin.github-oma"
  readonly property string helperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.pluginId + "/bin/github-oma"
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/github-oma/state.json"
  readonly property string cachePath: Quickshell.env("HOME") + "/.local/state/omarchy/github-oma/cache.json"

  // How often the background poll runs. Five minutes keeps a wall-clock
  // widget honest without spending search units on nothing.
  property int refreshMinutes: 5

  property string login: ""
  property var orgs: []
  property var scopes: GithubModel.emptyScopes()
  property int fetchedAt: 0

  property bool loading: false
  property string errorKind: ""
  property string errorMessage: ""

  // "mine" = personal repos only, "all" = personal + organizations. The
  // panel's toggle writes these, and they survive restarts via state.json.
  property string scope: "mine"
  property string tab: "issues"

  readonly property var counts: GithubModel.countsFor(scopes)
  readonly property var rows: GithubModel.itemsFor(scopes, scope, tab)
  readonly property int badgeCount: GithubModel.badgeCount(scopes, scope)
  readonly property int attentionCount: GithubModel.attentionCount(scopes, scope)

  // Relative timestamps are rendered from this, so "updated 2m ago" does not
  // freeze at whatever it said when the panel opened.
  property double nowMs: Date.now()
  readonly property string metaText: GithubModel.updatedMeta(scopes, scope, fetchedAt, loading, nowMs)

  function nowSeconds() { return Math.floor(Date.now() / 1000) }

  function setScope(value) {
    var next = GithubModel.clampScope(value)
    if (next === root.scope) return
    root.scope = next
    saveState()
  }

  function setTab(value) {
    var next = GithubModel.clampTab(value)
    if (next === root.tab) return
    root.tab = next
    saveState()
  }

  // Personal → both → organizations → personal. The panel's chips also set
  // a scope directly; this is the one-key path.
  function toggleScope() {
    setScope(root.scope === "mine" ? "all" : (root.scope === "all" ? "orgs" : "mine"))
  }

  function refresh() {
    if (fetchProc.running) return
    root.loading = true
    fetchProc.command = [root.helperPath, "refresh", "--json"]
    fetchProc.running = true
  }

  // Called when the panel opens: paint from the cache, and only pay for the
  // network when the cache is getting old.
  function refreshIfStale(maxAgeSeconds) {
    if (!fetchProc.running && root.nowSeconds() - root.fetchedAt > maxAgeSeconds) root.refresh()
  }

  function applyPayload(payload, fromCache) {
    if (!payload || !payload.ok) return false
    // A slow cache load must never overwrite a fresher live result.
    if (fromCache && payload.fetchedAt < root.fetchedAt) return false
    root.login = payload.login
    root.orgs = payload.orgs
    root.scopes = payload.scopes
    root.fetchedAt = payload.fetchedAt
    return true
  }

  function applyResult(raw) {
    var payload = GithubModel.parseRefresh(raw)
    if (!payload) {
      root.errorKind = "parse-failed"
      root.errorMessage = ""
      return
    }
    if (!payload.ok) {
      root.errorKind = payload.error !== "" ? payload.error : "fetch-failed"
      root.errorMessage = payload.message
      return
    }
    root.errorKind = ""
    root.errorMessage = ""
    applyPayload(payload, false)
  }

  function loadState(raw) {
    var state = GithubModel.parseState(raw)
    root.scope = state.scope
    root.tab = state.tab
  }

  function saveState() {
    stateFile.setText(GithubModel.serializeState(root.scope, root.tab))
  }

  // ---- files --------------------------------------------------------------

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onFileChanged: reload()
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyPayload(GithubModel.parseRefresh(text()), true)
    onFileChanged: reload()
  }

  // ---- fetching -----------------------------------------------------------

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyResult(text)
    }
    onExited: function(exitCode) {
      root.loading = false
      // 127 is a missing helper or a broken shebang; the helper's own typed
      // failures always print a payload first, so errorKind stays empty here
      // only when nothing at all came back.
      if (exitCode === 127 && root.errorKind === "") root.errorKind = "no-helper"
      else if (exitCode !== 0 && root.errorKind === "") root.errorKind = "fetch-failed"
    }
  }

  Timer {
    id: startupTimer
    interval: 2000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: pollTimer
    interval: root.refreshMinutes * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  Component.onCompleted: startupTimer.start()
}
