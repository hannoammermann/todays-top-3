.pragma library

function generateId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

// Capped at 3: the slot is the feature. Everything else waits in Later.
var TODAY_CAP = 3
// The note's Done log keeps a month, newest first.
var LOG_DAYS = 30
// Steps break a task into small pieces: one level, a handful at most.
var STEP_CAP = 5
// Today's finished tasks stay on view (crossed out) until midnight.
var DONE_SHOWN = 10

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

function dayKey(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

function dayStart(key) {
  var p = String(key).split("-")
  return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])).getTime()
}

function startOfToday() {
  var now = new Date()
  return new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
}

// Ids start with the creation time in base 36, which recovers the day a
// task was added for lists saved before addedOn existed.
function addedOnFromId(id) {
  var ms = parseInt(String(id).slice(0, 8), 36)
  return isFinite(ms) && ms > 1600000000000 && ms < Date.now() + 86400000 ? dayKey(ms) : dayKey(Date.now())
}

// Whole days since the task joined the list; 0 for today.
function ageDays(addedOn, now) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(addedOn || ""))) return 0
  var today = new Date(now)
  var todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()
  return Math.max(0, Math.round((todayStart - dayStart(addedOn)) / 86400000))
}

function validItem(t) {
  return t && typeof t.id === "string" && typeof t.text === "string"
}

function validDone(d) {
  return validItem(d) && typeof d.completedAt === "number"
}

function cleanSteps(steps) {
  if (!Array.isArray(steps)) return []
  return steps.filter(function(s) { return s && typeof s.text === "string" && s.text !== "" })
    .slice(0, STEP_CAP).map(function(s) { return { text: s.text, done: s.done === true } })
}

function cleanItem(t) {
  var item = { id: t.id, text: t.text, addedOn: typeof t.addedOn === "string" ? t.addedOn : addedOnFromId(t.id), steps: cleanSteps(t.steps) }
  if (t.group && t.group !== "later" && GROUPS.indexOf(t.group) >= 0) item.group = t.group
  return item
}

function cleanDone(d) {
  return { id: d.id, text: d.text, completedAt: d.completedAt, steps: cleanSteps(d.steps) }
}

function stepsDone(item) {
  return (item.steps || []).filter(function(s) { return s.done }).length
}

// Only the first character — never force-lowercases the rest, so acronyms
// and proper nouns ("BIOS settings") survive intact.
function capitalizeFirst(text) {
  return text.charAt(0).toUpperCase() + text.slice(1)
}

// "Recently done" in the panel means done today — cleared at local midnight.
// The note's Done log is the long-term record.
function pruneDone(done) {
  var cutoff = startOfToday()
  return done.filter(function(d) { return d.completedAt >= cutoff })
}

// ---- Local state (JSON) ----------------------------------------------------
//
// The note holds what the lists are; this file holds what only this machine
// needs: today's done list and per-item metadata (id, day added) matched to
// the note by text. It also
// keeps a copy of both lists, which fills a missing note back in.
// Version 3 files kept the lists here too; they're read as-is so the first
// run can move them into the note.

function emptyState() {
  return { tasks: [], later: [], done: [] }
}

function parseState(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    var raw = Array.isArray(parsed && parsed.items) ? parsed.items.filter(validItem) : []
    var items = raw.map(cleanItem)
    var tasks, later
    if (raw.length) {
      tasks = raw.filter(function(t) { return t.list !== "later" }).slice(0, TODAY_CAP).map(cleanItem)
      later = raw.filter(function(t) { return t.list === "later" }).map(cleanItem)
    } else {
      tasks = Array.isArray(parsed && parsed.tasks) ? parsed.tasks.filter(validItem).slice(0, TODAY_CAP).map(cleanItem) : []
      later = Array.isArray(parsed && parsed.parked) ? parsed.parked.filter(validItem).map(cleanItem) : []
    }
    var done = Array.isArray(parsed && parsed.done) ? pruneDone(parsed.done.filter(validDone)).slice(0, DONE_SHOWN).map(cleanDone) : []
    var ui = parsed && parsed.ui && typeof parsed.ui === "object" ? parsed.ui : {}
    return { items: items, tasks: tasks, later: later, done: done, tipDismissed: ui.tipDismissed === true }
  } catch (e) {
    var empty = emptyState()
    empty.items = []
    empty.tipDismissed = false
    return empty
  }
}

function serializeState(tasks, later, done, tipDismissed) {
  return JSON.stringify({
    version: 5,
    items: tasks.map(function(t) { return Object.assign(cleanItem(t), { list: "today" }) })
      .concat(later.map(function(t) { return Object.assign(cleanItem(t), { list: "later" }) })),
    done: done,
    ui: { tipDismissed: tipDismissed === true }
  }, null, 2) + "\n"
}

// Turns a Hyprland bind (modmask bits + key) into "SUPER+ALT+T".
function formatBind(modmask, key) {
  var names = [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]]
  var parts = names.filter(function(n) { return modmask & n[0] }).map(function(n) { return n[1] })
  return parts.concat([String(key).toUpperCase()]).join("+")
}

// ---- The note (markdown) ---------------------------------------------------
//
// Plain markdown so it reads and edits fine anywhere, including a phone:
//
//   ## Today
//   - [ ] Update CTA button
//     - [x] Get new copy
//     - [ ] Swap the button
//   ## Later
//   - [ ] Compare NAS boards
//   ## Done
//   - [x] 2026-11-25 Send the weekly update (2 steps)
//
// Parsing is lenient: headings in any case, "- [ ]", "- [x]" or bare "- "
// bullets. Indented checkboxes under a task are its steps. Anything above
// "## Today" (a title, properties) is kept as-is. Lines in other
// sections are dropped on the next write, so the note stays short.

function parseNote(raw) {
  var lines = String(raw || "").split(/\r?\n/)
  var result = { preamble: [], today: [], later: [], log: [] }
  var groupOfSection = { important: "important", later: "later", ideas: "ideas" }
  var section = ""
  var seenHeading = false
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var heading = line.match(/^#{1,6}\s+(.*?)\s*$/)
    if (heading) {
      var name = heading[1].toLowerCase()
      var known = name === "today" ? "today"
        : name === "important" ? "important"
        : name === "later" ? "later"
        : name === "ideas" || name === "idea" ? "ideas"
        : name === "done" ? "done" : ""
      // A title or other heading above the lists belongs to the preamble.
      if (known || seenHeading) {
        seenHeading = true
        section = known
        continue
      }
    }
    if (!seenHeading) {
      result.preamble.push(line)
      continue
    }
    var item = line.match(/^(\s*)[-*+]\s+(?:\[([ xX])\]\s*)?(.*?)\s*$/)
    if (!item || !item[3]) continue
    var checked = item[2] === "x" || item[2] === "X"
    var inLater = groupOfSection[section] !== undefined
    var list = section === "today" ? result.today : inLater ? result.later : null
    if (list && item[1].length > 0 && list.length > 0) {
      var parent = list[list.length - 1]
      if (parent.steps.length < STEP_CAP) parent.steps.push({ text: item[3], done: checked })
    } else if (list) {
      var entry = inLater ? fromLegacyMarks(item[3], groupOfSection[section]) : fromLegacyMarks(item[3], "later")
      list.push({ text: entry.text, checked: checked, steps: [], group: inLater ? entry.group : undefined })
    } else if (section === "done" && item[1].length === 0) {
      result.log.push("- [x] " + item[3])
    }
  }
  while (result.preamble.length && result.preamble[result.preamble.length - 1].trim() === "") result.preamble.pop()
  return result
}

function serializeNote(preamble, tasks, later, log) {
  var out = []
  if (preamble && preamble.length) out = out.concat(preamble, [""])
  function push(t) {
    out.push("- [ ] " + t.text)
    ;(t.steps || []).forEach(function(s) { out.push("  - [" + (s.done ? "x" : " ") + "] " + s.text) })
  }
  out.push("## Today")
  tasks.forEach(push)
  var g = laterGroups(later)
  // Important and Ideas only appear once they have something in them.
  if (g.important.length) {
    out.push("", "## Important")
    g.important.forEach(push)
  }
  out.push("", "## Later")
  g.normal.forEach(push)
  if (g.ideas.length) {
    out.push("", "## Ideas")
    g.ideas.forEach(push)
  }
  out.push("", "## Done")
  out = out.concat(log)
  return out.join("\n") + "\n"
}

// Gives each note line back its id, time and day added by matching text
// against what this machine already knew. Lines new to it (typed on another
// device) get a fresh id and today's date.
//
// Fresh ids come from the text, so every screen's copy picks the same one.
function textId(text, n) {
  var h = 5381
  for (var i = 0; i < text.length; i++) h = ((h * 33) ^ text.charCodeAt(i)) >>> 0
  return "n" + h.toString(36) + (n ? "-" + n : "")
}

function attachMeta(entries, known, used) {
  return entries.map(function(e) {
    for (var i = 0; i < known.length; i++) {
      var k = known[i]
      if (!used[k.id] && k.text === e.text) {
        used[k.id] = true
        return { id: k.id, text: e.text, addedOn: k.addedOn, steps: cleanSteps(e.steps), group: e.group }
      }
    }
    var n = 0
    while (used[textId(e.text, n)]) n++
    var id = textId(e.text, n)
    used[id] = true
    return { id: id, text: e.text, addedOn: dayKey(Date.now()), steps: cleanSteps(e.steps), group: e.group }
  })
}

// Turns a parsed note into lists. Ticked lines anywhere count as finished
// (ticking a box on the phone is how you complete from there), and more than
// 3 open Today lines spill over to the top of Later.
function applyNote(note, known) {
  var used = {}
  var openToday = note.today.filter(function(e) { return !e.checked })
  var openLater = note.later.filter(function(e) { return !e.checked })
  var finished = note.today.concat(note.later).filter(function(e) { return e.checked })
  var tasks = attachMeta(openToday, known, used)
  var later = attachMeta(openLater, known, used)
  var completed = attachMeta(finished, known, used)
  var overflow = tasks.slice(TODAY_CAP)
  return {
    preamble: note.preamble,
    tasks: tasks.slice(0, TODAY_CAP),
    later: overflow.concat(later),
    completed: completed,
    log: note.log,
    changed: finished.length > 0 || overflow.length > 0
  }
}

function logEntry(text, now, steps) {
  var line = "- [x] " + dayKey(now) + " " + text
  return steps > 0 ? line + " (" + steps + (steps === 1 ? " step)" : " steps)") : line
}

function addLog(log, text, now, steps) {
  return [logEntry(text, now, steps || 0)].concat(log)
}

// Undoing a completion takes back today's log line for it.
function removeLog(log, text, now) {
  var prefix = "- [x] " + dayKey(now) + " " + text
  for (var i = 0; i < log.length; i++) {
    if (log[i] === prefix || log[i].indexOf(prefix + " (") === 0) return log.slice(0, i).concat(log.slice(i + 1))
  }
  return log
}

// Dated entries older than a month go; undated lines are left alone.
function pruneLog(log, now) {
  var cutoff = dayKey(now - LOG_DAYS * 86400000)
  return log.filter(function(line) {
    var m = line.match(/^- \[x\] (\d{4}-\d{2}-\d{2})/)
    return !m || m[1] >= cutoff
  })
}

// ---- Groups and quick -----------------------------------------------------
//
// Later is split into three groups, each its own heading in the note:
// Important, Later and Ideas. A quick win is marked with ⚡ at the end of
// its text, which reads the same in the panel and the note.

var GROUPS = ["important", "later", "ideas"]

function groupOf(item) {
  return GROUPS.indexOf(item && item.group) >= 0 ? item.group : "later"
}

function isQuick(text) {
  return /\s*⚡\s*$/.test(String(text || ""))
}

function displayText(text) {
  return String(text || "").replace(/\s*⚡\s*$/, "")
}

function setQuick(text, on) {
  var base = displayText(text)
  return on ? base + " ⚡" : base
}

// Notes written with the earlier one-character marks (! ~ ?) still read
// right: the mark picks the group or adds ⚡, then goes away.
function fromLegacyMarks(text, group) {
  var m = String(text || "").match(/^\s*((?:[~!?]\s*)+)(.*)$/)
  if (!m) return { text: text, group: group }
  var quick = m[1].indexOf("~") >= 0
  var g = m[1].indexOf("!") >= 0 ? "important" : m[1].indexOf("?") >= 0 ? "ideas" : group
  return { text: quick ? setQuick(m[2], true) : m[2], group: g }
}

// Quick ones lead within each group; otherwise newest first as stored.
function laterGroups(later) {
  function quickFirst(list) {
    return list.filter(function(t) { return isQuick(t.text) }).concat(list.filter(function(t) { return !isQuick(t.text) }))
  }
  return {
    important: quickFirst(later.filter(function(t) { return groupOf(t) === "important" })),
    normal: quickFirst(later.filter(function(t) { return groupOf(t) === "later" })),
    ideas: later.filter(function(t) { return groupOf(t) === "ideas" })
  }
}

// Clicking a group button on an item moves it there, or back to plain
// Later if it's already in that group.
function toggleGroup(items, id, group) {
  return items.map(function(t) {
    return t.id === id ? Object.assign({}, t, { group: groupOf(t) === group ? "later" : group }) : t
  })
}

function toggleQuick(items, id) {
  return items.map(function(t) {
    return t.id === id ? Object.assign({}, t, { text: setQuick(t.text, !isQuick(t.text)) }) : t
  })
}

// ---- List operations -------------------------------------------------------

function newItem(text) {
  var trimmed = String(text || "").trim()
  if (!trimmed) return null
  return { id: generateId(), text: capitalizeFirst(trimmed), addedOn: dayKey(Date.now()), steps: [] }
}

function completeTask(tasks, done, id) {
  var index = tasks.findIndex(function(t) { return t.id === id })
  if (index < 0) return null
  var task = tasks[index]
  return {
    task: task,
    tasks: tasks.filter(function(t) { return t.id !== id }),
    done: [{ id: task.id, text: task.text, completedAt: Date.now(), steps: cleanSteps(task.steps) }].concat(done).slice(0, DONE_SHOWN)
  }
}

function clearDone(done, id) {
  return done.filter(function(d) { return d.id !== id })
}

// Undo for a misclick on "done", only into a free slot.
function restoreTask(tasks, done, id) {
  if (tasks.length >= TODAY_CAP) return null
  var index = done.findIndex(function(d) { return d.id === id })
  if (index < 0) return null
  var entry = done[index]
  return {
    entry: entry,
    done: done.filter(function(d) { return d.id !== id }),
    tasks: tasks.concat([{ id: entry.id, text: entry.text, addedOn: dayKey(entry.completedAt), steps: cleanSteps(entry.steps) }])
  }
}

function updateText(items, id, text) {
  var trimmed = String(text || "").trim()
  if (!trimmed) return items
  var capitalized = capitalizeFirst(trimmed)
  return items.map(function(t) { return t.id === id ? Object.assign({}, t, { text: capitalized }) : t })
}

// Later goes on top, so the newest thought is the first one you see.
function moveToLater(tasks, later, id) {
  var index = tasks.findIndex(function(t) { return t.id === id })
  if (index < 0) return null
  var item = Object.assign({}, tasks[index])
  delete item.group
  return { tasks: tasks.filter(function(t) { return t.id !== id }), later: [item].concat(later) }
}

// Back into Today at the bottom, only into a free slot. It counts as added
// today: picking it again is a fresh decision.
function pullFromLater(tasks, later, id) {
  if (tasks.length >= TODAY_CAP) return null
  var index = later.findIndex(function(t) { return t.id === id })
  if (index < 0) return null
  // Picked for today: it leaves its Later group.
  var item = Object.assign({}, later[index], { addedOn: dayKey(Date.now()) })
  delete item.group
  return { tasks: tasks.concat([item]), later: later.filter(function(t) { return t.id !== id }) }
}

function removeItem(items, id) {
  return items.filter(function(t) { return t.id !== id })
}

function addStep(tasks, id, text) {
  var trimmed = String(text || "").trim()
  if (!trimmed) return null
  var hit = tasks.find(function(t) { return t.id === id })
  if (!hit || (hit.steps || []).length >= STEP_CAP) return null
  return tasks.map(function(t) {
    return t.id === id ? Object.assign({}, t, { steps: (t.steps || []).concat([{ text: capitalizeFirst(trimmed), done: false }]) }) : t
  })
}

function toggleStep(tasks, id, index) {
  return tasks.map(function(t) {
    if (t.id !== id) return t
    return Object.assign({}, t, { steps: (t.steps || []).map(function(s, i) { return i === index ? { text: s.text, done: !s.done } : s }) })
  })
}

function removeStep(tasks, id, index) {
  return tasks.map(function(t) {
    return t.id === id ? Object.assign({}, t, { steps: (t.steps || []).filter(function(s, i) { return i !== index }) }) : t
  })
}

// Priority is just list order; quick start moves a task to the top.
function moveToTop(tasks, id) {
  var index = tasks.findIndex(function(t) { return t.id === id })
  if (index <= 0) return tasks
  return [tasks[index]].concat(tasks.slice(0, index), tasks.slice(index + 1))
}

// ---- History ---------------------------------------------------------------
//
// Counts only ({ "2026-11-25": 3 }) — no task names, so the history file
// says how much got done, never what.

// Tasks finished per day, for the dot strip. Counts only, no names.
function parseDoneCounts(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    var done = parsed && parsed.done && typeof parsed.done === "object" ? parsed.done : {}
    var clean = {}
    for (var k in done) {
      if (/^\d{4}-\d{2}-\d{2}$/.test(k) && typeof done[k] === "number" && done[k] > 0) clean[k] = Math.round(done[k])
    }
    return clean
  } catch (e) {
    return {}
  }
}

function bumpDone(counts, now, delta) {
  var next = {}
  for (var k in counts) next[k] = counts[k]
  var key = dayKey(now)
  next[key] = Math.max(0, (next[key] || 0) + delta)
  if (!next[key]) delete next[key]
  return next
}

function serializeHistory(doneCounts) {
  return JSON.stringify({ version: 3, done: doneCounts || {} }, null, 2) + "\n"
}

// The dot strip: 26 weeks, one column per week (Monday on top), the
// current week last. Each cell is a shade 0-3 by tasks finished that day
// (0, 1, 2, 3+), -1 for days that haven't happened yet.
var STRIP_WEEKS = 26

// Today's square is at least as full as today's finished list, so tasks
// done before the counts existed (or on another machine) still show.
function withToday(counts, doneToday, now) {
  var next = {}
  for (var k in counts) next[k] = counts[k]
  var key = dayKey(now)
  next[key] = Math.max(next[key] || 0, doneToday)
  return next
}

function dotStrip(counts, now) {
  var d = new Date(now)
  var monday = new Date(d.getFullYear(), d.getMonth(), d.getDate() - (d.getDay() + 6) % 7)
  var start = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() - (STRIP_WEEKS - 1) * 7)
  var todayKey = dayKey(now)
  var cells = []
  for (var i = 0; i < STRIP_WEEKS * 7; i++) {
    var day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
    var key = dayKey(day.getTime())
    var n = counts[key] || 0
    cells.push({ level: key > todayKey ? -1 : Math.min(3, n), today: key === todayKey, key: key, count: n })
  }
  return cells
}

function expandHome(path, home) {
  var p = String(path || "").trim()
  if (p === "~") return home
  if (p.indexOf("~/") === 0) return home + p.slice(1)
  return p
}
