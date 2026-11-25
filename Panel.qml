import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
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

  // Today (max 3), Later (anything you want out of your head), and today's
  // finished tasks, which stay on view crossed out until midnight but don't
  // take a slot. The lists live in a markdown note; see "Storage".
  property var tasks: []
  property var later: []
  property var done: []
  readonly property bool atCap: tasks.length >= Model.TODAY_CAP

  // The note's parts the panel doesn't show: text above the first heading
  // and the Done log.
  property var notePreamble: []
  property var log: []

  // Tasks finished per day, for the dot strip.
  property var doneCounts: ({})

  // Wall clock for the day boundary and age labels, refreshed on open.
  property real now: Date.now()

  readonly property var strip: Model.dotStrip(Model.withToday(doneCounts, done.length, now), now)

  // Id of the task currently being edited in place, or "" for none.
  property string editingTaskId: ""

  // Later sits under Today while there's a free slot (that's when you pick
  // from it); with Today full it folds behind "later N" in the footer.
  property bool laterExpanded: false
  readonly property bool laterVisible: later.length > 0 && (!atCap || laterExpanded)
  readonly property int laterShown: 8

  // Brief confirmation in the input after a capture.
  property string inputHint: ""

  // "+ step" puts the input into step mode for that task: Enter adds a step
  // instead of a task, Esc goes back to normal.
  property string stepTargetId: ""
  readonly property var stepTarget: root.tasks.find(function(t) { return t.id === root.stepTargetId }) || null

  // One-time tip about the keyboard shortcut, dismissible with ✕.
  property bool tipDismissed: false
  property string shortcutLabel: ""

  property bool settingsOpen: false

  // Plan stage: at the start of the day (nothing timed or finished yet)
  // with a free slot, the panel is about picking the day — boxed slots and
  // Later right below. Once the day gets going it's about doing; a slot
  // that frees up later just shows Later underneath, without the plan header.
  readonly property bool dayFresh: done.length === 0
  readonly property bool planMode: !atCap && dayFresh

  // Today's finished tasks stay out of the way behind one line.
  property bool doneAllShown: false
  readonly property int doneShownCount: doneAllShown ? done.length : 0
  readonly property var laterGroups: Model.laterGroups(later)
  // Ideas don't count as waiting work.
  readonly property int laterTaskCount: laterGroups.important.length + laterGroups.normal.length
  property bool ideasExpanded: false
  readonly property bool laterHasQuick: later.some(function(t) { return Model.groupOf(t) !== "ideas" && Model.isQuick(t.text) })

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function flashHint(text) {
    root.inputHint = text
    hintTimer.restart()
  }

  Timer {
    id: hintTimer
    interval: 1800
    onTriggered: root.inputHint = ""
  }

  // Typing is never blocked: with Today full, Enter files the text under
  // Later instead, so a thought can be written down and let go of right away.
  function addTask() {
    if (root.stepTarget) {
      root.addStepTo(root.stepTargetId)
      return
    }
    var item = Model.newItem(input.text)
    if (!item) return
    if (root.atCap) {
      root.later = [item].concat(root.later)
      root.flashHint("Saved to Later ✓")
    } else {
      root.tasks = root.tasks.concat([item])
    }
    input.text = ""
    persist()
  }

  // Tab in the input (or Enter in step mode) adds the text as a step.
  function addStep() {
    if (root.tasks.length === 0) return
    root.addStepTo(root.tasks[0].id)
  }

  function addStepTo(id) {
    var next = Model.addStep(root.tasks, id, input.text)
    if (!next) {
      if (String(input.text).trim() !== "") root.flashHint("Up to " + Model.STEP_CAP + " steps per task")
      return
    }
    root.tasks = next
    input.text = ""
    persist()
  }

  function startStepMode(id) {
    root.stepTargetId = id
    input.forceActiveFocus()
  }

  function dismissTip() {
    root.tipDismissed = true
    saveStateSoon()
  }

  // Settings live in the shell's own config (the same values as the
  // widget's settings form), written through the omarchy CLI.
  function setSetting(key, value, isJson) {
    settingProc.command = ["omarchy", "bar", "set", root.moduleName, key, String(value)].concat(isJson ? ["--json"] : [])
    settingProc.running = true
  }

  Process {
    id: settingProc
  }

  // Finds the key bound to this panel, if any, for the tip.
  Process {
    id: bindProc
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var hit = JSON.parse(text).find(function(b) {
            return /today'?s top 3|todays-top-3/i.test(String(b.description || "") + " " + String(b.arg || ""))
          })
          root.shortcutLabel = hit ? Model.formatBind(hit.modmask, hit.key) : ""
        } catch (e) {
          root.shortcutLabel = ""
        }
      }
    }
  }

  function toggleStep(id, index) {
    root.tasks = Model.toggleStep(root.tasks, id, index)
    persist()
  }

  function removeStep(id, index) {
    root.tasks = Model.removeStep(root.tasks, id, index)
    persist()
  }

  // Focus on this: straight to the top. Order is the priority, and this
  // is the only way to change it, for "the important one now" as much as
  // "an easy one first to get going".
  function makeTop(id) {
    root.tasks = Model.moveToTop(root.tasks, id)
    persist()
  }

  function completeTask(id) {
    var next = Model.completeTask(root.tasks, root.done, id)
    if (!next) return
    root.tasks = next.tasks
    root.done = next.done
    root.log = Model.addLog(root.log, next.task.text, Date.now(), Model.stepsDone(next.task))
    root.doneCounts = Model.bumpDone(root.doneCounts, Date.now(), 1)
    persist()
    persistHistory()
  }

  // Undo: clicking a crossed-out task puts it back (needs a free slot).
  function restoreTask(id) {
    var next = Model.restoreTask(root.tasks, root.done, id)
    if (!next) return
    root.tasks = next.tasks
    root.done = next.done
    root.log = Model.removeLog(root.log, next.entry.text, next.entry.completedAt)
    root.doneCounts = Model.bumpDone(root.doneCounts, next.entry.completedAt, -1)
    persist()
    persistHistory()
  }

  function toLater(id) {
    var next = Model.moveToLater(root.tasks, root.later, id)
    if (!next) return
    root.tasks = next.tasks
    root.later = next.later
    persist()
  }

  function pullFromLater(id) {
    var next = Model.pullFromLater(root.tasks, root.later, id)
    if (!next) return
    root.tasks = next.tasks
    root.later = next.later
    persist()
  }

  function toggleLaterGroup(id, group) {
    root.later = Model.toggleGroup(root.later, id, group)
    persist()
  }

  function toggleLaterQuick(id) {
    root.later = Model.toggleQuick(root.later, id)
    persist()
  }

  function dropLater(id) {
    root.later = Model.removeItem(root.later, id)
    persist()
  }

  function startEditTask(id) {
    root.editingTaskId = id
  }

  function cancelEditTask() {
    root.editingTaskId = ""
  }

  function commitEditTask(id, text) {
    root.tasks = Model.updateText(root.tasks, id, text)
    root.editingTaskId = ""
    persist()
  }

  // Done entries leave the panel at midnight and the note's log after a
  // month. Checked on open and every half hour; both lists are tiny.
  function pruneExpired() {
    var pruned = Model.pruneDone(root.done)
    var prunedLog = Model.pruneLog(root.log, Date.now())
    if (pruned.length !== root.done.length || prunedLog.length !== root.log.length) {
      root.done = pruned
      root.log = prunedLog
      persist()
    }
  }

  // The double Qt.callLater on focus is deliberate: KeyboardPanel primes its
  // own focusTarget (keyCatcher) via a single deferred call on this same
  // open transition, and ours has to land after it.
  onOpenedChanged: {
    if (root.opened) {
      root.pruneExpired()
      root.now = Date.now()
      root.laterExpanded = false
      root.settingsOpen = false
      root.doneAllShown = false
      root.ideasExpanded = false
      root.stepTargetId = ""
      if (!root.tipDismissed && !bindProc.running) bindProc.running = true
      Qt.callLater(function() {
        Qt.callLater(function() {
          if (root.opened) input.forceActiveFocus()
        })
      })
    } else {
      root.editingTaskId = ""
    }
  }

  // ---- Storage -------------------------------------------------------------
  //
  // Two files:
  // - The note (markdown): Today, Later and a Done log. By default it sits
  //   privately next to the other state. The "Sync with a note" setting
  //   points it at a file in any synced folder (a notes vault, Syncthing,
  //   Dropbox), which is how the lists reach other devices.
  // - todays-top-3.json: what only this machine needs (today's done list,
  //   each item's id and day added, whether the tip was dismissed).
  //
  // Both are watched because the bar exists once per screen, and the note
  // can also change from another device. Our own writes come straight back
  // as change events; those are recognized by content and skipped.
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/"
  readonly property string statePath: stateDir + "todays-top-3.json"
  readonly property string historyPath: stateDir + "todays-top-3-history.json"
  readonly property string localNotePath: stateDir + "todays-top-3.md"

  readonly property string syncPath: Model.expandHome(String(root.setting("notePath", "")).replace(/^file:\/\//, ""), home)
  readonly property bool syncOn: root.setting("syncNote", false) === true && syncPath !== ""
  readonly property string notePath: syncOn ? syncPath : localNotePath

  // The note is only read once local state is in, so ids and times can be
  // matched to it, and a first run can move old lists into it.
  property bool stateReady: false
  property bool wasSyncOn: false
  // Turning sync off writes the current lists back to the local note rather
  // than reading a stale local copy from before sync was on.
  property bool adoptOnNextNoteLoad: false

  onSyncOnChanged: {
    if (!syncOn && wasSyncOn) adoptOnNextNoteLoad = true
    wasSyncOn = syncOn
  }

  onNotePathChanged: {
    root.lastNoteText = ""
    noteDirProc.running = true
  }

  property string lastStateText: ""
  property string lastNoteText: ""
  property string lastHistoryText: ""

  function assignIfChanged(name, value) {
    if (JSON.stringify(root[name]) !== JSON.stringify(value)) root[name] = value
  }

  Process {
    id: ensureDirProc
    command: ["bash", "-c", "mkdir -p \"$1\" && chmod 700 \"$1\"", "--", root.stateDir]
  }

  Process {
    id: noteDirProc
    command: ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\"", "--", root.notePath]
  }

  // Atomic writes replace the file (and its mode) each time, so the
  // owner-only mode is re-applied after every save of the private files.
  Process {
    id: chmodStateProc
    command: ["chmod", "600", root.statePath]
  }

  Process {
    id: chmodNoteProc
    command: ["chmod", "600", root.localNotePath]
  }

  Process {
    id: chmodHistoryProc
    command: ["chmod", "600", root.historyPath]
  }

  // Ids, times and days added are matched to the lists by id first (another
  // screen writing the same ids) and by text second.
  function withMeta(list, items) {
    var used = {}
    return list.map(function(t) {
      var hit = items.find(function(k) { return !used[k.id] && k.id === t.id })
        || items.find(function(k) { return !used[k.id] && k.text === t.text })
      if (!hit) return t
      used[hit.id] = true
      return Object.assign({}, t, { id: hit.id, addedOn: hit.addedOn })
    })
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onSaved: chmodStateProc.running = true
    onLoaded: {
      var raw = text()
      if (raw === root.lastStateText) return
      root.lastStateText = raw
      var state = Model.parseState(raw)
      if (!root.stateReady) {
        // Shown right away; the note, once read, has the final say. If there
        // is no note yet (first run after an update), these move into it.
        root.tasks = state.tasks
        root.later = state.later
      } else if (state.items.length) {
        root.assignIfChanged("tasks", root.withMeta(root.tasks, state.items))
        root.assignIfChanged("later", root.withMeta(root.later, state.items))
      }
      root.assignIfChanged("done", state.done)
      root.tipDismissed = state.tipDismissed
      root.stateReady = true
    }
    onLoadFailed: root.stateReady = true
  }

  FileView {
    id: noteFile
    path: root.stateReady ? root.notePath : ""
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onSaved: if (root.notePath === root.localNotePath) chmodNoteProc.running = true
    onLoaded: {
      var raw = text()
      if (raw === root.lastNoteText) return
      if (root.adoptOnNextNoteLoad) {
        root.adoptOnNextNoteLoad = false
        persist()
        return
      }
      root.lastNoteText = raw
      root.applyNoteText(raw)
    }
    // No note yet: a first run, or sync was just pointed at a new file.
    // Either way, write what the panel has.
    onLoadFailed: {
      root.adoptOnNextNoteLoad = false
      if (root.stateReady) persist()
    }
  }

  function applyNoteText(raw) {
    var applied = Model.applyNote(Model.parseNote(raw), root.tasks.concat(root.later))
    var logNext = applied.log
    var doneNext = root.done
    var countsNext = root.doneCounts
    applied.completed.forEach(function(c) {
      logNext = Model.addLog(logNext, c.text, Date.now(), Model.stepsDone(c))
      doneNext = [{ id: c.id, text: c.text, completedAt: Date.now(), steps: c.steps }].concat(doneNext).slice(0, Model.DONE_SHOWN)
      countsNext = Model.bumpDone(countsNext, Date.now(), 1)
    })
    if (applied.completed.length) {
      root.doneCounts = countsNext
      persistHistory()
    }
    root.notePreamble = applied.preamble
    root.assignIfChanged("tasks", applied.tasks)
    root.assignIfChanged("later", applied.later)
    root.assignIfChanged("done", doneNext)
    root.log = logNext
    // Writes back only if the tidy form differs (e.g. old marks converted).
    persist()
  }

  FileView {
    id: historyFile
    path: root.historyPath
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onSaved: chmodHistoryProc.running = true
    onLoaded: {
      var raw = text()
      if (raw === root.lastHistoryText) return
      root.lastHistoryText = raw
      root.assignIfChanged("doneCounts", Model.parseDoneCounts(raw))
    }
  }

  function persist() {
    saveNoteTimer.restart()
    saveStateSoon()
  }

  function saveStateSoon() {
    saveStateTimer.restart()
  }

  Timer {
    id: saveStateTimer
    interval: 200
    repeat: false
    onTriggered: {
      var text = Model.serializeState(root.tasks, root.later, root.done, root.tipDismissed)
      if (text === root.lastStateText) return
      root.lastStateText = text
      stateFile.setText(text)
    }
  }

  Timer {
    id: saveNoteTimer
    interval: 200
    repeat: false
    onTriggered: {
      if (!root.stateReady) return
      var text = Model.serializeNote(root.notePreamble, root.tasks, root.later, root.log)
      if (text === root.lastNoteText) return
      root.lastNoteText = text
      noteFile.setText(text)
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
      root.lastHistoryText = Model.serializeHistory(root.doneCounts)
      historyFile.setText(root.lastHistoryText)
    }
  }

  Timer {
    interval: 30 * 60 * 1000
    repeat: true
    running: true
    onTriggered: {
      root.now = Date.now()
      root.pruneExpired()
    }
  }

  Component.onCompleted: {
    ensureDirProc.running = true
    Qt.callLater(function() {
      stateFile.reload()
      historyFile.reload()
    })
  }

  // ---- UI ------------------------------------------------------------------

  readonly property color dimText: Qt.darker(root.bar.foreground, 1.6)
  readonly property color quietText: Qt.darker(root.bar.foreground, 1.3)
  readonly property color accent: Color.accent

  function ageLabel(item) {
    var d = Model.ageDays(item.addedOn, root.now)
    return d > 0 ? d + "d" : ""
  }

  function stripShade(level) {
    if (level < 0) return "transparent"
    if (level === 0) return Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.1)
    return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, level === 1 ? 0.55 : level === 2 ? 0.8 : 1)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
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

        // Capture first: the cursor lands here every time the panel opens.
        // Settings take over the whole panel, so everything else steps aside.
        Row {
          visible: !root.settingsOpen
          width: column.width
          spacing: Style.space(6)

          Text {
            id: promptGlyph
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            color: root.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          TextField {
            id: input
            width: column.width - promptGlyph.width - Style.space(6)
            placeholderText: root.inputHint !== "" ? root.inputHint
              : root.stepTarget ? "Step for: " + root.stepTarget.text
              : (root.atCap ? "Add a thought for Later" : "Add a task")
            foreground: root.bar.foreground
            font.family: root.bar.fontFamily

            onAccepted: root.addTask()
            Keys.onEscapePressed: function(event) {
              if (root.stepTargetId !== "") {
                root.stepTargetId = ""
                input.text = ""
                event.accepted = true
              } else {
                event.accepted = false
              }
            }
            Keys.onTabPressed: function(event) {
              if (input.text.trim() !== "" && root.tasks.length > 0) {
                root.addStep()
                event.accepted = true
              } else {
                event.accepted = false
              }
            }
          }
        }

        Item {
          visible: !root.settingsOpen
          width: column.width
          height: todayHeader.implicitHeight

          Text {
            id: todayHeader
            textFormat: Text.PlainText
            text: root.planMode ? "PICK TODAY'S 3" : "TODAY"
            color: root.planMode ? root.bar.foreground : root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
          }
        }

        Repeater {
          model: root.settingsOpen ? [] : root.tasks

          Column {
            id: taskBlock
            required property var modelData
            required property int index
            width: column.width
            spacing: Style.space(6)

            readonly property bool isTop: index === 0
            readonly property var steps: modelData.steps || []
            readonly property int stepsDone: Model.stepsDone(modelData)

            Item {
              id: taskRow
              width: parent.width
              height: Math.max(doneBtn.height, textColumn.implicitHeight, Style.space(22))

              HoverHandler { id: rowHover }
              readonly property bool showHoverActions: rowHover.hovered && root.editingTaskId !== taskBlock.modelData.id

              // Each task sits in its numbered slot; #1 is outlined in the
              // accent colour.
              Rectangle {
                anchors.fill: parent
                anchors.margins: -Style.space(5)
                radius: Style.space(5)
                color: "transparent"
                border.width: 1
                border.color: taskBlock.isTop
                  ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
                  : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.22)
              }

              // The slot number; hovering the row turns it into ✓ Done.
              Text {
                anchors.horizontalCenter: doneBtn.horizontalCenter
                anchors.verticalCenter: doneBtn.verticalCenter
                visible: !rowHover.hovered
                text: String(taskBlock.index + 1)
                color: taskBlock.isTop ? root.accent : root.dimText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              PanelActionButton {
                id: doneBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                opacity: rowHover.hovered ? 1 : 0
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
                anchors.right: stepBtn.left
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  visible: taskBlock.modelData.id !== root.editingTaskId
                  width: textColumn.width
                  text: (Model.isQuick(taskBlock.modelData.text) ? "⚡ " : "") + Model.displayText(taskBlock.modelData.text)
                  // While doing, #1 leads; the other two step back.
                  readonly property bool secondary: !root.planMode && !taskBlock.isTop
                  color: secondary ? root.quietText : root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: secondary ? Style.font.body : Style.font.subtitle
                  font.bold: !secondary
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.startEditTask(taskBlock.modelData.id)
                  }
                }

                TextArea {
                  id: editField
                  visible: taskBlock.modelData.id === root.editingTaskId
                  width: textColumn.width
                  text: taskBlock.modelData.text
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
                      root.commitEditTask(taskBlock.modelData.id, editField.text)
                      event.accepted = true
                    }
                  }
                }

                // Time spent, steps (on the tasks below the top one) and how
                // many days the task has waited. Nothing for a fresh task.
                Text {
                  textFormat: Text.PlainText
                  visible: text !== "" && taskBlock.modelData.id !== root.editingTaskId
                  text: [
                    !taskBlock.isTop && taskBlock.steps.length > 0 ? taskBlock.stepsDone + "/" + taskBlock.steps.length : "",
                    root.ageLabel(taskBlock.modelData)
                  ].filter(function(s) { return s !== "" }).join(" · ")
                  color: root.dimText
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              PanelActionButton {
                id: stepBtn
                anchors.right: laterBtn.left
                anchors.verticalCenter: parent.verticalCenter
                opacity: taskRow.showHoverActions && taskBlock.steps.length < Model.STEP_CAP ? 1 : 0
                enabled: opacity > 0
                iconText: "󰐕"
                tooltipText: "Add a step"
                foreground: Qt.darker(root.bar.foreground, 1.4)
                hoverColor: root.bar.foreground
                onClicked: root.startStepMode(taskBlock.modelData.id)
              }

              PanelActionButton {
                id: laterBtn
                anchors.right: taskBlock.isTop ? parent.right : startBtn.left
                anchors.rightMargin: Style.space(2)
                anchors.verticalCenter: parent.verticalCenter
                opacity: taskRow.showHoverActions ? 1 : 0
                enabled: opacity > 0
                iconText: "󰄠"
                tooltipText: "Move to Later"
                foreground: Qt.darker(root.bar.foreground, 1.4)
                hoverColor: root.bar.foreground
                onClicked: root.toLater(taskBlock.modelData.id)
              }

              // Focus on this: to the top of the list.
              PanelActionButton {
                id: startBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !taskBlock.isTop
                opacity: taskRow.showHoverActions ? 1 : 0
                enabled: opacity > 0
                iconText: "↑"
                tooltipText: "Focus on this (make it #1)"
                foreground: Qt.darker(root.bar.foreground, 1.4)
                hoverColor: root.bar.foreground
                onClicked: root.makeTop(taskBlock.modelData.id)
              }

              // The finishing moment: the row burns through in dither blocks.
              FlashTag {
                id: completeFlash
                sweep: true
                frames: ["░", "▒", "▓", "█"]
                frameInterval: 80
                holdInterval: 120
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.subtitle
                idleColor: root.accent
                finishColor: root.accent
                onFinished: root.completeTask(taskBlock.modelData.id)
              }
            }

            // Steps show on the top task only. The first open one is the
            // next thing to do, so it's the one in bold.
            Repeater {
              model: taskBlock.isTop || root.stepTargetId === taskBlock.modelData.id ? taskBlock.steps : []

              Item {
                id: stepRow
                required property var modelData
                required property int index
                width: taskBlock.width
                height: Style.space(18)

                readonly property bool isNext: !modelData.done && taskBlock.steps.findIndex(function(s) { return !s.done }) === index
                HoverHandler { id: stepHover }

                Text {
                  id: stepMark
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(32)
                  anchors.verticalCenter: parent.verticalCenter
                  text: stepRow.modelData.done ? "✓" : (stepRow.isNext ? "›" : "○")
                  color: stepRow.modelData.done || stepRow.isNext ? root.accent : root.dimText
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.left: stepMark.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: removeStepBtn.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: stepRow.modelData.text
                  color: stepRow.modelData.done ? root.dimText : root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: stepRow.isNext
                  font.strikeout: stepRow.modelData.done
                  elide: Text.ElideRight
                }

                MouseArea {
                  anchors.left: parent.left
                  anchors.right: removeStepBtn.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleStep(taskBlock.modelData.id, stepRow.index)
                }

                PanelActionButton {
                  id: removeStepBtn
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.space(16)
                  opacity: stepHover.hovered ? 1 : 0
                  enabled: opacity > 0
                  iconText: "✕"
                  tooltipText: "Remove step"
                  foreground: root.dimText
                  hoverColor: root.bar.foreground
                  onClicked: root.removeStep(taskBlock.modelData.id, stepRow.index)
                }
              }
            }

            // Visible way in to steps on the top task.
            Text {
              visible: root.stepTargetId === taskBlock.modelData.id
              leftPadding: Style.space(32)
              textFormat: Text.PlainText
              text: "+ type the step above, Enter to add · Esc when done"
              color: root.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startStepMode(taskBlock.modelData.id)
              }
            }
          }
        }

        // Free slots: dashed numbered boxes, so an empty one reads as a
        // place to fill.
        Repeater {
          model: root.settingsOpen ? 0 : Math.max(0, Model.TODAY_CAP - root.tasks.length)

          Item {
            id: freeSlot
            required property int index
            width: column.width
            height: Style.space(24)

            Shape {
              x: -Style.space(5)
              y: -Style.space(5)
              width: freeSlot.width + Style.space(10)
              height: freeSlot.height + Style.space(10)
              preferredRendererType: Shape.CurveRenderer

              ShapePath {
                strokeWidth: 1
                strokeColor: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.22)
                strokeStyle: ShapePath.DashLine
                dashPattern: [4, 3]
                fillColor: "transparent"
                PathRectangle {
                  x: 0.5
                  y: 0.5
                  width: freeSlot.width + Style.space(10) - 1
                  height: freeSlot.height + Style.space(10) - 1
                  radius: Style.space(5)
                }
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              leftPadding: Style.space(9)
              text: (root.tasks.length + freeSlot.index + 1) + "     empty"
              color: Qt.darker(root.bar.foreground, 2.0)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // Later: under Today whenever a slot is free, so picking the day is
        // just ↑. With Today full it waits behind "later N" in the footer.
        Column {
          width: column.width
          spacing: Style.space(6)
          visible: root.laterVisible && !root.settingsOpen

          Rectangle {
            width: column.width
            height: Style.spacing.hairline
            color: root.bar.foreground
            opacity: 0.12
          }

          Text {
            topPadding: Style.space(4)
            textFormat: Text.PlainText
            text: root.planMode ? "FROM LATER · " + root.laterTaskCount : "LATER · " + root.laterTaskCount
            color: root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
          }

          // Important first, then the rest. Ideas fold away below.
          Text {
            visible: root.laterGroups.important.length > 0
            topPadding: Style.space(2)
            textFormat: Text.PlainText
            text: "IMPORTANT"
            color: root.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
          }

          Repeater {
            model: root.laterVisible ? root.laterGroups.important : []
            delegate: laterRowComponent
          }

          Text {
            visible: root.laterGroups.important.length > 0 && root.laterGroups.normal.length > 0
            topPadding: Style.space(4)
            textFormat: Text.PlainText
            text: "OTHER"
            color: root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
          }

          Repeater {
            model: root.laterVisible ? root.laterGroups.normal.slice(0, root.laterShown) : []
            delegate: laterRowComponent
          }

          Text {
            textFormat: Text.PlainText
            visible: root.laterGroups.normal.length > root.laterShown
            text: "+" + (root.laterGroups.normal.length - root.laterShown) + " more in the note"
            color: root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: root.laterGroups.ideas.length > 0
            textFormat: Text.PlainText
            topPadding: Style.space(4)
            text: (root.ideasExpanded ? "▾ " : "▸ ") + "IDEAS · " + root.laterGroups.ideas.length
            color: root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.ideasExpanded = !root.ideasExpanded
            }
          }

          Repeater {
            model: root.laterVisible && root.ideasExpanded ? root.laterGroups.ideas : []
            delegate: laterRowComponent
          }

          Component {
            id: laterRowComponent

            Item {
              id: laterRow
              required property var modelData
              width: column.width
              height: Style.space(18)
              HoverHandler { id: laterHover }

              readonly property bool important: Model.groupOf(modelData) === "important"
              readonly property bool idea: Model.groupOf(modelData) === "ideas"
              readonly property bool quick: Model.isQuick(modelData.text)

              // Leading mark: ⚡ for a quick win, else a quiet dot, so
              // every row's text starts in the same place.
              Text {
                id: laterLead
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(16)
                text: laterRow.quick ? "⚡" : "·"
                color: laterRow.quick ? root.accent : root.dimText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                textFormat: Text.PlainText
                anchors.left: laterLead.right
                anchors.right: markImportantBtn.left
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                text: Model.displayText(laterRow.modelData.text)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: laterRow.idea ? root.dimText : root.quietText
                elide: Text.ElideRight
              }

              // Sorting buttons, on hover: important, idea, quick win.
              PanelActionButton {
                id: markImportantBtn
                anchors.right: markIdeaBtn.left
                anchors.verticalCenter: parent.verticalCenter
                size: Style.space(18)
                opacity: laterHover.hovered ? 1 : 0
                enabled: opacity > 0
                iconText: laterRow.important ? "󰓎" : "󰓒"
                tooltipText: laterRow.important ? "Not important" : "Important"
                foreground: laterRow.important ? root.accent : root.dimText
                hoverColor: root.bar.foreground
                onClicked: root.toggleLaterGroup(laterRow.modelData.id, "important")
              }

              PanelActionButton {
                id: markIdeaBtn
                anchors.right: markQuickBtn.left
                anchors.verticalCenter: parent.verticalCenter
                size: Style.space(18)
                opacity: laterHover.hovered ? 1 : 0
                enabled: opacity > 0
                iconText: "󰌶"
                tooltipText: laterRow.idea ? "Make it a task" : "Just an idea"
                foreground: laterRow.idea ? root.accent : root.dimText
                hoverColor: root.bar.foreground
                onClicked: root.toggleLaterGroup(laterRow.modelData.id, "ideas")
              }

              PanelActionButton {
                id: markQuickBtn
                anchors.right: dropBtn.left
                anchors.verticalCenter: parent.verticalCenter
                size: Style.space(18)
                opacity: laterHover.hovered ? 1 : 0
                enabled: opacity > 0
                iconText: "⚡"
                tooltipText: laterRow.quick ? "Not a quick one" : "Quick win"
                foreground: laterRow.quick ? root.accent : root.dimText
                hoverColor: root.bar.foreground
                onClicked: root.toggleLaterQuick(laterRow.modelData.id)
              }

              PanelActionButton {
                id: dropBtn
                anchors.right: pullBtn.left
                anchors.verticalCenter: parent.verticalCenter
                size: Style.space(18)
                opacity: laterHover.hovered ? 1 : 0
                enabled: opacity > 0
                iconText: "✕"
                tooltipText: "Drop it"
                foreground: root.dimText
                hoverColor: root.bar.foreground
                onClicked: root.dropLater(laterRow.modelData.id)
              }

              PanelActionButton {
                id: pullBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                size: Style.space(18)
                iconText: "↑"
                tooltipText: root.atCap ? "Today is full" : "Move to Today"
                enabled: !root.atCap
                foreground: root.bar.foreground
                onClicked: root.pullFromLater(laterRow.modelData.id)
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.planMode && root.laterHasQuick
            topPadding: Style.space(4)
            text: "⚡ quick ones are a good way to get going"
            color: root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Settings, behind the gear in the footer. Sync is off by default:
        // the lists stay in a private local note unless you point them at a
        // file in a synced folder (a notes vault, Syncthing, Dropbox).
        Column {
          width: column.width
          spacing: Style.space(8)
          visible: root.settingsOpen

          Item {
            width: column.width
            height: settingsTitle.implicitHeight

            Text {
              id: settingsTitle
              textFormat: Text.PlainText
              text: "‹  SETTINGS"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.5

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settingsOpen = false
              }
            }
          }

          Item {
            width: column.width
            height: syncLabel.implicitHeight

            Text {
              id: syncLabel
              anchors.left: parent.left
              textFormat: Text.PlainText
              text: "Sync with a note (e.g. Obsidian)"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: root.setting("syncNote", false) === true ? "[ on ]" : "[ off ]"
              color: root.setting("syncNote", false) === true ? root.accent : root.dimText
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setSetting("syncNote", root.setting("syncNote", false) !== true, true)
              }
            }
          }

          TextField {
            id: notePathField
            width: column.width
            text: String(root.setting("notePath", ""))
            placeholderText: "~/Notes/Top 3.md"
            foreground: root.bar.foreground
            font.family: root.bar.fontFamily
            onAccepted: root.setSetting("notePath", Model.expandHome(text, root.home), false)
          }

          Text {
            width: column.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.syncOn ? "Synced: " + root.notePath : "Off: lists stay in " + root.localNotePath + ". Enter a .md path and press Enter, then turn sync on."
            color: root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Today's finished tasks, opened from "✓ n done" in the footer. They don't take a slot.
        // Clicking one puts it back, which is the undo for a misclick.
        Repeater {
          model: root.settingsOpen ? [] : root.done.slice(0, root.doneShownCount)

          Item {
            id: doneRow
            required property var modelData
            width: column.width
            height: Style.space(20)
            HoverHandler { id: doneHover }

            Text {
              id: doneMark
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "✓"
              color: root.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              textFormat: Text.PlainText
              anchors.left: doneMark.right
              anchors.leftMargin: Style.space(14)
              anchors.right: doneTime.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: doneRow.modelData.text
              color: root.dimText
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.strikeout: true
              elide: Text.ElideRight
            }

            Text {
              id: doneTime
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: doneHover.hovered ? (root.atCap ? "slots full" : "undo")
                : ""
              color: root.dimText
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              enabled: !root.atCap
              cursorShape: Qt.PointingHandCursor
              onClicked: root.restoreTask(doneRow.modelData.id)
            }
          }
        }

        Rectangle {
          width: column.width
          height: Style.spacing.hairline
          color: root.bar.foreground
          opacity: 0.12
        }

        // Footer: half a year of finished tasks as small dots (today
        // outlined), then today's done count, the Later count and settings.
        Item {
          width: column.width
          height: Math.max(stripGrid.height, footerText.implicitHeight)

          Grid {
            id: stripGrid
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            rows: 7
            flow: Grid.TopToBottom
            spacing: 2

            Repeater {
              model: root.strip

              Rectangle {
                required property var modelData
                width: 6
                height: 6
                radius: 1
                color: root.stripShade(modelData.level)
                border.width: modelData.today ? 1 : 0
                border.color: root.bar.foreground
              }
            }
          }

          PanelActionButton {
            id: gearBtn
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            size: Style.space(18)
            iconText: "󰒓"
            tooltipText: "Settings"
            foreground: root.settingsOpen ? root.bar.foreground : root.dimText
            hoverColor: root.bar.foreground
            onClicked: root.settingsOpen = !root.settingsOpen
          }

          Column {
            id: footerText
            anchors.right: gearBtn.left
            anchors.rightMargin: Style.space(6)
            anchors.bottom: parent.bottom
            spacing: Style.space(2)

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              visible: root.done.length > 0
              text: "✓ " + root.done.length + " done"
              color: root.doneAllShown ? root.bar.foreground : root.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.doneAllShown = !root.doneAllShown
              }
            }

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              visible: root.later.length > 0
              text: "later " + root.laterTaskCount + (root.laterGroups.ideas.length ? " · " + root.laterGroups.ideas.length + " ideas" : "")
              color: root.laterExpanded ? root.bar.foreground : root.dimText
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                anchors.fill: parent
                enabled: root.atCap
                cursorShape: root.atCap ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.laterExpanded = !root.laterExpanded
              }
            }
          }
        }
        // One-time tip about the shortcut, under everything else. ✕ hides it.
        Item {
          width: column.width
          height: tipText.implicitHeight
          visible: !root.tipDismissed && !root.settingsOpen

          Text {
            id: tipText
            anchors.left: parent.left
            anchors.right: tipClose.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.shortcutLabel !== ""
              ? root.shortcutLabel + " opens this from anywhere"
              : "Tip: give this a keyboard shortcut (see README)"
            color: root.dimText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelActionButton {
            id: tipClose
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            size: Style.space(16)
            iconText: "✕"
            tooltipText: "Got it"
            foreground: root.dimText
            hoverColor: root.bar.foreground
            onClicked: root.dismissTip()
          }
        }

      }
    }
  }
}
