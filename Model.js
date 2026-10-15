.pragma library

function generateId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

function validTask(t) {
  return t && typeof t.id === "string" && typeof t.text === "string"
}

function validDone(d) {
  return d && typeof d.id === "string" && typeof d.text === "string" && typeof d.completedAt === "number"
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
    var tasks = Array.isArray(parsed && parsed.tasks) ? parsed.tasks.filter(validTask).slice(0, 3) : []
    var done = Array.isArray(parsed && parsed.done) ? pruneDone(parsed.done.filter(validDone)).slice(0, 3) : []
    return { tasks: tasks, done: done }
  } catch (e) {
    return { tasks: [], done: [] }
  }
}

function serializeState(tasks, done) {
  return JSON.stringify({ version: 2, tasks: tasks, done: done }, null, 2) + "\n"
}

// Capped at 3: the slot is the feature. A 4th task forces a decision about
// one of the existing three instead of just piling on.
function addTask(tasks, text) {
  var trimmed = String(text || "").trim()
  if (!trimmed || tasks.length >= 3) return tasks
  return tasks.concat([{ id: generateId(), text: trimmed }])
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
  var nextDone = [{ id: task.id, text: task.text, completedAt: Date.now() }].concat(done).slice(0, 3)
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
  var nextTasks = tasks.concat([{ id: entry.id, text: entry.text }])
  return { tasks: nextTasks, done: nextDone }
}

function updateTaskText(tasks, id, text) {
  var trimmed = String(text || "").trim()
  if (!trimmed) return tasks
  return tasks.map(function(t) { return t.id === id ? { id: t.id, text: trimmed } : t })
}

// Priority is just list order. Promoting moves a task to the front rather
// than swapping neighbors, so any order is reachable in at most two clicks
// with a 3-item list.
function promoteTask(tasks, id) {
  var index = tasks.findIndex(function(t) { return t.id === id })
  if (index <= 0) return tasks
  var copy = tasks.slice()
  var item = copy.splice(index, 1)[0]
  copy.unshift(item)
  return copy
}
