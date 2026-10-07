import QtQuick
import qs.Commons
import qs.Ui

// 󰊤 in the bar: the GitHub mark, how many items the current scope holds, and
// the urgent color when something is assigned to you or waiting on your
// review. Click opens the panel, middle-click refreshes.
//
// This widget never fetches anything itself. Service.qml owns the poller (one
// per shell, not one per monitor) and this widget reaches it the only way a
// third-party plugin may: through the bar's scoped shell facade.
BarWidget {
  id: root
  moduleName: "tenzin.github-oma"

  readonly property var service: root.bar && root.bar.shell
    ? root.bar.shell.serviceFor(root.moduleName) : null

  readonly property int badge: root.service ? root.service.badgeCount : 0
  readonly property bool attention: root.service ? root.service.attentionCount > 0 : false

  // nf-md-github, verified in the configured Nerd Font. A bar widget with
  // empty text paints nothing at all, so the glyph is always present and the
  // count rides beside it.
  readonly property string glyph: "󰊤"
  readonly property string label: root.badge <= 0
    ? root.glyph
    : root.glyph + " " + (root.badge > 99 ? "99+" : String(root.badge))

  readonly property string tooltip: {
    if (!root.service) return "GitHub"
    if (root.service.errorKind !== "") return "GitHub · " + root.service.errorKind + " — open the panel for the fix"
    var counts = root.service.counts
    var withOrgs = root.service.scope === "all"
    var issues = counts.mine.issues + (withOrgs ? counts.orgs.issues : 0)
    var prs = counts.mine.prs + (withOrgs ? counts.orgs.prs : 0)
    return "GitHub · " + (withOrgs ? "personal + orgs" : "personal")
      + " · " + issues + " open issues · " + prs + " open pull requests"
  }

  // The shell routes `omarchy-shell shell summon|hide|toggle tenzin.github-oma`
  // through this root's open/close/opened shape (Bar.findPanelWidget), so the
  // three have to exist here and reach the loaded panel.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function refresh() {
    if (root.service) root.service.refresh()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    // A fixed slot would clip "󰊤 12"; letting the label size the slot keeps the
    // count readable and the bar host lays the neighbours out from it.
    fixedWidth: -1
    active: root.attention
    tooltipText: root.tooltip
    onPressed: function(pressedButton) {
      if (pressedButton === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
