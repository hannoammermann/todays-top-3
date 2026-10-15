# Today's Top 3

An [Omarchy](https://omarchy.org/) status-bar widget for a daily task list capped at three active items on purpose. No backlog, no history, no chat, no Eisenhower matrix — just three slots, a quick-add field, and a terminal-flavored completion animation.

![Today's Top 3 popover showing three active tasks, a collapsed "recently done" line, and the add field disabled at the 3-task cap](preview.png)

## Why capped at 3

A fourth task doesn't get queued — it can't be added until you finish, drop, or reorder one of the existing three. The cap is the feature: it forces the tradeoff decision instead of letting the list grow the way every other to-do app does.

## What it does

- **Bar**: three pips (●●○) — filled slots vs. free ones, nothing else. No task text, no variable width. Hover for a tooltip ("Today — 2 of 3").
- **Add**: type and hit Enter. Disabled with an explanatory placeholder once you're at 3 — finish or remove one first, there's no overflow list to dump a 4th into.
- **Complete**: ✓ plays a brief terminal-style `[ OK ]` tag before the task leaves the list.
- **Reorder**: an up-chevron promotes any task to the top (any order is reachable in at most two clicks with 3 items). The top task doesn't get a dead, do-nothing button — the control is simply absent, not disabled.
- **Edit**: click a task's text to edit it in place. The field wraps like the display text does, so a two-line task is fully visible while you edit it instead of scrolling.
- **Recently done**: collapsed by default to a single `[+] recently done (n)` line — expand on click to see struck-through entries with restore (↺, mirrored `[ << ]` tag animation) and clear (✕) actions. Capped at the 3 most recent, and cleared automatically at local midnight regardless of count.
- **All clear**: finishing your last task for the day types out "All clear ✓" instead of just popping in — a slightly bigger payoff reserved for the rarer, bigger moment.
- Fully local: no network calls, no AI, no telemetry, ever.

## Data

Task state lives at `~/.local/state/omarchy/todays-top-3.json`, *not* inside this repo — so cloning, forking, or publishing this code can never expose your actual task content. The containing directory and the file itself are both locked to owner-only permissions (`700`/`600`).

## Install

Clone or symlink this repo into `~/.config/omarchy/plugins/todays-top-3/`, then:

```bash
omarchy plugin enable io.github.hannoammermann.todays-top-3
```

Place it in your bar via `~/.config/omarchy/shell.json`'s `bar.layout` section, or `omarchy bar move`.

## License

MIT — see [LICENSE](LICENSE).
