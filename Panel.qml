import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "GithubModel.js" as GithubModel

// The popout: your open issues and pull requests, personal repos first and
// organizations one button away.
//
// Layout only. Every count, row, and string is shaped by Service.qml through
// GithubModel.js, so this file holds the keyboard cursor, the two chip rows,
// and the list.
//
// Keys: j/k move, 1/2 switch issues/PRs, m toggles organizations, Enter opens
// the selection in the browser, g/G jump, r refreshes, Tab cycles sections,
// Esc closes.
Panel {
  id: root
  moduleName: "tenzin.github-oma"
  ipcTarget: "tenzin.github-oma"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var service: root.bar && root.bar.shell
    ? root.bar.shell.serviceFor("tenzin.github-oma") : null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var rows: root.service ? root.service.rows : []
  readonly property var counts: root.service ? root.service.counts : GithubModel.countsFor(GithubModel.emptyScopes())
  readonly property string scope: root.service ? root.service.scope : "mine"
  readonly property string tab: root.service ? root.service.tab : "issues"
  readonly property var scopeCounts: scope === "orgs" ? counts.orgs : counts.mine
  readonly property int shownIssues: scopeCounts.issues
  readonly property int shownPrs: scopeCounts.prs

  // The two scopes as one row of chips. A state file written by an older
  // build may still say "all"; the model clamps that to personal.
  readonly property var repoCounts: root.service
    ? root.service.repoCounts : { mine: 0, orgs: 0 }
  // The scope chips count what the current tab shows: items on the issue/PR
  // tabs, repositories on the repos tab.
  readonly property var scopeOptions: root.tab === "repos" ? [
    { value: "mine", label: "Personal · " + repoCounts.mine },
    { value: "orgs", label: "Orgs · " + repoCounts.orgs }
  ] : [
    { value: "mine", label: "Personal · " + (counts.mine.issues + counts.mine.prs) },
    { value: "orgs", label: "Orgs · " + (counts.orgs.issues + counts.orgs.prs) }
  ]
  readonly property int scopeCount: root.scopeOptions.length

  // The tab row: the two involvement lists, then the repos view.
  readonly property var tabOptions: [
    { value: "issues", label: "Issues · " + root.shownIssues },
    { value: "prs", label: "Pull requests · " + root.shownPrs },
    { value: "repos", label: "Repos · " + (root.service ? root.service.repoCount : 0) }
  ]
  readonly property int tabCount: root.tabOptions.length
  readonly property var notice: root.service && root.service.errorKind !== ""
    ? GithubModel.errorNotice(root.service.errorKind, root.service.errorMessage) : null
  readonly property string truncation: root.service ? root.service.truncationHint : ""

  // Keyboard cursor. "tabs" and "scope" hold a chip index, "list" holds a row
  // index; Tab walks the three, j/k (and h/l) move inside the current one.
  property string section: "list"
  property int tabIndex: 0
  property int scopeIndex: 0
  property int listIndex: 0

  function clamp(value, low, high) { return Math.max(low, Math.min(high, value)) }

  function syncIndexes() {
    if (!root.service) return
    root.tabIndex = Math.max(0, tabValues().indexOf(root.service.tab))
    root.scopeIndex = Math.max(0, root.scopeValues().indexOf(root.service.scope))
  }

  // Chip order, and the values the chips carry.
  function scopeValues() { return ["mine", "orgs"] }

  function tabValues() { return ["issues", "prs", "repos"] }

  function moveCursor(dx, dy) {
    var step = dy !== 0 ? dy : dx
    if (step === 0) return
    if (root.section === "tabs") root.tabIndex = clamp(root.tabIndex + step, 0, root.tabCount - 1)
    else if (root.section === "scope") root.scopeIndex = clamp(root.scopeIndex + step, 0, root.scopeCount - 1)
    else if (root.rows.length > 0) root.listIndex = clamp(root.listIndex + step, 0, root.rows.length - 1)
  }

  function activate() {
    if (!root.service) return
    if (root.section === "tabs") root.service.setTab(tabValues()[root.tabIndex])
    else if (root.section === "scope") root.service.setScope(scopeValues()[root.scopeIndex])
    else root.openSelection()
  }

  function openSelection() {
    if (root.rows.length === 0) return
    var row = root.rows[clamp(root.listIndex, 0, root.rows.length - 1)]
    if (row && row.url !== "") Qt.openUrlExternally(row.url)
  }

  function cycleSection(direction) {
    var order = ["tabs", "scope", "list"]
    var index = Math.max(0, order.indexOf(root.section))
    root.section = order[(index + (direction < 0 ? order.length - 1 : 1)) % order.length]
  }

  // ---- lifecycle ----------------------------------------------------------

  function open(payloadJson) {
    root.syncIndexes()
    root.controller.show()
    if (root.service) root.service.refreshIfStale(60)
  }

  function openFromHotkey() { root.open("{}") }

  function close() { root.controller.hide() }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  onOpenedChanged: if (root.opened) Qt.callLater(keepVisible)
  onRowsChanged: root.listIndex = clamp(root.listIndex, 0, Math.max(0, root.rows.length - 1))

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.cycleSection(direction) }
      onTextKey: function(text, modifiers) {
        if (!root.service) return
        if (text === "m" || text === "M") {
          root.service.toggleScope()
          root.syncIndexes()
        } else if (text === "r" || text === "R") {
          root.service.refresh()
        } else if (text === "1") {
          root.service.setTab("issues")
          root.syncIndexes()
        } else if (text === "2") {
          root.service.setTab("prs")
          root.syncIndexes()
        } else if (text === "3") {
          root.service.setTab("repos")
          root.syncIndexes()
        } else if (text === "g") {
          root.listIndex = 0
        } else if (text === "G") {
          root.listIndex = Math.max(0, root.rows.length - 1)
        } else if (text === "o" || text === "O") {
          root.openSelection()
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "GitHub"
          meta: root.service ? root.service.heroText : ""
          detail: root.service && root.service.login !== "" ? "@" + root.service.login : ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.notice !== null ? 0.55 : 1.0
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: "󰊤"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            Row {
              spacing: Style.space(2)
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: root.service && root.service.loading ? root.dim : root.foreground
                fontFamily: root.fontFamily
                onClicked: if (root.service) root.service.refresh()
              }
            }
          }
        }

        // One line per failure: what broke, then the exact fix. Rows already
        // on screen stay there, so a dead network never blanks the list.
        Text {
          width: parent.width
          visible: root.notice !== null
          textFormat: Text.PlainText
          text: root.notice ? root.notice.title + " — " + root.notice.hint : ""
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        ButtonGroup {
          options: root.tabOptions
          value: root.service ? root.service.tab : "issues"
          foreground: root.foreground
          fontFamily: root.fontFamily
          focusable: false
          cursorIndex: root.section === "tabs" ? root.tabIndex : -1
          onChanged: function(value) {
            if (!root.service) return
            root.service.setTab(value)
            root.syncIndexes()
          }
          onHovered: function(index, isHovered) {
            if (!isHovered) return
            root.section = "tabs"
            root.tabIndex = index
          }
        }

        ButtonGroup {
          options: root.scopeOptions
          value: root.scope
          foreground: root.foreground
          fontFamily: root.fontFamily
          focusable: false
          cursorIndex: root.section === "scope" ? root.scopeIndex : -1
          onChanged: function(value) {
            if (!root.service) return
            root.service.setScope(value)
            root.syncIndexes()
          }
          onHovered: function(index, isHovered) {
            if (!isHovered) return
            root.section = "scope"
            root.scopeIndex = index
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ListView (not a Column) so j/k keep the cursor row visible and the
        // view re-clamps itself when the tab changes the list length.
        ListView {
          id: issueList
          width: parent.width
          height: Math.min(contentHeight, Style.space(400))
          spacing: Style.space(2)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.rows
          currentIndex: root.listIndex
          onCurrentIndexChanged: if (currentIndex >= 0) Qt.callLater(keepVisible)
          function keepVisible() {
            if (currentIndex >= 0 && count > 0) positionViewAtIndex(currentIndex, ListView.Contain)
          }

          ScrollBar.vertical: ScrollBar { policy: issueList.contentHeight > issueList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

          delegate: CursorSurface {
            id: rowSurface
            required property var modelData
            required property int index

            readonly property var item: rowSurface.modelData
            readonly property bool isRepo: rowSurface.item.kind === "repo"

            width: issueList.width
            height: rowColumn.implicitHeight + Style.spacing.sm * 2
            hasCursor: root.section === "list" && rowSurface.index === root.listIndex

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: {
                if (!containsMouse) return
                root.section = "list"
                root.listIndex = rowSurface.index
              }
              onClicked: {
                root.section = "list"
                root.listIndex = rowSurface.index
                root.openSelection()
              }
            }

            Column {
              id: rowColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.spacing.rowPaddingX
              anchors.rightMargin: Style.spacing.rowPaddingX
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs

              // An issue or pull request: its title, then the repo it is in.
              Text {
                width: parent.width
                visible: !rowSurface.isRepo
                textFormat: Text.PlainText
                text: rowSurface.item.title
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: !rowSurface.isRepo
                textFormat: Text.PlainText
                text: rowSurface.item.repo
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              // A repo: the name alone.
              Text {
                width: parent.width
                visible: rowSurface.isRepo
                textFormat: Text.PlainText
                text: rowSurface.item.nameWithOwner
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
            }
          }

          Text {
            anchors.centerIn: parent
            width: issueList.width - Style.space(40)
            visible: issueList.count === 0
            textFormat: Text.PlainText
            text: root.notice !== null ? "Nothing to show"
              : root.service && root.service.loading ? "Loading…"
              : root.tab === "repos" ? "No repositories." : "Nothing open. Enjoy."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }

        Text {
          width: parent.width
          visible: root.truncation !== ""
          textFormat: Text.PlainText
          text: root.truncation
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "j/k move · 1/2/3 tabs · m scope · enter open · r refresh · tab sections · esc close"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
