import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar label for the Dofus Almanax, and the host for the calendar popup.
//
// This widget owns the three things the panel must not disagree with it
// about: the dataset, the Paris clock, and the daily sync.
//
// Left click reveals the calendar, right click opens the Almanax page on
// Dofus pour les Noobs, whose data this is.
BarWidget {
  id: root
  moduleName: "pinkpantr.almanax"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string cacheDir: home + "/.cache/almanax"

  // Resolved against this file rather than a fixed path, so the plugin runs
  // from wherever it was cloned to.
  readonly property string syncScript: String(Qt.resolvedUrl("almanax-sync")).replace(/^file:\/\//, "")

  property var days: ({})
  property string imgDir: ""

  // The Almanax rolls over at midnight in Paris, not locally — Dofus runs on
  // Ankama's clock. From Montreal that is six hours early, so for the last
  // stretch of every evening the local date is already the wrong answer.
  // `date` is asked rather than computed so DST is the system's problem.
  property date parisDate: new Date()
  readonly property string almanaxKey: Model.keyForDate(parisDate)
  readonly property var entry: days && days[almanaxKey] ? days[almanaxKey] : null

  readonly property bool showOffering: setting("showOffering", true) === true
  readonly property string glyph: "󰃭"
  readonly property string label: entry
    ? (showOffering ? entry.offrande : entry.bonusTitle)
    : ""
  readonly property string displayText: label === "" ? glyph : glyph + " " + label

  // Tracks the day the dataset was last pulled for, so the sync fires once
  // per rollover instead of on every clock tick.
  property string syncedFor: ""

  function refresh() {
    parisClock.running = true
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function syncIfNeeded() {
    var key = Model.dateKey(parisDate.getFullYear(), parisDate.getMonth(), parisDate.getDate())
    if (root.syncedFor === key) return
    root.syncedFor = key
    syncProc.running = true
  }

  function applyData(text) {
    try {
      var parsed = JSON.parse(String(text || ""))
      if (parsed && parsed.days) {
        root.days = parsed.days
        root.imgDir = String(parsed.imgDir || (root.cacheDir + "/img"))
      }
    } catch (e) {
      // A half-written or missing file just leaves the last good dataset in
      // place; the sync writes atomically, so this is the cold-start case.
    }
  }

  // ---- Calendar popup. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

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
    if ("days" in target) target.days = root.days
    if ("imgDir" in target) target.imgDir = root.imgDir
    if ("today" in target) target.today = root.parisDate
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onDaysChanged: injectPanel()
  onImgDirChanged: injectPanel()
  onParisDateChanged: {
    injectPanel()
    syncIfNeeded()
  }

  Component.onCompleted: parisClock.running = true

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: parisClock.running = true
  }

  // Paris' calendar day, as a bare YYYY-MM-DD line.
  Process {
    id: parisClock
    command: ["env", "TZ=Europe/Paris", "date", "+%Y-%m-%d"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.parseIsoDate(text, null)
        if (next && !Model.sameDay(next, root.parisDate)) root.parisDate = next
        else if (next && root.syncedFor === "") root.syncIfNeeded()
      }
    }
  }

  // CHANGED 2026-10-06: a failed sync used to be final for the day, because
  // syncedFor was already set. Offline at boot meant no data until the next
  // Paris midnight. A non-zero exit now arms this timer and tries again.
  Timer {
    id: syncRetry
    interval: 5 * 60 * 1000
    repeat: false
    onTriggered: syncProc.running = true
  }

  Process {
    id: syncProc
    command: [root.syncScript]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      dataFile.reload()
      if (exitCode === 0) syncRetry.stop()
      else syncRetry.restart()
    }
  }

  FileView {
    id: dataFile
    path: root.cacheDir + "/data.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyData(text())
    onFileChanged: reload()
  }

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

  IpcHandler {
    target: "pinkpantr.almanax"

    function refresh(): void { root.refresh() }
    function sync(): void { syncProc.running = true }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? root.glyph : root.displayText
    labelVisible: true
    hasVisualContent: true
    tooltipText: root.entry ? root.entry.bonusTitle : ""
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton && root.bar)
        root.bar.run("xdg-open https://www.dofuspourlesnoobs.com/calendrier-de-lalmanax.html")
      else root.togglePanel()
    }
  }
}
