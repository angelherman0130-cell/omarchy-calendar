# Cronos Calendar

> **Companion plugin for [Cronos](https://github.com/angelherman0130-cell/omarchy-cronos).**
> Install Cronos first (the task manager), then this calendar reads its tasks.
> They are designed to work as a pair — no Cronos, no dots or task list.

Bar widget for Omarchy cloned from `omarchy.clock`: a date/time label (weekday
and time) that opens a month calendar popup. Days that carry pending
[Cronos](https://github.com/angelherman0130-cell/omarchy-cronos) tasks get an
accent dot, and the next tasks are listed under "CRONOS TASKS" with "Today" /
"Tomorrow" / full-date labels, overdue ones in red.

Click any day and the popup becomes a quick-add form with Cronos' own options —
title, notes, tags, deadline time (presets or custom) and the reminder set
(presets from "At deadline" to "2 weeks", plus a custom number in minutes or
hours). Tasks go straight through the Cronos service into its store, so they
appear in the Cronos panel with every rule intact.

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

![Cronos Calendar popup with task dots and agenda](docs/screenshot.png?v=1)