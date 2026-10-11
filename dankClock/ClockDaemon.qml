import QtQuick
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import "Clock.js" as Clock

// Daemon surface: instantiated exactly once while the plugin is enabled, unlike
// the bar pill which exists per bar and per screen.
//
// It wakes the lazy ClockService singleton (so alarms ring even with no pill
// placed anywhere) and owns the IPC handler.
PluginComponent {
    id: root

    IpcHandler {
        target: "dankClock"

        // Explicit return types are required, or `dms ipc` cannot see the
        // function at all.
        function status(): string {
            return ClockService.statusLine();
        }

        // start | pause | toggle | skip | reset
        function pomodoro(action: string): string {
            switch (action) {
            case "start":
                ClockService.pomoStart();
                break;
            case "pause":
                ClockService.pomoPause();
                break;
            case "":
            case "toggle":
                ClockService.pomoToggle();
                break;
            case "skip":
                ClockService.pomoSkip();
                break;
            case "reset":
                ClockService.pomoReset();
                break;
            default:
                return "usage: pomodoro start|pause|toggle|skip|reset";
            }
            const p = ClockService.pomo;
            return p.phase + "\t" + p.status;
        }

        // Quickshell IPC calls need an exact argument count, so the optional
        // label is a separate function rather than an optional parameter.
        //   dms ipc call dankClock timer 5m
        //   dms ipc call dankClock timerNamed 5m tea
        function timer(duration: string): string {
            return timerNamed(duration, "");
        }

        function timerNamed(duration: string, label: string): string {
            const ms = Clock.parseDuration(duration);
            if (ms === null)
                return "cannot parse duration: " + duration + " (try 90s, 5m, 1h30m, 1:30)";
            ClockService.timerAdd(ms, label);
            return "timer " + Clock.fmtDuration(ms) + (label ? " · " + label : "");
        }

        function cancelTimers(): string {
            const hit = ClockService.timers.slice();
            for (const t of hit)
                ClockService.timerCancel(t.id);
            return "cancelled " + hit.length;
        }

        // toggle | lap | reset
        function stopwatch(action: string): string {
            switch (action) {
            case "":
            case "toggle":
                ClockService.swToggle();
                break;
            case "lap":
                ClockService.swLap();
                break;
            case "reset":
                ClockService.swReset();
                break;
            default:
                return "usage: stopwatch toggle|lap|reset";
            }
            return Clock.fmtDuration(Clock.swElapsed(ClockService.stopwatch, Date.now()), {
                centis: true
            });
        }

        // One-shot alarms:
        //   dms ipc call dankClock alarm 7:30
        //   dms ipc call dankClock alarmNamed 7:30 "Wake up"
        function alarm(time: string): string {
            return alarmNamed(time, "");
        }

        function alarmNamed(time: string, label: string): string {
            const tod = Clock.parseTimeOfDay(time);
            if (!tod)
                return "cannot parse time: " + time + " (try 7:30, 19:05, 7pm)";
            const a = ClockService.alarmAdd(tod.hour, tod.minute, label, 0);
            const at = Clock.alarmNextFire(a, Date.now());
            return "alarm " + Clock.fmtTimeOfDay(a.hour, a.minute, true) + " in " + Clock.fmtHuman(at - Date.now());
        }

        // Removes every alarm set for that time of day.
        function removeAlarm(time: string): string {
            const tod = Clock.parseTimeOfDay(time);
            if (!tod)
                return "cannot parse time: " + time;
            const hit = ClockService.alarms.filter(a => a.hour === tod.hour && a.minute === tod.minute);
            for (const a of hit)
                ClockService.alarmRemove(a.id);
            return "removed " + hit.length;
        }

        function dismiss(): string {
            const n = ClockService.ringing.length;
            ClockService.dismissAll();
            return "dismissed " + n;
        }

        function snooze(): string {
            const n = ClockService.ringing.length;
            ClockService.snoozeAll();
            return "snoozed " + n;
        }
    }

    Component.onCompleted: {
        // Singletons are lazy; touching one property constructs it.
        console.info("dankClock: daemon started, sound helper at", ClockService.scriptPath);
    }

    Component.onDestruction: {
        console.info("dankClock: daemon stopped");
    }
}
