import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Three pips: filled = an active slot taken, empty = free. No task text and
// no variable width in the bar — click opens the task list for that.
//
// The timer adds no permanent "running" colour, only states that need you:
// the top pip breathes once when you press play, turns amber when you're
// back from a break but haven't restarted, and all three turn red once
// you've hit 90 minutes of focus without a break.
BarWidget {
  id: root
  moduleName: "io.github.hannoammermann.todays-top-3"

  readonly property var tasks: panelLoader.item && panelLoader.item.tasks ? panelLoader.item.tasks : []
  readonly property int taskCount: tasks.length
  readonly property var panelItem: panelLoader.item
  readonly property bool running: panelItem ? panelItem.running === true : false
  readonly property bool breakDue: panelItem ? panelItem.breakDue === true : false
  readonly property bool nudge: panelItem ? panelItem.nudge === true : false

  readonly property string tooltipText: {
    if (breakDue) return "90 min of focus — take a break"
    if (running && taskCount > 0 && panelItem) {
      var t = tasks[0]
      return t.text + " — " + Model.formatDuration((t.seconds || 0) + Model.liveSeconds(panelItem.timer, panelItem.now))
    }
    if (nudge) return "Timer paused"
    return taskCount === 0 ? "Today — no tasks yet" : "Today — " + taskCount + " of 3"
  }

  // Only a fresh press of play breathes — not a timer that was already
  // running when the shell started, or one picked up from another screen
  // a while after it began.
  // Reads the start time straight off the timer: a separate binding for it
  // may not have re-evaluated yet when this handler fires.
  onRunningChanged: {
    var timer = panelItem ? panelItem.timer : null
    if (running && timer && Date.now() - timer.startedAt < 5000) breath.restart()
  }

  // Amber isn't one of the shell's colour roles, so it's read straight from
  // the active theme's palette and follows theme switches.
  property color amber: "#e0af68"

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var match = text().match(/^\s*yellow\s*=\s*["']?(#[0-9A-Fa-f]{6})/m)
      if (match) root.amber = match[1]
    }
  }

  property real breathLevel: 1.0

  SequentialAnimation {
    id: breath
    NumberAnimation { target: root; property: "breathLevel"; to: 0.15; duration: 750; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "breathLevel"; to: 1.0; duration: 750; easing.type: Easing.InOutSine }
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: Style.space(26)
    tooltipText: root.tooltipText

    onPressed: function(b) { root.togglePanel() }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(2)

      Repeater {
        model: 3

        // The breath lives on this wrapper rather than the dot itself, so it
        // doesn't fight the dot's own fade between filled and free.
        Item {
          id: pip
          required property int index
          width: Style.space(5)
          height: Style.space(5)
          opacity: index === 0 ? root.breathLevel : 1.0

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.breakDue ? Color.urgent : (pip.index === 0 && root.nudge ? root.amber : button.foreground)
            opacity: pip.index < root.taskCount ? 1.0 : 0.3

            Behavior on opacity {
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
            Behavior on color {
              ColorAnimation { duration: 300 }
            }
          }
        }
      }
    }
  }
}
