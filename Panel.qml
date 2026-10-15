import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.hannoammermann.todays-top-3"
  ipcTarget: "io.github.hannoammermann.todays-top-3"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var tasks: []
  property var done: []
  readonly property bool atCap: tasks.length >= 3

  // Id of the task currently being edited in place, or "" for none. Only
  // one row edits at a time; switching to a different row while one is open
  // abandons the unsaved edit rather than auto-committing it.
  property string editingTaskId: ""

  // Collapsed by default — the done list costs nothing visually until you
  // actually click to see it. Persists for the shell session (not reset on
  // close/reopen); there's no need to force it shut again once you've
  // chosen to look.
  property bool doneExpanded: false

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function addTask() {
    if (root.atCap) return
    var next = Model.addTask(root.tasks, input.text)
    if (next === root.tasks) return
    root.tasks = next
    input.text = ""
    persist()
  }

  // "All clear" types itself out, but only at the moment the last active
  // task is cleared — not every time the panel happens to load into an
  // already-empty state (e.g. reopening later the same day).
  property bool allClearRevealing: false
  property int allClearRevealIndex: 0
  readonly property string allClearFullText: "All clear ✓"

  function startAllClearReveal() {
    root.allClearRevealing = true
    root.allClearRevealIndex = 0
    allClearRevealTimer.restart()
  }

  Timer {
    id: allClearRevealTimer
    interval: 40
    repeat: true
    onTriggered: {
      if (root.allClearRevealIndex < root.allClearFullText.length) {
        root.allClearRevealIndex = root.allClearRevealIndex + 1
      } else {
        allClearRevealTimer.stop()
        root.allClearRevealing = false
      }
    }
  }

  function completeTask(id) {
    var hadActiveTasks = root.tasks.length > 0
    var next = Model.completeTask(root.tasks, root.done, id)
    root.tasks = next.tasks
    root.done = next.done
    persist()
    if (hadActiveTasks && root.tasks.length === 0) root.startAllClearReveal()
  }

  function clearDone(id) {
    root.done = Model.clearDone(root.done, id)
    persist()
  }

  function restoreTask(id) {
    var next = Model.restoreTask(root.tasks, root.done, id)
    root.tasks = next.tasks
    root.done = next.done
    persist()
    // Once you've acted on the done list, it's served its purpose for this
    // visit — fold it back away after a beat rather than leaving it expanded
    // indefinitely.
    doneCollapseTimer.restart()
  }

  Timer {
    id: doneCollapseTimer
    interval: 2200
    repeat: false
    onTriggered: root.doneExpanded = false
  }

  function promoteTask(id) {
    root.tasks = Model.promoteTask(root.tasks, id)
    persist()
  }

  function startEditTask(id) {
    root.editingTaskId = id
  }

  function cancelEditTask() {
    root.editingTaskId = ""
  }

  function commitEditTask(id, text) {
    root.tasks = Model.updateTaskText(root.tasks, id, text)
    root.editingTaskId = ""
    persist()
  }

  // Cheap safety net: a completed task is only ever removed from the done
  // log when read/written (parseState, this check), so a shell that runs for
  // days without this would keep stale entries past midnight. The scan
  // itself is never more than 3 items, so this is a filter, not a background job.
  function pruneExpiredDone() {
    var pruned = Model.pruneDone(root.done)
    if (pruned.length !== root.done.length) {
      root.done = pruned
      persist()
    }
  }

  // Closing mid-edit abandoned the draft anyway (editField's binding isn't
  // committed), so reopening should show the clean read-only row, not a
  // stale edit field for a task that no longer matches what's on screen.
  //
  // The double Qt.callLater on focus is deliberate: KeyboardPanel primes its
  // own focusTarget (keyCatcher) via a single deferred call on this same
  // open transition. Qt.callLater runs callbacks in the order they were
  // scheduled, so nesting ours inside a second deferred call guarantees it
  // lands after that one and actually wins, rather than racing it.
  onOpenedChanged: {
    if (root.opened) {
      root.pruneExpiredDone()
      Qt.callLater(function() {
        Qt.callLater(function() {
          if (root.opened && !root.atCap) input.forceActiveFocus()
        })
      })
    } else {
      root.editingTaskId = ""
    }
  }

  function persist() {
    saveTimer.restart()
  }

  // State lives outside this plugin's own folder, under the same
  // ~/.local/state/omarchy/ tree the first-party plugins use for their own
  // local state (see notifications.json, settings/weather.json). Keeping it
  // out of the plugin directory means it's never at risk of being swept up
  // if this folder is ever a git checkout that gets pushed somewhere.
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/"
  readonly property string statePath: stateDir + "todays-top-3.json"

  Process {
    id: ensureDirProc
    command: ["bash", "-c", "mkdir -p \"$1\" && chmod 700 \"$1\"", "--", root.stateDir]
  }

  // Belt-and-suspenders: the containing directory is already 700, so
  // nothing can reach this file without going through it first. This just
  // keeps the file's own mode tight too, re-applied after every write since
  // atomic writes replace the file (and its mode) each time.
  Process {
    id: chmodFileProc
    command: ["chmod", "600", root.statePath]
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var state = Model.parseState(text())
      root.tasks = state.tasks
      root.done = state.done
    }
    onLoadFailed: {
      root.tasks = []
      root.done = []
    }
  }

  Timer {
    id: saveTimer
    interval: 200
    repeat: false
    onTriggered: {
      stateFile.setText(Model.serializeState(root.tasks, root.done))
      chmodFileProc.running = true
    }
  }

  // Lets a done entry clear out shortly after midnight even if the panel is
  // never reopened, without a tight poll — half-hourly is plenty for a
  // once-a-day boundary.
  Timer {
    interval: 30 * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.pruneExpiredDone()
  }

  Component.onCompleted: {
    ensureDirProc.running = true
    Qt.callLater(function() { stateFile.reload() })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: input.activeFocus || root.editingTaskId !== ""
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Text {
          textFormat: Text.PlainText
          text: "TODAY — TOP 3"
          color: Qt.darker(root.bar.foreground, 1.2)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          font.letterSpacing: 1
        }

        Repeater {
          model: root.tasks

          Item {
            id: taskRow
            required property var modelData
            required property int index
            width: column.width
            height: Math.max(doneBtn.height, promoteBtn.height, taskLabel.implicitHeight, Style.space(22))

            // Brief terminal-style "[ OK ]" tag before the row actually
            // leaves the active list.
            FlashTag {
              id: completeFlash
              frames: ["[    ]", "[ .  ]", "[ .. ]", "[ OK ]"]
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.body
              idleColor: root.bar.foreground
              onFinished: root.completeTask(taskRow.modelData.id)
            }

            PanelActionButton {
              id: doneBtn
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "✓"
              tooltipText: "Done"
              foreground: root.bar.foreground
              onClicked: {
                if (completeFlash.active) return
                completeFlash.start()
              }
            }

            Text {
              id: taskLabel
              textFormat: Text.PlainText
              visible: taskRow.modelData.id !== root.editingTaskId
              anchors.left: doneBtn.right
              anchors.leftMargin: Style.space(8)
              anchors.right: promoteBtn.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: taskRow.modelData.text
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startEditTask(taskRow.modelData.id)
              }
            }

            TextField {
              id: editField
              visible: taskRow.modelData.id === root.editingTaskId
              anchors.left: doneBtn.right
              anchors.leftMargin: Style.space(8)
              anchors.right: promoteBtn.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: taskRow.modelData.text
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle

              onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
              onAccepted: root.commitEditTask(taskRow.modelData.id, editField.text)
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelEditTask()
                  event.accepted = true
                }
              }
            }

            PanelActionButton {
              id: promoteBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "★"
              tooltipText: "Move to top"
              enabled: taskRow.index > 0
              foreground: root.bar.foreground
              onClicked: root.promoteTask(taskRow.modelData.id)
            }
          }
        }

        // Empty reads differently depending on why it's empty: having
        // finished something today earns "All clear", not the same neutral
        // placeholder as a day that hasn't started yet.
        Text {
          textFormat: Text.PlainText
          visible: root.tasks.length === 0
          text: root.allClearRevealing
            ? root.allClearFullText.slice(0, root.allClearRevealIndex)
            : (root.done.length > 0 ? root.allClearFullText : "Nothing yet — add up to 3.")
          color: root.done.length > 0 ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: root.done.length === 0
          font.bold: root.done.length > 0
        }

        // The divider and the done block below it are one visual unit, so
        // they get a tighter gap between them than the standard spacing
        // used elsewhere — less dead space for a line whose only job is
        // separating "your tasks" from everything secondary below it.
        Column {
          width: column.width
          spacing: Style.space(6)
          visible: root.tasks.length > 0 || root.done.length > 0

          Rectangle {
            width: column.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
          }

          // Collapsed by default: a one-line "[+] recently done (n)" costs
          // almost nothing visually. Only the click to expand instantiates
          // the actual rows (model is [] while collapsed), so the list
          // isn't sitting there off-screen either.
          Column {
            width: column.width
            spacing: Style.space(4)
            opacity: 0.6
            visible: root.done.length > 0

            Text {
              textFormat: Text.PlainText
              visible: !root.doneExpanded
              width: column.width
              text: "[+] recently done (" + root.done.length + ")"
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.doneExpanded = true
              }
            }

            Text {
              visible: root.doneExpanded
              width: column.width
              textFormat: Text.PlainText
              text: "[-] recently done"
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.doneExpanded = false
              }
            }

            Repeater {
              model: root.doneExpanded ? root.done : []

              Item {
                id: doneRow
                required property var modelData
                width: column.width
                height: Style.space(17)

                // Mirrors the completion tag: restoring a task is the
                // inverse of finishing one, so it gets the same brief
                // terminal-tag treatment rather than snapping back silently.
                FlashTag {
                  id: restoreFlash
                  frames: ["[    ]", "[ <  ]", "[ << ]"]
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.bodySmall
                  idleColor: root.bar.foreground
                  onFinished: root.restoreTask(doneRow.modelData.id)
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.right: restoreBtn.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: doneRow.modelData.text
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.strikeout: true
                  color: Qt.darker(root.bar.foreground, 1.6)
                  elide: Text.ElideRight
                }

                PanelActionButton {
                  id: restoreBtn
                  anchors.right: clearDoneBtn.left
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.space(18)
                  iconText: "↺"
                  tooltipText: root.atCap ? "No free slot" : "Restore to active"
                  enabled: !root.atCap
                  foreground: root.bar.foreground
                  onClicked: {
                    if (restoreFlash.active || root.atCap) return
                    restoreFlash.start()
                  }
                }

                PanelActionButton {
                  id: clearDoneBtn
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.space(18)
                  iconText: "✕"
                  tooltipText: "Clear"
                  foreground: root.bar.foreground
                  onClicked: root.clearDone(doneRow.modelData.id)
                }
              }
            }
          }
        }

        TextField {
          id: input
          property bool cursorOn: true
          width: column.width
          enabled: !root.atCap
          placeholderText: root.atCap ? "Finish or remove one first" : "Add a task" + (cursorOn ? "_" : " ")
          foreground: root.bar.foreground
          font.family: root.bar.fontFamily

          onAccepted: root.addTask()

          // Idle terminal-prompt flavor — only runs while there's actually
          // a blinking placeholder to animate, not once you're typing.
          Timer {
            interval: 500
            repeat: true
            running: input.text === "" && !root.atCap
            onTriggered: input.cursorOn = !input.cursorOn
          }
        }
      }
    }
  }
}
