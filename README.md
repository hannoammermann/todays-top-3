# Today's Top 3

**One thing at a time, three things a day.** An [Omarchy](https://omarchy.org/) status-bar widget that puts together what to-do and Pomodoro plugins usually keep apart:

- **A hard cap of three tasks.** No backlog. A fourth can't be added until you finish or park one.
- **A timer on the top task only.** Starting work means putting that task first, so priority and focus are the same decision.
- **A break signal after 90 minutes of focus.** The bar turns red, and only a real 5-minute break resets it. No 25-minute cycles to babysit; it follows how long you actually work.

All of it lives in three dots in your bar. No chat, no Eisenhower matrix, no network.

![Today's Top 3 popover with three sample tasks, the top one timing at 1h 15m with a pause button, the add field disabled at the 3-task cap, and a footer showing today's 3h 12m alongside parked 1 · done 2](preview.png)

## Why this combination

- **The cap forces the tradeoff.** A list that can always grow never makes you choose. With three slots, adding something means deciding what it replaces, instead of letting the list pile up the way every other to-do app does.
- **The timer enforces the order.** Most timers run next to your list, not on it. Here only the top task can be timed, so you can't drift onto task #3 while telling yourself #1 is the priority. Switching means promoting it, on purpose.
- **The break signal protects the focus.** A 25-minute Pomodoro can cut a deep-work stretch short. One signal at 90 minutes lets you finish a thought and still makes you stop, and short pauses don't count as a break.

## The thinking behind it

These are research-informed defaults, not proven numbers. How solid each one is:

- **One thing at a time: strong evidence.** Switching between tasks costs time and accuracy ([Rubinstein, Meyer & Evans, 2001](https://doi.org/10.1037/0096-1523.27.4.763)), and part of your attention stays on the task you just left, called attention residue ([Leroy, 2009](https://doi.org/10.1016/j.obhdp.2009.04.002)).
- **Short breaks: good evidence.** A meta-analysis of breaks of 10 minutes or less found they reliably reduce fatigue and boost energy, with smaller effects on performance ([Albulescu et al., 2022](https://doi.org/10.1371/journal.pone.0272460)).
- **90 minutes: plausible, not proven.** It comes from Nathaniel Kleitman's basic rest-activity cycle, the idea that the ~90-minute rhythm of sleep continues through the day. That rhythm is well established during sleep, but the evidence while awake is mixed. Treat 90 as a sensible ceiling, not a biological law.
- **Three tasks: a heuristic.** No study says "three". It follows the "most important tasks" habit and the small capacity of working memory ([Cowan, 2001](https://doi.org/10.1017/S0140525X01003922)): few enough to hold in your head, enough to make real progress.

## What it does

- **Bar**: three pips (●●○) — filled slots vs. free ones. No task text, no variable width. Hover for a tooltip ("Today — 2 of 3", or the running task and its time). The pips only change colour when something needs you — see *Focus timer*.
- **Add**: type and hit Enter. Disabled with an explanatory placeholder once you're at 3 — finish or park one first, there's no overflow list to dump a 4th into.
- **Complete**: ✓ plays a brief terminal-style `[ OK ]` tag before the task leaves the list.
- **Reorder**: an up-chevron promotes any task to the top (any order is reachable in at most two clicks with 3 items). The top task doesn't get a dead, do-nothing button — the control is simply absent, not disabled.
- **Edit**: click a task's text to edit it in place. The field wraps like the display text does, so a two-line task is fully visible while you edit it instead of scrolling.
- **Focus timer**: ▶ on the top task (only the top task — one thing at a time). Each task shows its total time across every day it's been on the list, and finished tasks keep theirs in the done list.
  - Pressing play makes the top pip breathe once; there's no permanent "running" colour.
  - After **90 minutes** of focus, all three pips turn red and one notification says to take a break. Only a **5-minute** stretch with nothing running resets that — a 4-minute pause carries the streak on.
  - **Locking the screen pauses** immediately. **Sleep, crashes, and shell restarts** end the session at the last 10-second heartbeat, so time asleep is never counted.
  - If you're back at the keyboard after a break but haven't restarted, the top pip turns **amber**. Opening the panel dismisses it.
  - Promoting another task pauses the timer; the new top task waits for its own play press.
- **Park**: hover a task for a park button. It frees the slot when something urgent comes up, without throwing the task away. Only **one** task can be parked at a time and it never expires — it waits behind `parked 1` in the footer until you bring it back (↺, needs a free slot) or drop it (✕). Parking the running task pauses it.
- **Footer**: one quiet line under the input — `today · 3h 12m` on the left (click to cycle week, Monday start, month, and year; resets to today on every open), and `parked 1 · done 3` on the right. Each toggle only appears when it has something in it, and opens its list below the footer, one at a time.
- **Recently done**: collapsed by default behind `done n` in the footer — expand on click to see struck-through entries with restore (↺, mirrored `[ << ]` tag animation) and clear (✕) actions. Capped at the 3 most recent, and cleared automatically at local midnight regardless of count.
- **All clear**: finishing your last task for the day types out "All clear ✓" instead of just popping in — a slightly bigger payoff reserved for the rarer, bigger moment.
- Fully local: no network calls, no AI, no telemetry, ever.

## Data

Task state lives at `~/.local/state/omarchy/todays-top-3.json`, *not* inside this repo — so cloning, forking, or publishing this code can never expose your actual task content. The containing directory and the file itself are both locked to owner-only permissions (`700`/`600`).

Time stats live next to it in `todays-top-3-history.json` (also `600`) as daily totals only — `{ "2026-10-16": 11520 }` — with no task names, so the history records how much you worked, never on what.

## Install

```bash
omarchy plugin add https://github.com/hannoammermann/todays-top-3.git --enable
```

Or clone this repo into `~/.config/omarchy/plugins/todays-top-3/` yourself and run `omarchy plugin enable io.github.hannoammermann.todays-top-3`. Move it around the bar with `omarchy bar move`, or via `bar.layout` in `~/.config/omarchy/shell.json`.

## Remove

```bash
omarchy plugin remove io.github.hannoammermann.todays-top-3
```

That removes the plugin itself. Your tasks and time history stay behind in case you reinstall; to delete them too:

```bash
rm ~/.local/state/omarchy/todays-top-3.json ~/.local/state/omarchy/todays-top-3-history.json
```

The plugin never edits your shell or Hyprland config.

## Dependencies and permissions

Nothing to install beyond a standard Omarchy setup. Like all Omarchy plugins it runs unsandboxed as your user; this is everything it touches:

- Reads and writes only the two state files above.
- Runs `omarchy-shell lock isLocked` every 10 seconds while a timer is running, to pause when the screen locks.
- Runs `notify-send` (libnotify, included with Omarchy) once when you reach 90 minutes of focus.
- Uses Wayland idle notifications (`ext-idle-notify`, supported by Hyprland) for the "back but paused" hint.
- Reads the current theme's `colors.toml` for the amber colour.

## License

MIT — see [LICENSE](LICENSE).
