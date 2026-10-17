.pragma library

function generateId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

// Fixed on purpose: 90 minutes of focus earns a break, and only a real
// 5-minute stretch away counts as one.
var FOCUS_LIMIT_SECONDS = 90 * 60
var BREAK_MS = 5 * 60 * 1000
// How long you have to be back at the keyboard (timer paused, break already
// taken) before the bar starts hinting that the timer isn't running.
var NUDGE_ACTIVE_MS = 2 * 60 * 1000

function validTask(t) {
  return t && typeof t.id === "string" && typeof t.text === "string"
}

function validDone(d) {
  return d && typeof d.id === "string" && typeof d.text === "string" && typeof d.completedAt === "number"
}

function secondsOf(item) {
  return item && typeof item.seconds === "number" && item.seconds > 0 ? Math.round(item.seconds) : 0
}

function cleanTask(t) {
  return { id: t.id, text: t.text, seconds: secondsOf(t) }
}

function cleanDone(d) {
  return { id: d.id, text: d.text, completedAt: d.completedAt, seconds: secondsOf(d) }
}

function cleanParked(p) {
  return { id: p.id, text: p.text, seconds: secondsOf(p), parkedAt: typeof p.parkedAt === "number" ? p.parkedAt : Date.now() }
}

function validTimer(t) {
  return t && typeof t.taskId === "string" && typeof t.startedAt === "number" && typeof t.lastBeat === "number"
}

function emptyFocus() {
  return { seconds: 0, breakSince: 0, alerted: false, nudgeDismissed: false }
}

function cleanFocus(f) {
  if (!f || typeof f !== "object") return emptyFocus()
  return {
    seconds: typeof f.seconds === "number" && f.seconds > 0 ? Math.round(f.seconds) : 0,
    breakSince: typeof f.breakSince === "number" && f.breakSince > 0 ? f.breakSince : 0,
    alerted: f.alerted === true,
    nudgeDismissed: f.nudgeDismissed === true
  }
}

// Only the first character — never force-lowercases the rest, so acronyms
// and proper nouns ("BIOS settings") survive intact.
function capitalizeFirst(text) {
  return text.charAt(0).toUpperCase() + text.slice(1)
}

function startOfToday() {
  var now = new Date()
  return new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
}

// "Recently done" means done today — cleared at local midnight rather than
// a rolling 24h window, so it never blends into yesterday no matter what
// time you check. Pruning happens wherever state is read or written rather
// than on a tight timer, since there's never more than 3 entries to scan.
function pruneDone(done) {
  var cutoff = startOfToday()
  return done.filter(function(d) { return d.completedAt >= cutoff })
}

function parseState(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    var tasks = Array.isArray(parsed && parsed.tasks) ? parsed.tasks.filter(validTask).slice(0, 3).map(cleanTask) : []
    var done = Array.isArray(parsed && parsed.done) ? pruneDone(parsed.done.filter(validDone)).slice(0, 3).map(cleanDone) : []
    var parked = Array.isArray(parsed && parsed.parked) ? parsed.parked.filter(validTask).slice(0, PARK_CAP).map(cleanParked) : []
    var timer = validTimer(parsed && parsed.timer) ? parsed.timer : null
    // A timer for a task that no longer exists can't be credited anywhere.
    if (timer && !tasks.some(function(t) { return t.id === timer.taskId })) timer = null
    return { tasks: tasks, done: done, parked: parked, timer: timer, focus: cleanFocus(parsed && parsed.focus) }
  } catch (e) {
    return { tasks: [], done: [], parked: [], timer: null, focus: emptyFocus() }
  }
}

function serializeState(tasks, done, parked, timer, focus) {
  return JSON.stringify({
    version: 3,
    tasks: tasks,
    done: done,
    parked: parked || [],
    timer: timer || null,
    focus: focus || emptyFocus()
  }, null, 2) + "\n"
}

// Capped at 3: the slot is the feature. A 4th task forces a decision about
// one of the existing three instead of just piling on.
function addTask(tasks, text) {
  var trimmed = String(text || "").trim()
  if (!trimmed || tasks.length >= 3) return tasks
  return tasks.concat([{ id: generateId(), text: capitalizeFirst(trimmed) }])
}

// Moves a task out of the active list and into the done log with a
// timestamp, rather than deleting it outright. Kept to the 3 most recent —
// otherwise a day with a lot of completions would make the done list grow
// past the active list it's supposed to sit quietly beneath.
function completeTask(tasks, done, id) {
  var index = tasks.findIndex(function(t) { return t.id === id })
  if (index < 0) return { tasks: tasks, done: done }
  var task = tasks[index]
  var nextTasks = tasks.filter(function(t) { return t.id !== id })
  var nextDone = [{ id: task.id, text: task.text, completedAt: Date.now(), seconds: secondsOf(task) }].concat(done).slice(0, 3)
  return { tasks: nextTasks, done: nextDone }
}

function clearDone(done, id) {
  return done.filter(function(d) { return d.id !== id })
}

// Undo for a misclick on "done". No-op if all 3 active slots are full —
// restoring doesn't bump an existing task, it just isn't possible until one
// frees up.
function restoreTask(tasks, done, id) {
  if (tasks.length >= 3) return { tasks: tasks, done: done }
  var index = done.findIndex(function(d) { return d.id === id })
  if (index < 0) return { tasks: tasks, done: done }
  var entry = done[index]
  var nextDone = done.filter(function(d) { return d.id !== id })
  var nextTasks = tasks.concat([{ id: entry.id, text: entry.text, seconds: secondsOf(entry) }])
  return { tasks: nextTasks, done: nextDone }
}

function updateTaskText(tasks, id, text) {
  var trimmed = String(text || "").trim()
  if (!trimmed) return tasks
  var capitalized = capitalizeFirst(trimmed)
  return tasks.map(function(t) { return t.id === id ? { id: t.id, text: capitalized, seconds: secondsOf(t) } : t })
}

// One bench seat, never expiring. Parking frees a slot when something
// urgent comes up without throwing the bumped task away — but only one can
// sit there, so it stays an exception rather than becoming a backlog under
// another name.
var PARK_CAP = 1

function parkTask(tasks, parked, id) {
  if (parked.length >= PARK_CAP) return { tasks: tasks, parked: parked }
  var index = tasks.findIndex(function(t) { return t.id === id })
  if (index < 0) return { tasks: tasks, parked: parked }
  var task = tasks[index]
  return {
    tasks: tasks.filter(function(t) { return t.id !== id }),
    parked: parked.concat([{ id: task.id, text: task.text, seconds: secondsOf(task), parkedAt: Date.now() }])
  }
}

// Same rule as restoring a done task: only into a free slot, at the bottom.
function unparkTask(tasks, parked, id) {
  if (tasks.length >= 3) return { tasks: tasks, parked: parked }
  var index = parked.findIndex(function(p) { return p.id === id })
  if (index < 0) return { tasks: tasks, parked: parked }
  var entry = parked[index]
  return {
    tasks: tasks.concat([{ id: entry.id, text: entry.text, seconds: secondsOf(entry) }]),
    parked: parked.filter(function(p) { return p.id !== id })
  }
}

function clearParked(parked, id) {
  return parked.filter(function(p) { return p.id !== id })
}

// Priority is just list order. Moving up swaps a task with the one directly
// above it, one step at a time.
function moveTaskUp(tasks, id) {
  var index = tasks.findIndex(function(t) { return t.id === id })
  if (index <= 0) return tasks
  var copy = tasks.slice()
  var above = copy[index - 1]
  copy[index - 1] = copy[index]
  copy[index] = above
  return copy
}

// ---- Timer -----------------------------------------------------------------
//
// Only one session runs at a time, always on the top task. Ending a session
// credits its time to three places at once: the task's own total, the
// per-day history, and the current focus streak.

// The focus streak only resets after a real break: 5+ continuous minutes
// with nothing running. A 4-minute pause carries the streak straight on.
function breakTaken(timer, focus, now) {
  return !timer && focus.breakSince > 0 && now - focus.breakSince >= BREAK_MS
}

function liveSeconds(timer, now) {
  return timer ? Math.max(0, Math.round((now - timer.startedAt) / 1000)) : 0
}

function focusSeconds(timer, focus, now) {
  if (breakTaken(timer, focus, now)) return 0
  return focus.seconds + liveSeconds(timer, now)
}

function startSession(tasks, timer, focus, now) {
  if (timer || tasks.length === 0) return null
  var nextFocus = breakTaken(timer, focus, now)
    ? emptyFocus()
    : { seconds: focus.seconds, breakSince: 0, alerted: focus.alerted, nudgeDismissed: false }
  return { timer: { taskId: tasks[0].id, startedAt: now, lastBeat: now }, focus: nextFocus }
}

// `end` is normally now, but after sleep or a crash it's the last heartbeat —
// the moment the machine was last known to be awake.
function stopSession(tasks, days, timer, focus, end) {
  if (!timer) return { tasks: tasks, days: days, timer: null, focus: focus }
  var stop = Math.max(timer.startedAt, end)
  var elapsed = Math.round((stop - timer.startedAt) / 1000)
  var nextTasks = tasks.map(function(t) {
    return t.id === timer.taskId ? { id: t.id, text: t.text, seconds: secondsOf(t) + elapsed } : t
  })
  return {
    tasks: nextTasks,
    days: addSpan(days, timer.startedAt, stop),
    timer: null,
    focus: { seconds: focus.seconds + elapsed, breakSince: stop, alerted: focus.alerted, nudgeDismissed: false }
  }
}

// ---- History ---------------------------------------------------------------
//
// Daily totals only ({ "2026-10-16": seconds }) — no task names, so the
// history file says how much you worked, never on what.

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

function dayKey(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

// Splits at local midnight, so a session from 23:30 to 00:45 counts 30 min
// toward one day and 45 toward the next.
function addSpan(days, start, end) {
  var next = {}
  for (var k in days) next[k] = days[k]
  var cursor = start
  while (cursor < end) {
    var d = new Date(cursor)
    var midnight = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime()
    var chunkEnd = Math.min(end, midnight)
    var key = dayKey(cursor)
    next[key] = (next[key] || 0) + Math.round((chunkEnd - cursor) / 1000)
    cursor = chunkEnd
  }
  return next
}

function parseHistory(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    var days = parsed && parsed.days && typeof parsed.days === "object" ? parsed.days : {}
    var clean = {}
    for (var k in days) {
      if (/^\d{4}-\d{2}-\d{2}$/.test(k) && typeof days[k] === "number" && days[k] > 0) clean[k] = Math.round(days[k])
    }
    return clean
  } catch (e) {
    return {}
  }
}

function serializeHistory(days) {
  return JSON.stringify({ version: 1, days: days }, null, 2) + "\n"
}

var PERIODS = ["today", "week", "month", "year"]

function periodStart(period, now) {
  var d = new Date(now)
  if (period === "week") {
    // Weeks start on Monday.
    var sinceMonday = (d.getDay() + 6) % 7
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() - sinceMonday).getTime()
  }
  if (period === "month") return new Date(d.getFullYear(), d.getMonth(), 1).getTime()
  if (period === "year") return new Date(d.getFullYear(), 0, 1).getTime()
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

// Recorded days plus whatever part of a running session falls in the period.
function periodSeconds(days, timer, period, now) {
  var start = periodStart(period, now)
  var fromKey = dayKey(start)
  var total = 0
  for (var k in days) if (k >= fromKey) total += days[k]
  if (timer) total += Math.max(0, Math.round((now - Math.max(timer.startedAt, start)) / 1000))
  return total
}

function formatDuration(seconds) {
  var minutes = Math.floor(seconds / 60)
  if (minutes < 1) return seconds > 0 ? "<1m" : "0m"
  var h = Math.floor(minutes / 60)
  var m = minutes % 60
  if (h === 0) return m + "m"
  return m === 0 ? h + "h" : h + "h " + m + "m"
}

// ---- Multi-monitor ---------------------------------------------------------
//
// The bar (and so this plugin) exists once per screen, but only one copy may
// run the heartbeat, lock check and notification — otherwise a second
// monitor would double every notification. This file is a .pragma library,
// so this variable is shared by all copies. A leader that stops checking in
// (destroyed without cleanup, e.g. on hot reload) is replaced after 30s.
var _leader = null

function claimLeader(token, now) {
  if (!_leader || _leader.token === token || now - _leader.seen > 30000) _leader = { token: token, seen: now }
  return _leader.token === token
}

function releaseLeader(token) {
  if (_leader && _leader.token === token) _leader = null
}
