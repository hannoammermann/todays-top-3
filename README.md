# Today's Top 3

An [Omarchy](https://omarchy.org/) status-bar widget for a daily task list capped at three active items on purpose. No backlog, no history, no chat, no Eisenhower matrix — just three slots, a quick-add field, and a terminal-flavored completion animation.

## Why capped at 3

A fourth task doesn't get queued — it can't be added until you finish, drop, or reorder one of the existing three. The cap is the feature: it forces the tradeoff decision instead of letting the list grow the way every other to-do app does.

## What it does

- Bar shows three pips (●●○) — filled slots vs. free ones. No task text in the bar itself.
- Click to open: add a task, mark one done (with a terminal `[ OK ]` tag animation), reorder by promoting any task to the top, or edit a task's text in place.
- Completed tasks sit in a collapsed "recently done" line below the list, expandable on click, and auto-expire daily at local midnight.
- Everything is local — no network calls, no AI, no telemetry.

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
