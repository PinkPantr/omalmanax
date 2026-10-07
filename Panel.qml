import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The Almanax calendar popup: a month grid over a detail card, in the same
// hero-over-detail composition the clock's calendar uses.
//
// Unlike the clock's grid this one is a picker, not a read-out — the whole
// point is to look up a day that is not today — so it carries a selection
// cursor alongside the today marker.
//
// The search field above the grid answers the other half of the question.
// Browsing finds "what is on this day"; searching finds "which day gives me
// this", so a query swaps the grid out for a list of the days that match,
// soonest first. Picking one drops you back on the calendar, on that day.
//
// BarWidget.qml owns the bar label, the dataset, and the Paris clock, and
// hands this panel the button to anchor against.
Panel {
  id: root
  moduleName: "pinkpantr.almanax"
  ipcTarget: "pinkpantr.almanax"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so everything the bar identifies a panel by has to be that
  // widget rather than this one.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Data and clock, both owned by the bar widget so the label and the
  //      panel can never disagree about what day it is.
  property var days: ({})
  property string imgDir: ""
  property date today: new Date()

  // The day being looked at. Starts on today and returns there every time
  // the panel is opened — reopening to last week's offering would be a
  // surprise, not a convenience.
  property date selected: new Date()

  // ---- Search state. `query` is the field's text; the grid and the detail
  //      card stand down while it is non-empty.
  property string query: ""
  property int cursor: 0

  // Enough rows to cover a broad query without building 366 delegates for
  // someone who typed one letter. The count line still reports the true total.
  readonly property int resultLimit: 60

  readonly property bool searching: query.trim() !== ""
  readonly property var search: Model.searchDays(days, query, today, resultLimit)
  readonly property var rows: search.rows

  readonly property int viewYear: selected.getFullYear()
  readonly property int viewMonth: selected.getMonth()

  readonly property string todayKey: Model.dateKey(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property string selectedKey: Model.dateKey(selected.getFullYear(), selected.getMonth(), selected.getDate())
  readonly property string selectedAlmanaxKey: Model.keyForDate(selected)

  readonly property var entry: days && days[selectedAlmanaxKey] ? days[selectedAlmanaxKey] : null
  readonly property bool hasData: days && Object.keys(days).length > 0
  readonly property string illuPath: illuFor(entry)

  readonly property bool viewingToday: Model.sameDay(selected, today)
  readonly property string relativeLabel: Model.relativeLabel(selected, today)

  // French labels throughout, so the week starts on Monday rather than
  // following a system locale that may not agree. Still overridable.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), 1)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey, selectedKey)

  // The bar's own French dataset sets the language for the panel, so month
  // and weekday names come from a French locale rather than the system one.
  readonly property var labelLocale: Qt.locale("fr_FR")

  // Guarded so the panel renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dimForeground: Qt.darker(contentForeground, 1.9)

  readonly property int cellWidth: Style.space(46)
  readonly property int cellHeight: Style.space(32)
  readonly property int cellSpacing: Style.space(2)

  // Uniform rows: every line elides rather than wraps, so the list stays
  // scannable and a long bonus description cannot push the next result off
  // the bottom of the panel.
  readonly property int resultRowHeight: Style.space(66)
  readonly property int resultArtSize: Style.space(42)

  function open() {
    // Always land on today, with no query left over. Browsing is a lookup,
    // not a place to be left.
    root.clearSearch()
    root.selected = new Date(root.today)
    root.controller.show()
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function goToToday() { root.selected = new Date(root.today) }

  function moveDay(delta) {
    var d = new Date(root.selected)
    d.setDate(d.getDate() + delta)
    root.selected = d
  }

  // Clamped to the target month's length so stepping off 31 January lands on
  // 28/29 February rather than skidding into March.
  function moveMonth(delta) {
    var d = new Date(root.selected)
    var day = d.getDate()
    d.setDate(1)
    d.setMonth(d.getMonth() + delta)
    d.setDate(Math.min(day, new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()))
    root.selected = d
  }

  function selectCell(cell) {
    root.selected = new Date(cell.year, cell.month, cell.day)
  }

  function illuFor(e) {
    return e && e.illu && root.imgDir !== "" ? "file://" + root.imgDir + "/" + e.illu : ""
  }

  // ---- Search -------------------------------------------------------------

  function focusSearch() { searchField.forceActiveFocus() }

  function clearSearch() {
    searchField.text = ""
    root.query = ""
  }

  // Clearing hands the keys back to the panel, so the arrows drive the grid
  // again instead of a field that no longer filters anything.
  function dismissSearch() {
    root.clearSearch()
    keyCatcher.forceActiveFocus()
  }

  function moveCursor(delta) {
    var n = root.rows.length
    if (n === 0) return
    root.cursor = Math.max(0, Math.min(root.cursor + delta, n - 1))
    ensureVisible(root.cursor)
  }

  // Landing on a result is the end of the search: the calendar comes back
  // with that day selected, which is where its full description lives.
  function activateCursor() {
    if (root.cursor < 0 || root.cursor >= root.rows.length) return
    openResult(root.rows[root.cursor])
  }

  function openResult(row) {
    root.selected = new Date(row.year, row.month, row.day)
    root.dismissSearch()
  }

  function ensureVisible(index) {
    var item = resultsRepeater.itemAt(index)
    if (!item) return
    var limit = Math.max(0, scroll.contentHeight - scroll.height)

    // The last row is followed by the "+ N autres" note, so bottoming the list
    // out rather than the row is what brings the whole tail into view.
    if (index === root.rows.length - 1) {
      scroll.contentY = limit
      return
    }

    var top = item.mapToItem(column, 0, 0).y
    if (top < scroll.contentY)
      scroll.contentY = Math.max(0, Math.min(top, limit))
    else if (top + item.height > scroll.contentY + scroll.height)
      scroll.contentY = Math.max(0, Math.min(top + item.height - scroll.height, limit))
  }

  function resultsSummary() {
    if (!root.hasData) return "Chargement…"
    var n = root.search.total
    if (n === 0) return "Aucun jour trouvé"
    return n === 1 ? "1 jour trouvé" : n + " jours trouvés"
  }

  function capitalize(text) {
    return text.charAt(0).toUpperCase() + text.slice(1)
  }

  function weekdayLabel(weekday) {
    return labelLocale.dayName(weekday, Locale.ShortFormat).replace(".", "").toUpperCase()
  }

  function monthLabel() {
    var gregorian = labelLocale.monthName(viewMonth, Locale.LongFormat)
    return Model.dofusMonth(viewMonth) + "  ·  "
      + gregorian.charAt(0).toUpperCase() + gregorian.slice(1) + " " + viewYear
  }

  // "Ven 12 Sept" — the Gregorian date is what you plan around, and the Dofus
  // month is one click away on the detail card.
  function rowDateLabel(row) {
    return capitalize(labelLocale.dayName(row.weekday, Locale.ShortFormat).replace(".", ""))
      + " " + row.day + " "
      + capitalize(labelLocale.monthName(row.month, Locale.ShortFormat).replace(".", ""))
  }

  function rowRelativeLabel(row) {
    return Model.relativeLabel(new Date(row.year, row.month, row.day), root.today)
  }

  // A fresh query is a fresh list: put the cursor on the soonest match and
  // scroll back to the top rather than leaving it deep in the previous one.
  onQueryChanged: {
    root.cursor = 0
    scroll.contentY = 0
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    // Anchored under the bar button rather than centred on the bar: the
    // widget sits on the right, and a centred popup reads as belonging to
    // whatever is in the middle of the bar instead.
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(searchRow.height + Style.space(10) + column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The field is an inline editor: while it has the keys, letters have to
      // reach it as text rather than firing the panel's shortcuts.
      blocked: searchField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (root.searching) {
          if (dy !== 0) root.moveCursor(dy)
          return
        }
        if (dx !== 0) root.moveDay(dx)
        if (dy !== 0) root.moveDay(dy * 7)
      }
      onActivateRequested: root.searching ? root.activateCursor() : root.goToToday()
      onCloseRequested: root.searching ? root.dismissSearch() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "/") root.focusSearch()
        else if (root.searching) return
        else if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "t" || t === "T") root.goToToday()
      }

      // ---- Search field. Always present, so the feature is visible rather
      //      than hidden behind a key nobody was told about, and pinned above
      //      the scroll area so sixty results cannot carry it off the top.
      Item {
        id: searchRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: searchField.implicitHeight

        TextField {
          id: searchField
          anchors.fill: parent
          foreground: root.contentForeground
          font.family: root.contentFontFamily
          leftPadding: Style.space(28)
          rightPadding: Style.space(28)
          placeholderText: "Rechercher un objet ou un bonus…"
          onTextChanged: root.query = text

          // The field owns the keys while focused, so the panel's own
          // navigation has to be re-offered here.
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              if (searchField.text !== "") root.dismissSearch()
              else root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.moveCursor(1); event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.moveCursor(-1); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.activateCursor(); event.accepted = true
            }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(9)
          text: "󰍉"
          color: searchField.activeFocus ? Color.accent : Qt.darker(root.contentForeground, 2.2)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: clearButton
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: Style.space(9)
          visible: root.searching
          text: "✕"
          color: clearMouse.containsMouse ? Color.accent : Qt.darker(root.contentForeground, 2.2)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall

          MouseArea {
            id: clearMouse
            anchors.fill: parent
            anchors.margins: -Style.space(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dismissSearch()
          }
        }
      }

      Flickable {
        id: scroll
        anchors.top: searchRow.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: column.width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: column
          width: Math.max(scroll.width, gridColumn.width)
          spacing: Style.space(10)

          // ---- Month bar: chevrons either side of the Dofus month, with
          //      the Gregorian one alongside so the grid stays readable as
          //      an ordinary calendar.
          Item {
            width: parent.width
            height: Math.max(monthText.height, Style.space(28))
            visible: !root.searching

            Text {
              id: prevChevron
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              text: "‹"
              color: prevMouse.containsMouse ? Color.accent : root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading

              MouseArea {
                id: prevMouse
                anchors.fill: parent
                anchors.margins: -Style.space(8)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.moveMonth(-1)
              }
            }

            Text {
              id: monthText
              anchors.centerIn: parent
              text: root.monthLabel()
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              id: nextChevron
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              text: "›"
              color: nextMouse.containsMouse ? Color.accent : root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading

              MouseArea {
                id: nextMouse
                anchors.fill: parent
                anchors.margins: -Style.space(8)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- Grid. Scrolling anywhere over it steps the month, matching
          //      the clock panel's wheel behavior.
          Item {
            width: parent.width
            height: gridColumn.height
            visible: !root.searching

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.NoButton
              onWheel: function(wheel) {
                if (wheel.angleDelta.y > 0) root.moveMonth(-1)
                else if (wheel.angleDelta.y < 0) root.moveMonth(1)
              }
            }

            Column {
              id: gridColumn
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: root.cellSpacing

              Row {
                id: headerRow
                spacing: root.cellSpacing

                Repeater {
                  model: root.weekdays

                  Text {
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(20)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 2.2)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      id: cell
                      required property var modelData

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius

                      // Selection is the filled state and today is the
                      // outlined one, so the two read differently when they
                      // land on the same square.
                      color: modelData.selected
                        ? Color.accent
                        : (cellMouse.containsMouse ? Qt.rgba(root.contentForeground.r,
                                                             root.contentForeground.g,
                                                             root.contentForeground.b, 0.12)
                                                   : "transparent")
                      border.width: modelData.today && !modelData.selected ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      Text {
                        anchors.centerIn: parent
                        text: cell.modelData.day
                        color: cell.modelData.selected
                          ? Color.background
                          : (cell.modelData.inMonth
                              ? (cell.modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                              : Qt.darker(root.contentForeground, 2.2))
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: cell.modelData.today || cell.modelData.selected
                      }

                      MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectCell(cell.modelData)
                      }
                    }
                  }
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.contentForeground
            opacity: 0.12
            visible: !root.searching
          }

          // ---- Detail card for the selected day.
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.searching

            Row {
              width: parent.width
              spacing: Style.space(12)

              Rectangle {
                width: Style.space(60)
                height: Style.space(60)
                radius: Style.cornerRadius
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                Image {
                  anchors.centerIn: parent
                  width: Style.space(52)
                  height: Style.space(52)
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                  asynchronous: true
                  cache: true
                  source: root.illuPath
                  visible: status === Image.Ready
                }
              }

              Column {
                width: parent.width - Style.space(72)
                spacing: Style.space(2)

                Row {
                  spacing: Style.space(8)

                  Text {
                    text: root.selected.getDate() + " " + Model.dofusMonth(root.viewMonth)
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }

                  Text {
                    anchors.baseline: parent.children[0].baseline
                    text: root.relativeLabel
                    color: root.viewingToday ? Color.accent : Qt.darker(root.contentForeground, 2.2)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  width: parent.width
                  text: root.entry ? root.entry.offrande : (root.hasData ? "—" : "Chargement…")
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                  wrapMode: Text.WordWrap
                }
              }
            }

            Text {
              width: parent.width
              text: root.entry ? root.entry.bonusTitle : ""
              visible: text !== ""
              color: Color.accent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: root.entry ? root.entry.bonus : ""
              visible: text !== ""
              color: Qt.darker(root.contentForeground, 1.35)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              lineHeight: 1.25
              wrapMode: Text.WordWrap
            }
          }

          // ---- Results, in place of the grid while a query is live.
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.searching

            Text {
              width: parent.width
              text: root.resultsSummary()
              color: Qt.darker(root.contentForeground, 2.2)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            Column {
              id: resultsList
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                id: resultsRepeater
                model: root.rows

                Rectangle {
                  id: resultRow
                  required property var modelData
                  required property int index

                  width: resultsList.width
                  height: root.resultRowHeight
                  radius: Style.cornerRadius

                  // A tint rather than a solid accent fill: the row carries
                  // four lines of text and artwork, and none of it should have
                  // to fight the highlight to stay readable.
                  color: index === root.cursor
                    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                    : (resultMouse.containsMouse ? Qt.rgba(root.contentForeground.r,
                                                           root.contentForeground.g,
                                                           root.contentForeground.b, 0.08)
                                                 : "transparent")

                  Rectangle {
                    id: resultArt
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(6)
                    width: root.resultArtSize
                    height: root.resultArtSize
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                    Image {
                      anchors.centerIn: parent
                      width: parent.width - Style.space(6)
                      height: parent.height - Style.space(6)
                      fillMode: Image.PreserveAspectFit
                      smooth: true
                      asynchronous: true
                      cache: true
                      source: root.illuFor(resultRow.modelData.entry)
                      visible: status === Image.Ready
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: resultArt.right
                    anchors.leftMargin: Style.space(10)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(1)

                    Row {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: root.rowDateLabel(resultRow.modelData)
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      Text {
                        text: "·"
                        color: Qt.darker(root.contentForeground, 2.6)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        text: root.rowRelativeLabel(resultRow.modelData)
                        color: resultRow.modelData.away === 0 ? Color.accent : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      width: parent.width
                      text: resultRow.modelData.entry.offrande
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: resultRow.modelData.entry.bonusTitle
                      color: Color.accent
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: resultRow.modelData.entry.bonus
                      color: Qt.darker(root.contentForeground, 1.9)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    id: resultMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // CHANGED 2026-10-06: was onEntered. Arrow-key scrolling
                    // slid rows under a still mouse and snapped the cursor to
                    // them. Moving the mouse is what should take the cursor.
                    onPositionChanged: root.cursor = resultRow.index
                    onClicked: root.openResult(resultRow.modelData)
                  }
                }
              }
            }

            // The list is capped, so say what is being held back rather than
            // letting the count line and the row count quietly disagree.
            Text {
              width: parent.width
              visible: root.search.capped
              text: "+ " + (root.search.total - root.rows.length) + " autres, plus loin dans l'année"
              color: Qt.darker(root.contentForeground, 2.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
