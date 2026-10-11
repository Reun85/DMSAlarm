# dankClock

A [DankMaterialShell](https://danklinux.com) bar plugin with four time tools in
one pill: a **pomodoro** (the default view), **countdown timers**, a
**stopwatch** and **alarms**. It is meant to sit in the bar's center section next
to the built-in clock, which it does not replace.

| Surface | What it does |
|---|---|
| **Bar pill** | Idle: an icon. Running: the most important thing's countdown, with a thin progress line. Ringing: pulses; left-click dismisses, right-click snoozes. Otherwise left-click opens the popout, right-click starts/pauses the pomodoro. |
| **Popout** | Ringing banner on top, then tabs: Pomodoro · Timer · Stopwatch · Alarms. |
| **Control Center tile** | Pomodoro toggle, with the full ring and controls in the detail panel. |
| **IPC** | Everything scriptable from a terminal or compositor binding. |

## Features

- **Pomodoro**: focus / short break / long break, long break after N sessions.
  Every length is adjustable in the popout and takes effect immediately, even
  mid-phase (elapsed time is kept). There are auto-start toggles for breaks and
  focus, optional Do Not Disturb while focusing, and a 7-day history of
  completed sessions.
- **Timers**: any number at once, each with an optional label, pause/resume
  and +1 min. Clicking a preset chip starts it; right-clicking removes it, and
  the bookmark button saves the composed duration as a new preset.
- **Stopwatch**: centisecond display and laps, with the fastest and slowest lap
  marked.
- **Alarms**: one-shot or repeating on chosen weekdays (Weekdays, Weekends and
  Every day are one click), with labels and snooze. "Rings in …" previews are
  shown while editing.
- **Alerts**: a looping sound and a DMS toast. The sound stops on dismiss, or by
  itself after `ringTimeoutS`; the pill keeps pulsing until you deal with it.
  Pomodoro phase changes play a single chime instead.
- **Restart-proof**: everything is stored as absolute timestamps, so timers, the
  stopwatch and the pomodoro carry on correctly across a shell restart or a
  suspend. An alarm or timer that came due while the shell was down rings if it
  is at most `missedGraceMin` late; anything older gets a "missed" toast.

## Install

### Development (symlink)

```bash
devenv shell
ck-link      # symlink ./dankClock into ~/.config/DankMaterialShell/plugins and enable it
ck-reload    # reload / rescan / restart, chosen from git status
ck-logs      # journalctl --user -u dms -f
```

Then add the widget in *Settings → Appearance → DankBar Layout → Center*, right
after **Clock**. If home-manager owns `settings.json` (a read-only store
symlink), that placement only lasts for the session; declare it as described
below.

### NixOS / home-manager (flake input)

```nix
# flake.nix
inputs.dank-clock = {
  url = "github:<you>/dankClock";   # or "path:/home/reun/SYNC/projects/dankClock"
  inputs.nixpkgs.follows = "nixpkgs";
};
```

```nix
# home-manager
{ inputs, ... }: {
  imports = [ inputs.dank-clock.homeManagerModules.default ];

  programs.dankClock = {
    enable = true;
    # Optional; every key and default is in dankClock/Config.js.
    settings = {
      workMin = 50;
      shortBreakMin = 10;
    };
  };

  # Placement belongs to your bar config: add dankClock after "clock".
  # programs.dank-material-shell.settings.barConfigs = [{
  #   centerWidgets = [ "music" "clock" { id = "dankClock"; enabled = true; } "weather" ... ];
  # }];
}
```

The module sets `programs.dank-material-shell.plugins.dankClock` (`enable`, `src`,
`settings`) and adds `pipewire` for `pw-play`; turn that off with
`installSoundDeps = false`. The flake also exports `packages.<system>.default`
(the plugin directory itself) if you would rather wire `src` up yourself.
`nix flake check` runs the logic fixtures.

## Settings vs. what you change in the popout

On a home-manager setup `plugin_settings.json` is read-only, so nothing typed in
the settings page persists. dankClock therefore keeps everything you edit in the
popout — pomodoro lengths and toggles, timer presets, alarms, running timers,
history — in DMS **plugin state**
(`~/.local/state/DankMaterialShell/plugins/dankClock_state.json`), which is
writable.

Plugin settings, from the settings page or `programs.dankClock.settings`, are the
**defaults** underneath. A popout edit wins over them. The ↺ button on the
pomodoro's *Adjust* card drops those edits so the configured values apply again.

| Setting | Default | Notes |
|---|---|---|
| `workMin` / `shortBreakMin` / `longBreakMin` | `25` / `5` / `15` | minutes |
| `cyclesBeforeLongBreak` | `4` | |
| `autoStartBreaks` / `autoStartWork` | `false` / `false` | |
| `dndDuringWork` | `false` | only turns DND off again if it turned it on |
| `timerPresets` | `"1,5,10,15,25,60"` | minutes, comma-separated |
| `snoozeMin` | `9` | |
| `missedGraceMin` | `5` | how late a missed alarm may still ring |
| `soundFile` | `"alarm"` | looped while ringing; see *Sounds* |
| `chimeFile` | `"chime"` | pomodoro phase change, played once |
| `soundVolume` | `100` | percent, up to 150 |
| `ringTimeoutS` | `60` | the sound stops by itself after this |
| `barIdle` | `"icon"` | `icon`, `pomodoro` (shows its length) or `nextAlarm` (within 24 h) |
| `barPriority` | `"ringing,pomodoro,timer,stopwatch"` | what the pill shows when several things run |
| `showProgressInBar` | `true` | |
| `use24h` | `true` | |
| `toasts` | `true` | |

## Sounds

`alarm` and `chime` are bundled. They come from KDE's Ocean sound theme
(CC-BY-SA-4.0, see `dankClock/sounds/README.md`), so they work without any
sound theme installed. Other values:

- `bell`, `phone-incoming-call`, …: a freedesktop sound name
- `ocean/bell`, `oxygen/alarm-clock-elapsed`: `<theme>/<name>` from any
  installed theme
- `/path/to/file.ogg`: an absolute path
- `""`: silent

Playback goes through `dankClock/scripts/ck-sound.sh` using `pw-play`, with
`paplay` as the fallback. If neither is available, or the sound file is
missing, you get one warning toast and the plugin carries on silently.

## IPC

```bash
dms ipc call dankClock status                      # tab-separated, one line per active thing
dms ipc call dankClock pomodoro start|pause|toggle|skip|reset
dms ipc call dankClock timer 25m                   # 90s, 5m, 1h30m, 1:30, or a bare number (minutes)
dms ipc call dankClock timerNamed 10m tea
dms ipc call dankClock cancelTimers
dms ipc call dankClock stopwatch toggle|lap|reset
dms ipc call dankClock alarm 7:30                  # one-shot; 19:05 and 7pm also work
dms ipc call dankClock alarmNamed 7:30 "Stand-up"
dms ipc call dankClock removeAlarm 7:30
dms ipc call dankClock dismiss                     # everything ringing
dms ipc call dankClock snooze                      # alarm: snoozeMin, timer: +1 min
```

Quickshell IPC needs an exact argument count, which is why the labelled
variants are separate functions.

## How it works

```
Clock.js / Config.js      pure logic, no QML: formatting, parsing, timers, stopwatch,
                          the pomodoro state machine, alarm scheduling, settings
        ▲                 (unit-tested under node, DST included)
ClockService.qml          pragma Singleton (./qmldir): all state, one tick, persistence,
                          ringing, sound process
        ▲
ClockDaemon.qml           daemon surface: wakes the lazy singleton, hosts IPC
ClockBarWidget.qml        pill + popout + Control Center tile
ClockPopout.qml           RingingBanner + DankTabBar + the four tabs
  PomodoroTab / TimerTab / StopwatchTab / AlarmsTab (+ AlarmEditor)
  ProgressRing / TimeStepper / Card   presentational helpers
scripts/ck-sound.sh       resolve a sound name, play once or loop until killed
```

- **One owner.** The bar pill exists per bar and per screen; state kept there
  would ring every alarm once per monitor. The singleton is one instance per
  QML engine, and the daemon keeps it alive even with no pill placed.
- **Timestamps, not counters.** A running timer is `endsAt`; a paused one is
  `remainingMs`. Nothing is decremented per tick, so nothing drifts, and a
  restart picks up where it left off. The tick runs at 4 Hz while something is
  counting and 1 Hz otherwise; the stopwatch view adds a 30 Hz repaint only
  while it is on screen.
- **Alarms by window.** Each tick asks "did an occurrence fall in (last tick,
  now]?" rather than "is it 07:30 now?". That catches the minute even across a
  suspend, and the same check on startup (from the persisted last tick) finds
  alarms missed while the shell was down. Occurrences are built from local date
  fields, so 07:00 stays 07:00 across DST changes.

### Reload rules

| Changed | Needed |
|---|---|
| `*.qml`, `*.js` | `dms ipc call plugins reload dankClock` |
| `plugin.json` | `dms ipc call plugin-scan rescan dankClock` |
| files added/removed, or `ClockService.qml` | **full shell restart** (`ck-reload restart`) |

The reason is the same as in dankSyncthing. A plugin reload neither
re-registers a `pragma Singleton` nor invalidates Qt's directory listing, so a
new file or an edited singleton is invisible until the engine restarts.
`ck-reload` picks the right mode from `git status`.

## Development

```bash
ck-test    # Clock.js / Config.js fixtures under node (TZ pinned to Europe/Budapest for the DST cases)
ck-lint    # qmllint through a shadow qs.* import tree, plus shellcheck
ck-fmt     # qmlformat -i
```

## License

MIT, see [LICENSE](LICENSE). The bundled sounds in `dankClock/sounds/` are
CC-BY-SA-4.0.
