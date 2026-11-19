import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon for the Ompom pomodoro engine (ompom.engine), with a popup to
// switch the timer on and off, pick its mode, pause or restart a run, and see
// the last seven days. This widget owns no state itself (only which mode
// "on" means): it polls the engine's IpcHandler once a second and renders
// whatever comes back, and sends control calls the same way. That keeps the
// two plugins independent: reloading one never disturbs the other's timer.
Panel {
  id: root
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int barSize: bar ? bar.barSize : 26

  property string mode: "off"
  property string phase: "focus"
  property string remainingLabel: "--:--"
  // What the engine says to show beside the icon (Cycle.barLabel()): the
  // rules for it are the engine's, so a phase added there needs nothing
  // here. An engine from before the key sends none, and gets its countdown.
  property string label: ""
  property bool paused: false
  property string goal: ""
  property int runsInSet: 0
  property int runsPerSet: 4
  // notes-helper.py recent: [{day, runs, minutes}], oldest first.
  property var days: []
  // The mode the on switch (and right-click) turns on: the last one used.
  property string lastMode: "normal"

  readonly property bool timerOn: mode !== "off"
  readonly property bool atNight: ["bedtime", "snooze", "sleep"].indexOf(phase) !== -1
  // The engine refuses a mode switch here (Cycle.setMode()); the popup
  // shows that rather than offering clicks that do nothing.
  readonly property bool modeLocked: atNight || phase === "break" || phase === "extend"

  // SVGs (icons/*.svg), tinted at runtime via MultiEffect — no font/emoji
  // involved, so there's no risk of a missing glyph collapsing to zero width
  // (that's what broke the off -> on toggle earlier) and no baked-in emoji
  // color fighting the theme. See icons/ATTRIBUTION.md for provenance; off
  // reuses the exact same icon rather than a different shape, distinguished
  // only by color.
  readonly property url iconSource: paused ? Qt.resolvedUrl("icons/pause.svg")
    : Qt.resolvedUrl("icons/omvision-mark.svg")

  implicitWidth: Math.max(Style.space(52), row.implicitWidth + Style.space(16))
  implicitHeight: barSize

  // Color.bar.text is the same token the clock/other bar text actually binds
  // to — root.foreground (bar.foreground) reads noticeably lighter than that
  // in this theme, which is what made "on" look washed out. off keeps that
  // lighter tone deliberately, so it reads as a distinct, faded state.
  readonly property color dotColor: mode === "off" ? root.foreground : Color.bar.text

  // Trusted absolute binary — never resolved through a shell or PATH.
  readonly property string omarchyShellBin: "/usr/bin/omarchy-shell"

  // argv, always — no shell string to build or escape. bar.run() is a
  // first-party facade that only accepts a string, so that one path still
  // needs quoting; it goes through bar.shellQuote() (also first-party) for
  // that, per argument, rather than hand-built concatenation.
  function runCommand(argv) {
    if (bar && typeof bar.run === "function") {
      var quote = (typeof bar.shellQuote === "function") ? bar.shellQuote : function(a) { return a }
      bar.run(argv.map(quote).join(" "))
    } else {
      Quickshell.execDetached(argv)
    }
  }

  function engine(method, arg) {
    var argv = [root.omarchyShellBin, "-q", "ompom", method]
    if (arg !== undefined) argv.push(arg)
    root.runCommand(argv)
    // Show the answer now rather than on the next second's poll.
    pollSoon.restart()
  }

  function setMode(m) {
    if (m !== "off") root.lastMode = m
    root.engine("setMode", m)
  }
  function toggleOn() { root.setMode(root.timerOn ? "off" : root.lastMode) }

  // Left opens the popup, right switches the timer on or off, middle
  // pauses.
  function handleClick(button) {
    if (button === Qt.LeftButton) root.toggle()
    else if (button === Qt.MiddleButton) root.engine("togglePause")
    else root.toggleOn()
  }

  // The bar's own per-slot pointer layer only shows a pointing-hand cursor,
  // and only routes left-clicks through its own dispatcher, for modules that
  // implement triggerPress(button) — otherwise it falls back to plain
  // fallthrough hit-testing, which delivered clicks fine but left the cursor
  // stuck at a plain arrow. Implementing it fixes the hover cursor and keeps
  // left-clicks and right-clicks going through the exact same handleClick().
  function triggerPress(button) {
    root.handleClick(button)
  }

  function applyStatus(raw) {
    var parsed
    try { parsed = JSON.parse(raw) } catch (e) { return }
    if (!parsed) return
    root.mode = parsed.mode || "off"
    root.phase = parsed.phase || "focus"
    root.remainingLabel = parsed.remainingLabel || "--:--"
    root.label = typeof parsed.label === "string" ? parsed.label : root.remainingLabel
    root.paused = !!parsed.paused
    root.goal = parsed.goal || ""
    root.runsInSet = parsed.runsInSet || 0
    root.runsPerSet = parsed.runsPerSet || 4
    if (root.mode !== "off") root.lastMode = root.mode
  }

  // The same answer again is skipped: a new array would rebuild the
  // chart's delegates every 1.5 s while the popup is open.
  property string progressRaw: ""
  function applyProgress(raw) {
    if (raw === root.progressRaw) return
    root.progressRaw = raw
    var parsed
    try { parsed = JSON.parse(raw) } catch (e) { return }
    if (Array.isArray(parsed)) root.days = parsed
  }

  function minutesLabel(m) {
    var h = Math.floor(m / 60), r = m % 60
    return h === 0 ? m + "m" : h + "h" + (r ? (r < 10 ? "0" : "") + r : "")
  }
  function total(key) {
    return root.days.reduce(function(sum, d) { return sum + (d[key] || 0) }, 0)
  }
  readonly property var today: days.length > 0 ? days[days.length - 1] : ({ runs: 0, minutes: 0 })
  readonly property int maxRuns: Math.max(1, days.reduce(function(m, d) { return Math.max(m, d.runs || 0) }, 0))

  function heroTitle() {
    if (root.atNight) return root.label === "sleep" ? "Night" : root.label
    if (!root.timerOn) return "Off"
    if (root.phase === "break") return "Break " + root.remainingLabel
    if (root.phase === "prompt") return "Run complete"
    return (root.paused ? "Paused " : "Focus ") + root.remainingLabel
  }
  function heroMeta() {
    if (!root.timerOn) return "starts only when you switch it on"
    var parts = [root.mode === "long" ? "Long focus 50/10" : "Normal 25/5"]
    if (root.mode === "normal") parts.push("run " + (root.runsInSet + 1) + " of " + root.runsPerSet)
    if (root.goal) parts.push(root.goal)
    return parts.join(" · ")
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    // The main icon: the Omvision mark normally (dimmed when off), swapped for
    // the pause glyph only while paused — not a second icon added alongside it.
    // Title size (14px): at body size (12px) the mark's gate ticks vanish, and
    // heading size (16px) looked too big beside the countdown.
    Item {
      id: icon
      anchors.verticalCenter: parent.verticalCenter
      width: Style.font.title
      height: Style.font.title

      Image {
        id: iconSvg
        anchors.fill: parent
        source: root.iconSource
        sourceSize.width: icon.width
        sourceSize.height: icon.height
        smooth: true
        visible: false
      }

      MultiEffect {
        anchors.fill: parent
        source: iconSvg
        colorization: 1.0
        colorizationColor: root.dotColor
        brightness: 1.0
      }
    }

    Text {
      id: label
      anchors.verticalCenter: parent.verticalCenter
      visible: text.length > 0
      color: root.dotColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      text: root.label
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) { root.handleClick(mouse.button) }
    onEntered: if (bar && typeof bar.showTooltip === "function" && !root.opened)
      bar.showTooltip(root, "Ompom — left: panel · right: " + (root.timerOn ? "switch off" : "switch on") + " · middle: pause")
    onExited: if (bar && typeof bar.hideTooltip === "function") bar.hideTooltip(root)
    hoverEnabled: true
  }

  // One IPC call to the engine, its answer capped. status and progress are
  // each one small JSON object (well under 1KB); anything wildly larger is
  // treated as noise rather than parsed. The cap is enforced as bytes
  // arrive, not by measuring the finished string — by the time a finished
  // string exists, an unbounded one would already have been sitting in
  // memory. Direct argv against the trusted absolute binary — no shell, no
  // PATH resolution.
  component EngineQuery: Process {
    id: query
    property string method
    signal answered(string text)
    readonly property int maxChars: 4096
    property string buffer: ""
    property bool overCap: false

    command: [root.omarchyShellBin, "ompom", query.method]

    function ask() {
      if (query.running) return
      query.running = true
      queryWatchdog.restart()
    }

    // splitMarker: "" makes SplitParser re-emit onRead per underlying read
    // call instead of buffering until a delimiter (or stream end) shows up,
    // so the cap holds against a subprocess that's still writing.
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        if (query.overCap) return
        if (query.buffer.length + data.length > query.maxChars) {
          // Killed outright: a malfunctioning omarchy-shell might not honor
          // terminate().
          query.overCap = true
          query.buffer = ""
          query.signal(9)
          return
        }
        query.buffer += data
      }
    }

    onRunningChanged: if (running) { buffer = ""; overCap = false }
    onExited: if (!overCap && buffer) query.answered(buffer)

    // The call is a local IPC round-trip of a few ms. Still running well
    // past that (hung shell, stuck IPC), it's stopped rather than left to
    // block every poll after it.
    property Timer watchdog: Timer {
      id: queryWatchdog
      interval: 4000
      onTriggered: if (query.running) query.running = false
    }
  }

  EngineQuery { id: statusQuery; method: "status"; onAnswered: function(text) { root.applyStatus(text) } }
  EngineQuery { id: progressQuery; method: "progress"; onAnswered: function(text) { root.applyProgress(text) } }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: statusQuery.ask()
  }

  // After a click: the engine has acted by the time this fires.
  Timer {
    id: pollSoon
    interval: 150
    onTriggered: statusQuery.ask()
  }

  // The engine answers progress with its last read and starts a new one,
  // so asking again shortly after opening shows today's count fresh.
  Timer {
    interval: 1500
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: progressQuery.ask()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
          title: root.heroTitle()
          meta: root.heroMeta()
          foreground: root.foreground
          fontFamily: root.fontFamily
          trailingControl: Component {
            ToggleSwitch {
              checked: root.timerOn
              interactive: !root.modeLocked
              foreground: root.foreground
              onToggled: root.toggleOn()
            }
          }
        }

        ButtonGroup {
          enabled: !root.modeLocked
          opacity: enabled ? 1 : 0.5
          focusable: false
          foreground: root.foreground
          fontFamily: root.fontFamily
          value: root.mode
          options: [
            { value: "normal", label: "Normal 25/5", tooltip: "Every fourth break is 15 min" },
            { value: "long", label: "Long 50/10" }
          ]
          onChanged: function(v) { root.setMode(v) }
        }

        Row {
          spacing: Style.spacing.md
          visible: root.timerOn && !root.atNight

          Button {
            text: root.paused ? "Resume" : "Pause"
            iconText: root.paused ? "" : ""
            bordered: true
            enabled: root.phase === "focus"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.engine("togglePause")
          }

          Button {
            text: "Restart run"
            iconText: ""
            tooltipText: "A fresh focus run from now"
            bordered: true
            enabled: root.phase === "focus"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.engine("restart")
          }
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        PanelSectionHeader {
          text: "LAST 7 DAYS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          textFormat: Text.PlainText
          text: "Today " + root.today.runs + (root.today.runs === 1 ? " pomodoro" : " pomodoros")
            + " · " + root.minutesLabel(root.today.minutes)
            + "    Week " + root.total("runs") + " · " + root.minutesLabel(root.total("minutes"))
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        // One bar per day, as tall as its pomodoros against the week's best.
        Row {
          id: chart
          width: parent.width
          height: Style.space(84)
          spacing: Style.space(6)
          readonly property real barWidth: (width - spacing * 6) / 7

          Repeater {
            model: root.days

            delegate: Column {
              required property var modelData
              required property int index
              readonly property bool isToday: index === root.days.length - 1
              width: chart.barWidth
              height: chart.height
              spacing: Style.space(2)

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: modelData.runs > 0 ? String(modelData.runs) : " "
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Item {
                width: parent.width
                height: chart.height - Style.space(36)

                Rectangle {
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: modelData.runs > 0 ? Math.max(2, parent.height * modelData.runs / root.maxRuns) : 1
                  radius: Style.cornerRadius
                  color: isToday ? Color.accent : root.foreground
                  opacity: modelData.runs > 0 ? (isToday ? 1 : 0.55) : 0.2
                }
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: Qt.formatDate(new Date(modelData.day + "T12:00:00"), "ddd")
                color: isToday ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: isToday
              }
            }
          }
        }
      }
    }
  }
}
