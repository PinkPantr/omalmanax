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

  readonly property int viewYear: selected.getFullYear()
  readonly property int viewMonth: selected.getMonth()

  readonly property string todayKey: Model.dateKey(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property string selectedKey: Model.dateKey(selected.getFullYear(), selected.getMonth(), selected.getDate())
  readonly property string selectedAlmanaxKey: Model.keyForDate(selected)

  readonly property var entry: days && days[selectedAlmanaxKey] ? days[selectedAlmanaxKey] : null
  readonly property bool hasData: days && Object.keys(days).length > 0
  readonly property string illuPath: entry && entry.illu && imgDir !== ""
    ? "file://" + imgDir + "/" + entry.illu
    : ""

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

  function open() {
    // Always land on today. Browsing is a lookup, not a place to be left.
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

  function weekdayLabel(weekday) {
    return labelLocale.dayName(weekday, Locale.ShortFormat).replace(".", "").toUpperCase()
  }

  function monthLabel() {
    var gregorian = labelLocale.monthName(viewMonth, Locale.LongFormat)
    return Model.dofusMonth(viewMonth) + "  ·  "
      + gregorian.charAt(0).toUpperCase() + gregorian.slice(1) + " " + viewYear
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveDay(dx)
        if (dy !== 0) root.moveDay(dy * 7)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "t" || t === "T") root.goToToday()
      }

      Flickable {
        id: scroll
        anchors.fill: parent
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
          }

          // ---- Detail card for the selected day.
          Column {
            width: parent.width
            spacing: Style.space(8)

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
        }
      }
    }
  }
}
