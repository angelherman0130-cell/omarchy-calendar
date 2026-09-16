# Cronos Calendar

> **Companion plugin for [Cronos](https://github.com/angelherman0130-cell/omarchy-cronos).**
> Install Cronos first (the task manager), then this calendar reads its tasks.
> They are designed to work as a pair — no Cronos, no task rows.

Bar widget for Omarchy cloned from `omarchy.clock`: a date/time label (weekday
and time) that opens a month calendar popup. Your pending
[Cronos](https://github.com/angelherman0130-cell/omarchy-cronos) tasks are shown
**inside their day's cell** like a Google Calendar month view — the day number
up top, then the tasks as tinted chips (soonest deadline first, overdue in
red, "+N more" when a day overflows). The next tasks are also listed on the
"CRONOS TASKS" agenda below with "Today" / "Tomorrow" / full-date labels.

Keeps everything from the Omarchy clock: ISO week numbers, week-start toggle
("W" heading), month stepping (chevrons, scroll wheel, keyboard), year
progress rail and the memento-mori bar.

## Install (both, in order)

```
omarchy plugin add https://github.com/angelherman0130-cell/omarchy-cronos.git --enable
omarchy plugin add https://github.com/angelherman0130-cell/omarchy-calendar.git --enable
```

First line: the **Cronos** task manager (bar slot + notifications). Second
line: this **Cronos Calendar** widget, which doubles as the date/time label.

It talks to the Cronos plugin by reading the same `tasks.json` store
(`~/.local/state/omarchy/cronos/tasks.json`), refreshed live; no IPC or extra
service needed.

## Screenshots

![Cronos Calendar popup with tasks inside each day](docs/screenshot.png?v=1)