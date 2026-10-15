import QtQuick
import qs.Commons
import qs.Ui

// Three pips: filled = an active slot taken, empty = free. No task text and
// no variable width in the bar — click opens the task list for that.
BarWidget {
  id: root
  moduleName: "io.github.hannoammermann.todays-top-3"

  readonly property var tasks: panelLoader.item && panelLoader.item.tasks ? panelLoader.item.tasks : []
  readonly property int taskCount: tasks.length
  readonly property string tooltipText: taskCount === 0
    ? "Today — no tasks yet"
    : "Today — " + taskCount + " of 3"

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
    fixedWidth: Style.space(38)
    tooltipText: root.tooltipText

    onPressed: function(b) { root.togglePanel() }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(4)

      Repeater {
        model: 3

        Rectangle {
          required property int index
          width: Style.space(6)
          height: Style.space(6)
          radius: width / 2
          color: button.foreground
          opacity: index < root.taskCount ? 1.0 : 0.3

          Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }
        }
      }
    }
  }
}
