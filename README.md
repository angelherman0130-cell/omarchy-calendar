# Cronos Calendar

Bar widget for Omarchy cloned from `omarchy.clock`: a date/time label (weekday
and time) that opens a month calendar popup. Days that carry pending
[Cronos](https://github.com/angelherman0130-cell/omarchy-cronos) tasks get an
accent dot, and the next tasks are listed under "CRONOS TASKS" with "Today" /
"Tomorrow" / full-date labels, overdue ones in red.

Keeps everything from the Omarchy clock: ISO week numbers, week-start toggle
("W" heading), month stepping (chevrons, scroll wheel, keyboard), year
progress rail and the memento-mori bar.

## Install

```
omarchy plugin add https://github.com/angelherman0130-cell/omarchy-calendar.git --enable
```

It talks to the Cronos plugin by reading the same `tasks.json` store
(`~/.local/state/omarchy/cronos/tasks.json`), refreshed live; no IPC or extra
service needed.

## Screenshots

Coming soon.