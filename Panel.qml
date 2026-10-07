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
  readonly property bool withOrgs: root.service ? root.service.scope === "all" : false
  readonly property int shownIssues: counts.mine.issues + (withOrgs ? counts.orgs.issues : 0)
  readonly property int shownPrs: counts.mine.prs + (withOrgs ? counts.orgs.prs : 0)
  readonly property int orgTotal: counts.orgs.issues + counts.orgs.prs
  readonly property var notice: root.service && root.service.errorKind !== ""
    ? GithubModel.errorNotice(root.service.errorKind, root.service.errorMessage) : null
  readonly property string truncation: root.service
    ? GithubModel.truncationHint(root.service.scopes, root.service.scope, root.service.tab) : ""

  // Keyboard cursor. "tabs" and "scope" hold a chip index, "list" holds a row
  // index; Tab walks the three, j/k (and h/l) move inside the current one.
  property string section: "list"
  property int tabIndex: 0
  property int scopeIndex: 0
  property int listIndex: 0

  // State colours. Green and yellow have no shell token, so they follow the
  // theme's light/dark background rather than hard-coding one green that only
  // reads on half the themes; red and the accent are already theme tokens.
  readonly property bool lightTheme: {
    var base = Color.background
    return (0.299 * base.r + 0.587 * base.g + 0.114 * base.b) > 0.5
  }
  readonly property color successColor: root.lightTheme ? "#1a7f37" : "#3fb950"
  readonly property color warningColor: root.lightTheme ? "#9a6700" : "#d29922"

  function toneColor(tone) {
    switch (String(tone || "")) {
    case "urgent": return Color.urgent
    case "warning": return root.warningColor
    case "success": return root.successColor
    case "accent": return Color.accent
    default: return root.dim
    }
  }

  // A small tinted pill: fill and border from the tone, label in the tone.
  // Used for review state ("APPROVED", "NEEDS REVIEW") and for why a row is
  // yours ("ASSIGNED", "YOUR REVIEW").
  component ToneChip: BorderSurface {
    id: chip
    property string label: ""
    property color tone: root.dim

    implicitWidth: chipLabel.implicitWidth + Style.spacing.sm * 2
    implicitHeight: chipLabel.implicitHeight + Style.spacing.xxs * 2
    radius: Style.cornerRadius
    color: Qt.rgba(chip.tone.r, chip.tone.g, chip.tone.b, 0.15)
    borderSpec: Border.controlSpec("normal", chip.tone, chip.tone)

    Text {
      id: chipLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: chip.label
      color: chip.tone
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0.6
    }
  }

  function clamp(value, low, high) { return Math.max(low, Math.min(high, value)) }

  function syncIndexes() {
    if (!root.service) return
    root.tabIndex = root.service.tab === "prs" ? 1 : 0
    root.scopeIndex = root.service.scope === "all" ? 1 : 0
  }

  function moveCursor(dx, dy) {
    var step = dy !== 0 ? dy : dx
    if (step === 0) return
    if (root.section === "tabs") root.tabIndex = clamp(root.tabIndex + step, 0, 1)
    else if (root.section === "scope") root.scopeIndex = clamp(root.scopeIndex + step, 0, 1)
    else if (root.rows.length > 0) root.listIndex = clamp(root.listIndex + step, 0, root.rows.length - 1)
  }

  function activate() {
    if (!root.service) return
    if (root.section === "tabs") root.service.setTab(root.tabIndex === 0 ? "issues" : "prs")
    else if (root.section === "scope") root.service.setScope(root.scopeIndex === 0 ? "mine" : "all")
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
          meta: root.service ? root.service.metaText : ""
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
          options: [
            { value: "issues", label: "Issues · " + root.shownIssues },
            { value: "prs", label: "Pull requests · " + root.shownPrs }
          ]
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
          options: [
            { value: "mine", label: "Personal" },
            { value: "all", label: "+ Orgs · " + root.orgTotal }
          ]
          value: root.service ? root.service.scope : "mine"
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
            readonly property string timeText: GithubModel.relativeTime(rowSurface.item.updatedAtMs, root.service ? root.service.nowMs : Date.now())

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

              RowLayout {
                width: parent.width
                spacing: Style.spacing.sm

                Text {
                  textFormat: Text.PlainText
                  // nf-md-alert_circle_outline / nf-md-source_pull, coloured by
                  // the row's worst state so the glyph column reads as a column
                  // of states.
                  text: rowSurface.item.type === "pr" ? "󰓂" : "󰗖"
                  color: root.toneColor(GithubModel.rowTone(rowSurface.item))
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  Layout.alignment: Qt.AlignVCenter
                }

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: rowSurface.item.title
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  Layout.alignment: Qt.AlignVCenter
                }

                ToneChip {
                  readonly property var state: GithubModel.stateChip(rowSurface.item)
                  visible: state !== null
                  label: state ? state.label : ""
                  tone: state ? root.toneColor(state.tone) : root.dim
                  Layout.alignment: Qt.AlignVCenter
                }

                Text {
                  textFormat: Text.PlainText
                  visible: rowSurface.timeText !== ""
                  text: rowSurface.timeText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.alignment: Qt.AlignVCenter
                }
              }

              RowLayout {
                width: parent.width
                spacing: Style.spacing.sm

                Text {
                  textFormat: Text.PlainText
                  text: rowSurface.item.repo + "#" + rowSurface.item.number
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  Layout.maximumWidth: parent.width * 0.45
                }

                Repeater {
                  model: rowSurface.item.labels

                  Row {
                    spacing: Style.spacing.xxs
                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      width: 7
                      height: 7
                      radius: 4
                      color: GithubModel.labelRgba(modelData.color, 0.95)
                    }
                    Text {
                      textFormat: Text.PlainText
                      width: Math.min(implicitWidth, Style.space(90))
                      text: modelData.name
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }

                Item { Layout.fillWidth: true }

                ToneChip {
                  readonly property var yours: GithubModel.youChip(rowSurface.item)
                  visible: yours !== null
                  label: yours ? yours.label : ""
                  tone: yours ? root.toneColor(yours.tone) : root.dim
                }
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
              : "Nothing open. Enjoy."
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
          text: "j/k move · 1/2 issues/prs · m orgs · enter open · r refresh · tab sections · esc close"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
