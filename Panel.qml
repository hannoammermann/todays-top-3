import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
  property var parked: []
  readonly property bool atCap: tasks.length >= 3
  readonly property bool parkFull: parked.length >= Model.PARK_CAP

  // The running session (always the top task) or null, the current focus
  // streak, and per-day totals for the stats line. See Model.js "Timer".
  property var timer: null
  property var streak: Model.emptyFocus()
  property var days: ({})
  readonly property bool running: timer !== null

  // Wall clock for everything time-based, advanced by the heartbeat. Ten
  // seconds is plenty: the panel only ever shows whole minutes.
  property real now: Date.now()

  readonly property int todaySeconds: Model.periodSeconds(days, timer, "today", now)
  readonly property bool breakDue: Model.focusSeconds(timer, streak, now) >= Model.FOCUS_LIMIT_SECONDS

  // "You're back, but the timer is paused": a real break already happened,
  // you've been at the keyboard for a couple of minutes since, and you'd
  // timed something earlier today. Opening the panel counts as having seen
  // it, so it never nags through an afternoon of deliberate other work.
  property real activeSince: 0
  readonly property bool nudge: !running
    && tasks.length > 0
    && todaySeconds > 0
    && Model.breakTaken(timer, streak, now)
    && !streak.nudgeDismissed
    && activeSince > 0
    && now - activeSince >= Model.NUDGE_ACTIVE_MS

  property int statsPeriodIndex: 0
  readonly property string statsPeriod: Model.PERIODS[statsPeriodIndex]

  // Id of the task currently being edited in place, or "" for none. Only
  // one row edits at a time; switching to a different row while one is open
  // abandons the unsaved edit rather than auto-committing it.
  property string editingTaskId: ""

  // Collapsed by default — the done list costs nothing visually until you
  // actually click to see it. Persists for the shell session (not reset on
  // close/reopen); there's no need to force it shut again once you've
  // chosen to look.
  property bool doneExpanded: false
  property bool parkedExpanded: false

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

  function toggleTimer() {
    if (root.running) root.stopTimer(Date.now())
    else root.startTimer()
  }

  function startTimer() {
    var n = Date.now()
    var next = Model.startSession(root.tasks, root.timer, root.streak, n)
    if (!next) return
    root.now = n
    root.timer = next.timer
    root.streak = next.focus
    persist()
  }

  // `end` is the last moment known to be work: now for a pause or lock, the
  // last heartbeat after sleep or a crash.
  function stopTimer(end) {
    if (!root.timer) return
    var next = Model.stopSession(root.tasks, root.days, root.timer, root.streak, end)
    root.now = Date.now()
    root.tasks = next.tasks
    root.days = next.days
    root.timer = null
    root.streak = next.focus
    persist()
    persistHistory()
  }

  function completeTask(id) {
    if (root.timer && root.timer.taskId === id) root.stopTimer(Date.now())
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

  // Switching tasks is deliberate: the old one pauses and the new top task
  // waits for its own play press, so reordering never silently logs time.
  // Parking the running task pauses it, same as moving it off the top.
  function parkTask(id) {
    if (root.parkFull) return
    if (root.timer && root.timer.taskId === id) root.stopTimer(Date.now())
    var next = Model.parkTask(root.tasks, root.parked, id)
    root.tasks = next.tasks
    root.parked = next.parked
    persist()
  }

  function unparkTask(id) {
    var next = Model.unparkTask(root.tasks, root.parked, id)
    root.tasks = next.tasks
    root.parked = next.parked
    persist()
    parkedCollapseTimer.restart()
  }

  function clearParked(id) {
    root.parked = Model.clearParked(root.parked, id)
    persist()
  }

  Timer {
    id: parkedCollapseTimer
    interval: 2200
    repeat: false
    onTriggered: root.parkedExpanded = false
  }

  function promoteTask(id) {
    if (root.timer) root.stopTimer(Date.now())
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
      root.now = Date.now()
      root.statsPeriodIndex = 0
      if (root.nudge) {
        root.streak = Object.assign({}, root.streak, { nudgeDismissed: true })
        persist()
      }
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

  readonly property string historyPath: stateDir + "todays-top-3-history.json"

  // Watched because the bar exists once per screen: pressing play on one
  // monitor has to show up on the others. Our own writes come straight back
  // as change events, so those are recognized by content and skipped, and
  // otherwise only the parts that actually changed are reassigned — so a
  // heartbeat write from another screen never rebuilds the task rows (and
  // throws away an edit in progress).
  property string lastStateText: ""
  property string lastHistoryText: ""

  function assignIfChanged(name, value) {
    if (JSON.stringify(root[name]) !== JSON.stringify(value)) root[name] = value
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var raw = text()
      if (raw === root.lastStateText) return
      root.lastStateText = raw
      var state = Model.parseState(raw)
      root.assignIfChanged("tasks", state.tasks)
      root.assignIfChanged("done", state.done)
      root.assignIfChanged("parked", state.parked)
      root.assignIfChanged("timer", state.timer)
      root.assignIfChanged("streak", state.focus)
    }
    onLoadFailed: {
      root.tasks = []
      root.done = []
    }
  }

  FileView {
    id: historyFile
    path: root.historyPath
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var raw = text()
      if (raw === root.lastHistoryText) return
      root.lastHistoryText = raw
      root.assignIfChanged("days", Model.parseHistory(raw))
    }
  }

  Timer {
    id: saveTimer
    interval: 200
    repeat: false
    onTriggered: {
      root.lastStateText = Model.serializeState(root.tasks, root.done, root.parked, root.timer, root.streak)
      stateFile.setText(root.lastStateText)
      chmodFileProc.running = true
    }
  }

  function persistHistory() {
    historySaveTimer.restart()
  }

  Timer {
    id: historySaveTimer
    interval: 200
    repeat: false
    onTriggered: {
      root.lastHistoryText = Model.serializeHistory(root.days)
      historyFile.setText(root.lastHistoryText)
      chmodHistoryProc.running = true
    }
  }

  Process {
    id: chmodHistoryProc
    command: ["chmod", "600", root.historyPath]
  }

  // ---- Heartbeat -----------------------------------------------------------
  //
  // Every 10s while a session runs, the leading copy (see Model.claimLeader)
  // records "still awake at <time>". A gap between heartbeats means the
  // machine slept or the shell was down, and the session is ended at the
  // last heartbeat — never counting the time asleep, and never cutting more
  // than a few seconds of real work. The heartbeat is saved to disk once a
  // minute so a crash or shell restart is handled the same way.
  readonly property string instanceId: Model.generateId()
  property bool wasLeader: false
  property real lastSavedBeat: 0

  function heartbeat() {
    var n = Date.now()
    root.now = n
    if (!Model.claimLeader(root.instanceId, n)) {
      root.wasLeader = false
      return
    }
    // A copy that just took over only knows the heartbeat from disk, which
    // can be up to a minute old, so it allows a wider gap once.
    var gapLimit = root.wasLeader ? 40000 : 90000
    root.wasLeader = true
    if (!root.timer) return

    if (n - root.timer.lastBeat > gapLimit) {
      root.stopTimer(root.timer.lastBeat)
      return
    }

    root.timer = Object.assign({}, root.timer, { lastBeat: n })
    if (n - root.lastSavedBeat >= 60000) {
      root.lastSavedBeat = n
      persist()
    }
    if (!lockCheckProc.running) lockCheckProc.running = true

    if (root.breakDue && !root.streak.alerted) {
      root.streak = Object.assign({}, root.streak, { alerted: true })
      persist()
      breakNotifyProc.running = true
    }
  }

  Timer {
    interval: 10000
    repeat: true
    running: true
    onTriggered: root.heartbeat()
  }

  // Locking the screen pauses right away. The lock screen belongs to the
  // shell itself, so it's asked directly rather than guessed from idle time
  // (sitting still reading for five minutes is still work).
  Process {
    id: lockCheckProc
    command: ["omarchy-shell", "-q", "lock", "isLocked"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.trim() === "true" && root.timer) root.stopTimer(Date.now())
      }
    }
  }

  Process {
    id: breakNotifyProc
    command: ["notify-send", "-a", "Today's Top 3", "90 minutes of focus", "Time for a break — 5 minutes away resets it."]
  }

  // Only used for the "back but paused" hint: how long you've been at the
  // keyboard again. Ignores inhibitors so a playing video doesn't count.
  IdleMonitor {
    id: idleMonitor
    timeout: 60
    respectInhibitors: false
    onIsIdleChanged: root.activeSince = isIdle ? 0 : Date.now()
  }

  Component.onDestruction: Model.releaseLeader(root.instanceId)

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
    if (!idleMonitor.isIdle) root.activeSince = Date.now()
    Qt.callLater(function() {
      stateFile.reload()
      historyFile.reload()
    })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(326))
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
          text: "TODAY'S TOP 3"
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
            height: Math.max(doneBtn.height, promoteBtn.height, textColumn.implicitHeight, Style.space(22))

            readonly property bool isRunning: root.timer !== null && root.timer.taskId === modelData.id

            HoverHandler { id: rowHover }
            readonly property int totalSeconds: (modelData.seconds || 0) + (isRunning ? Model.liveSeconds(root.timer, root.now) : 0)

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

            Column {
              id: textColumn
              anchors.left: doneBtn.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parkBtn.left
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                id: taskLabel
                textFormat: Text.PlainText
                visible: taskRow.modelData.id !== root.editingTaskId
                width: textColumn.width
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

              // Wraps instead of horizontally scrolling. A single-line field
              // showing a long selected value tends to land scrolled to the
              // end, hiding the start — wrapping sidesteps that entirely by
              // keeping the whole task visible at once, matching how the
              // read-only label above already wraps.
              TextArea {
                id: editField
                visible: taskRow.modelData.id === root.editingTaskId
                width: textColumn.width
                text: taskRow.modelData.text
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                wrapMode: TextEdit.WordWrap
                padding: 0
                background: Item {}

                onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.cancelEditTask()
                    event.accepted = true
                  } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                    root.commitEditTask(taskRow.modelData.id, editField.text)
                    event.accepted = true
                  }
                }
              }

              // Total across every day this task has been on the list. No
              // line at all until it's been timed, so an untimed list looks
              // exactly as it always did.
              Text {
                textFormat: Text.PlainText
                visible: taskRow.totalSeconds > 0 && taskRow.modelData.id !== root.editingTaskId
                text: Model.formatDuration(taskRow.totalSeconds)
                color: taskRow.isRunning ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // Only shown while the row is hovered, but its space is always
            // reserved so the task text never reflows under the mouse.
            PanelActionButton {
              id: parkBtn
              anchors.right: taskRow.index > 0 ? promoteBtn.left : playBtn.left
              anchors.rightMargin: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              opacity: rowHover.hovered && root.editingTaskId !== taskRow.modelData.id ? 1 : 0
              enabled: opacity > 0 && !root.parkFull
              iconText: "󰐃"
              tooltipText: root.parkFull ? "Already one parked" : "Park for later"
              foreground: Qt.darker(root.bar.foreground, 1.4)
              hoverColor: root.bar.foreground
              onClicked: root.parkTask(taskRow.modelData.id)
            }

            // Only the top task can be timed — one thing at a time. It sits
            // where the top row would otherwise have no button at all.
            PanelActionButton {
              id: playBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: taskRow.index === 0
              iconText: taskRow.isRunning ? "󰏤" : "󰐊"
              tooltipText: taskRow.isRunning ? "Pause" : "Start timer"
              foreground: root.bar.foreground
              onClicked: root.toggleTimer()
            }

            PanelActionButton {
              id: promoteBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅃"
              tooltipText: "Move to top"
              // Hidden, not just disabled, when already on top — there's
              // nothing for it to do (and "move #1 down" is the same end
              // state as "promote #2", which already has its own button).
              visible: taskRow.index > 0
              // Dimmer at rest than the other action buttons — it's the
              // least-reached-for one — but back to full brightness on
              // hover so the click target still reads clearly.
              foreground: Qt.darker(root.bar.foreground, 1.4)
              hoverColor: root.bar.foreground
              onClicked: root.promoteTask(taskRow.modelData.id)
            }

            // Brief terminal-style "[ OK ]" tag before the row actually
            // leaves the active list. Declared last so it paints on top of
            // the row's other children — QtQuick stacks same-z siblings in
            // declaration order, and this needs to cover everything above
            // it while it's active, not sit behind it.
            FlashTag {
              id: completeFlash
              frames: ["[    ]", "[ .  ]", "[ .. ]", "[ OK ]"]
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.body
              idleColor: root.bar.foreground
              onFinished: root.completeTask(taskRow.modelData.id)
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

        // No custom blink here — the field auto-focuses on open, so the
        // real text cursor is doing that job already (and correctly, synced
        // to actual typing). A second, independent blinking "_" was left
        // over from before auto-focus existed and just fought the real one.
        TextField {
          id: input
          width: column.width
          enabled: !root.atCap
          placeholderText: root.atCap ? (root.parkFull ? "Finish one first" : "Finish or park one first") : "Add a task"
          foreground: root.bar.foreground
          font.family: root.bar.fontFamily

          onAccepted: root.addTask()
        }

        // One quiet footer line for everything secondary: time stats on the
        // left (click to cycle today/week/month/year, back to today on every
        // open), and the parked/done toggles on the right, each shown only
        // when it has something in it. Keeps the tasks sitting directly on
        // top of the input instead of behind two lines of chrome.
        Item {
          width: column.width
          height: statsText.implicitHeight

          Text {
            id: statsText
            textFormat: Text.PlainText
            anchors.left: parent.left
            text: root.statsPeriod + " · " + Model.formatDuration(Model.periodSeconds(root.days, root.timer, root.statsPeriod, root.now))
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.now = Date.now()
                root.statsPeriodIndex = (root.statsPeriodIndex + 1) % Model.PERIODS.length
              }
            }
          }

          Row {
            anchors.right: parent.right
            spacing: Style.space(4)

            Text {
              textFormat: Text.PlainText
              visible: root.parked.length > 0
              text: "parked " + root.parked.length
              color: root.parkedExpanded ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.parkedExpanded = !root.parkedExpanded
                  if (root.parkedExpanded) root.doneExpanded = false
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.parked.length > 0 && root.done.length > 0
              text: "·"
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              visible: root.done.length > 0
              text: "done " + root.done.length
              color: root.doneExpanded ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.doneExpanded = !root.doneExpanded
                  if (root.doneExpanded) root.parkedExpanded = false
                }
              }
            }
          }
        }

        // Opens below the footer line that toggled it. Only one list at a
        // time, and only the open one instantiates rows (the other's model
        // is []), so a collapsed list costs nothing.
        Column {
          width: column.width
          spacing: Style.space(4)
          visible: (root.parkedExpanded && root.parked.length > 0) || (root.doneExpanded && root.done.length > 0)

          Rectangle {
            width: column.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
          }

          Item { width: 1; height: Style.space(2) }

          Repeater {
            model: root.parkedExpanded ? root.parked : []

            Item {
              id: parkedRow
              required property var modelData
              width: column.width
              height: Style.space(17)

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parkedTime.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: parkedRow.modelData.text
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: Qt.darker(root.bar.foreground, 1.3)
                elide: Text.ElideRight
              }

              Text {
                id: parkedTime
                textFormat: Text.PlainText
                anchors.right: unparkBtn.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: (parkedRow.modelData.seconds || 0) > 0 ? Model.formatDuration(parkedRow.modelData.seconds) : ""
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                color: Qt.darker(root.bar.foreground, 1.6)
              }

              PanelActionButton {
                id: unparkBtn
                anchors.right: clearParkedBtn.left
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                size: Style.space(18)
                iconText: "󰑙"
                tooltipText: root.atCap ? "No free slot" : "Back to active"
                enabled: !root.atCap
                foreground: root.bar.foreground
                onClicked: {
                  if (unparkFlash.active || root.atCap) return
                  unparkFlash.start()
                }
              }

              PanelActionButton {
                id: clearParkedBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                size: Style.space(18)
                iconText: "✕"
                tooltipText: "Drop it"
                foreground: root.bar.foreground
                onClicked: root.clearParked(parkedRow.modelData.id)
              }

              FlashTag {
                id: unparkFlash
                frames: ["[    ]", "[ <  ]", "[ << ]"]
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                idleColor: root.bar.foreground
                onFinished: root.unparkTask(parkedRow.modelData.id)
              }
            }
          }

          // Struck-through and dimmer than parked rows: these are finished.
          Column {
            width: column.width
            spacing: Style.space(4)
            opacity: 0.6

            Repeater {
              model: root.doneExpanded ? root.done : []

              Item {
                id: doneRow
                required property var modelData
                width: column.width
                height: Style.space(17)

                Text {
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.right: doneTime.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: doneRow.modelData.text
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.strikeout: true
                  color: Qt.darker(root.bar.foreground, 1.6)
                  elide: Text.ElideRight
                }

                // Kept out of the struck-through text: the task is done, the
                // time it took isn't crossed out.
                Text {
                  id: doneTime
                  textFormat: Text.PlainText
                  anchors.right: restoreBtn.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: (doneRow.modelData.seconds || 0) > 0 ? Model.formatDuration(doneRow.modelData.seconds) : ""
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(root.bar.foreground, 1.6)
                }

                PanelActionButton {
                  id: restoreBtn
                  anchors.right: clearDoneBtn.left
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.space(18)
                  iconText: "󰑙"
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

                // Mirrors the completion tag: restoring a task is the
                // inverse of finishing one, so it gets the same brief
                // terminal-tag treatment rather than snapping back
                // silently. Declared last so it paints on top of this
                // row's other children while active, same reasoning as
                // the completion tag above.
                FlashTag {
                  id: restoreFlash
                  frames: ["[    ]", "[ <  ]", "[ << ]"]
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.bodySmall
                  idleColor: root.bar.foreground
                  onFinished: root.restoreTask(doneRow.modelData.id)
                }
              }
            }
          }
        }
      }
    }
  }
}
