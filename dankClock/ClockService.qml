pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "Config.js" as Config
import "Clock.js" as Clock

// Single owner of every timer, alarm and the pomodoro.
//
// The bar pill is instantiated once per bar and per screen, so state kept in a
// surface would be duplicated per monitor and every alarm would ring once per
// screen. A plugin-local singleton (registered in ./qmldir) is one instance per
// QML engine; surfaces only bind to it and call its functions.
//
// Persistence goes through PluginService plugin *state*
// (~/.local/state/DankMaterialShell/plugins/dankClock_state.json), not plugin
// settings, because on a home-manager setup plugin_settings.json is a read-only
// store symlink. Settings provide defaults; what you change in the popout wins.
//
// Everything running is stored as absolute timestamps (see Clock.js), so a
// shell restart or a suspend resumes with the right remaining time.
Item {
    id: root

    readonly property string pluginId: "dankClock"

    // --- configuration -------------------------------------------------------
    property var cfg: Config.resolve({})
    // Pomodoro values edited in the popout; layered over cfg.
    property var pomoOverrides: ({})
    readonly property var pomoCfg: Config.pomodoroConfig(cfg, pomoOverrides)
    // null = use the settings' preset list.
    property var presetOverride: null
    readonly property var timerPresets: presetOverride !== null ? presetOverride : Config.parsePresets(cfg.timerPresets)

    // --- live state ----------------------------------------------------------
    property real now: Date.now()
    property var pomo: Clock.pomoInitial(Config.DEFAULTS)
    property var timers: []
    property var stopwatch: Clock.newStopwatch()
    property var alarms: []
    // { key, kind: "timer"|"alarm"|"pomodoro", refId, title, body, since }
    property var ringing: []
    property var history: ({})

    // Session-only UI memory: the popout reopens on the last tab, and starts on
    // the pomodoro.
    property string currentTab: "pomodoro"

    property bool ready: false
    property bool silenced: false
    property bool soundMissing: false
    property real _lastCheck: Date.now()
    property bool _dndOwned: false

    // --- derived ---------------------------------------------------------------
    readonly property bool pomoActive: pomo.status !== "idle"
    readonly property bool swActive: Clock.swRunning(stopwatch) || stopwatch.accumulatedMs > 0
    readonly property bool anyRunning: pomo.status === "running" || Clock.swRunning(stopwatch) || timers.some(t => t.status === "running")
    // Changes once a day; bind to this rather than `now` for anything daily.
    readonly property string today: Clock.dayKey(now)
    readonly property int todayPomodoros: history[today] || 0
    readonly property var activeTimers: timers.filter(t => t.status !== "done")
    readonly property var soonestTimer: {
        let best = null;
        for (const t of timers) {
            if (t.status === "done")
                continue;
            if (!best || Clock.timerRemaining(t, now) < Clock.timerRemaining(best, now))
                best = t;
        }
        return best;
    }
    readonly property var nextAlarm: Clock.nextAlarm(alarms, now)

    readonly property string scriptPath: Paths.strip(Qt.resolvedUrl("scripts/ck-sound.sh").toString().split("?")[0])

    // --- settings ----------------------------------------------------------------
    function loadSettings() {
        cfg = Config.resolve(SettingsData.getPluginSettingsForPlugin(pluginId));
        // New durations from home-manager apply to an idle or running phase the
        // same way edits in the popout do.
        pomo = Clock.pomoApplyConfig(pomo, pomoCfg, Date.now());
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.loadSettings();
        }
    }

    // --- persistence --------------------------------------------------------------
    function _load(key, fallback) {
        const v = PluginService.loadPluginState(pluginId, key, undefined);
        return v === undefined || v === null ? fallback : v;
    }

    function _save(key, value) {
        PluginService.savePluginState(pluginId, key, value);
    }

    function _saveTimers() {
        _save("timers", timers);
    }

    function _saveAlarms() {
        _save("alarms", alarms);
    }

    function _savePomo() {
        _save("pomodoro", pomo);
    }

    function _saveStopwatch() {
        _save("stopwatch", stopwatch);
    }

    function restore() {
        const t = Date.now();
        pomoOverrides = _load("pomoOverrides", {});
        presetOverride = _load("timerPresets", null);
        history = _load("history", {});
        alarms = (_load("alarms", []) || []).filter(a => a && a.id !== undefined);
        timers = (_load("timers", []) || []).filter(x => x && x.id !== undefined);
        const sw = _load("stopwatch", null);
        stopwatch = sw && sw.laps ? sw : Clock.newStopwatch();
        pomo = Clock.pomoSanitize(_load("pomodoro", null), pomoCfg);

        // Look back to the last time the shell was alive (bounded to a day) for
        // anything that came due while it was not.
        const last = Number(_load("lastCheck", 0)) || t;
        _lastCheck = Math.max(last, t - Clock.DAY);
        ready = true;
        _tick(true);
    }

    // --- tick -----------------------------------------------------------------------
    // One timer for everything. It runs fast only while something is counting, so
    // countdowns tick over on the second; otherwise 1 Hz is plenty for alarms.
    Timer {
        id: ticker
        interval: root.anyRunning ? 250 : 1000
        repeat: true
        running: root.ready
        onTriggered: root._tick(false)
    }

    // lastCheck is persisted at a slower rate; it only needs to be roughly right
    // to recognise "the shell was down at 07:00".
    Timer {
        interval: 30000
        repeat: true
        running: root.ready
        onTriggered: root._save("lastCheck", root.now)
    }

    function _tick(startup) {
        const t = Date.now();
        now = t;
        const graceMs = cfg.missedGraceMin * Clock.MINUTE;

        // Timers
        let timersChanged = false;
        const nextTimers = timers.map(x => {
            if (!Clock.timerIsDue(x, t))
                return x;
            timersChanged = true;
            const late = t - x.endsAt;
            const title = x.label || I18n.tr("Timer");
            if (startup && late > graceMs) {
                _toast(I18n.tr("Timer finished while away"), title);
            } else {
                _ring({
                    kind: "timer",
                    refId: x.id,
                    title: title,
                    body: I18n.tr("%1 timer is up").arg(Clock.fmtDuration(x.durationMs))
                });
            }
            return Clock.timerFinish(x);
        });
        if (timersChanged) {
            // Missed timers are dropped rather than left as "done" rows nobody
            // will dismiss; rung ones stay until dismissed from the banner.
            timers = nextTimers.filter(x => x.status !== "done" || ringing.some(r => r.refId === x.id));
            _saveTimers();
        }

        // Pomodoro
        if (Clock.pomoIsDue(pomo, t)) {
            const late = t - pomo.endsAt;
            const ended = pomo.phase;
            const r = Clock.pomoComplete(pomo, pomoCfg, startup ? t : pomo.endsAt);
            // Catching up after a long downtime must not leave a phase that
            // started in the past running; it waits for the user instead.
            if (startup && late > graceMs && r.state.status === "running")
                r.state = Object.assign({}, r.state, { status: "idle", endsAt: null });
            _setPomo(r.state);
            if (r.completedWork)
                _credit(t);
            if (!(startup && late > graceMs))
                _pomoAlert(ended, r.state);
        }

        // Alarms
        const due = Clock.dueAlarms(alarms, _lastCheck, t, graceMs);
        if (due.length) {
            const fired = {};
            for (const d of due) {
                fired[d.alarm.id] = true;
                const title = d.alarm.label || I18n.tr("Alarm");
                const when = Clock.fmtTimeOfDay(d.alarm.hour, d.alarm.minute, cfg.use24h);
                if (d.missed)
                    _toast(I18n.tr("Missed alarm"), title + " · " + when);
                else
                    _ring({
                        kind: "alarm",
                        refId: d.alarm.id,
                        title: title,
                        body: when
                    });
            }
            alarms = alarms.map(a => fired[a.id] ? Clock.alarmAfterFire(a) : a);
            _saveAlarms();
        }
        _lastCheck = t;
    }

    // --- ringing ------------------------------------------------------------------
    function _ring(item) {
        const entry = Object.assign({
            key: Clock.makeId("ring", Date.now()),
            since: Date.now()
        }, item);
        // One ring per source: a re-fire replaces the previous banner.
        ringing = ringing.filter(r => r.refId !== item.refId).concat([entry]);
        silenced = false;
        ringTimeout.restart();
        _toast(item.title, item.body);
    }

    function _toast(title, body) {
        if (cfg.toasts)
            ToastService.showInfo(title, body || "");
    }

    function _unring(key) {
        const r = ringing.find(x => x.key === key);
        ringing = ringing.filter(x => x.key !== key);
        return r;
    }

    function dismiss(key) {
        const r = _unring(key);
        if (r && r.kind === "timer") {
            timers = timers.filter(t => t.id !== r.refId);
            _saveTimers();
        }
    }

    function dismissAll() {
        for (const r of ringing.slice())
            dismiss(r.key);
    }

    // Alarm: snooze for snoozeMin. Timer: +1 minute. Pomodoro: start the next phase.
    function snooze(key) {
        const r = _unring(key);
        if (!r)
            return;
        const t = Date.now();
        if (r.kind === "alarm") {
            alarms = alarms.map(a => a.id === r.refId ? Clock.alarmSnooze(a, t, cfg.snoozeMin * Clock.MINUTE) : a);
            _saveAlarms();
            _toast(I18n.tr("Snoozed"), I18n.tr("%1 minutes").arg(cfg.snoozeMin));
        } else if (r.kind === "timer") {
            timerAddTime(r.refId, Clock.MINUTE);
        } else if (r.kind === "pomodoro") {
            pomoStart();
        }
    }

    function snoozeAll() {
        for (const r of ringing.slice())
            snooze(r.key);
    }

    function silence() {
        silenced = true;
    }

    Timer {
        id: ringTimeout
        interval: root.cfg.ringTimeoutS * 1000
        onTriggered: root.silenced = true
    }

    // The looping alarm sound. Bound to the ringing list: it starts with the first
    // ring and stops (the script kills its player on TERM) when the last one is
    // dismissed or the timeout silences it.
    Process {
        id: ringSound
        running: root.ringing.length > 0 && !root.silenced && root.cfg.soundFile !== ""
        command: [root.scriptPath, root.cfg.soundFile, String(root.cfg.soundVolume), "1"]
        // The helper prints "ck-sound: …" to stderr when the file or the player
        // is missing. Say so once instead of failing silently on every ring.
        // (Read from stderr rather than onExited: qmllint cannot resolve the
        // QProcess::ExitStatus parameter of Quickshell's exited signal.)
        stderr: StdioCollector {
            onStreamFinished: {
                const msg = text.trim();
                if (msg.indexOf("ck-sound:") >= 0 && !root.soundMissing) {
                    root.soundMissing = true;
                    ToastService.showWarning(I18n.tr("dankClock: cannot play sound"), msg);
                }
            }
        }
    }

    function _chime() {
        if (cfg.chimeFile !== "")
            Quickshell.execDetached([scriptPath, cfg.chimeFile, String(cfg.soundVolume), "0"]);
    }

    function _pomoAlert(endedPhase, next) {
        const title = endedPhase === "work" ? I18n.tr("Focus session complete") : I18n.tr("Break over");
        const body = next.status === "running" ? I18n.tr("%1 started · %2").arg(Clock.phaseLabel(next.phase)).arg(Clock.fmtDuration(next.totalMs)) : I18n.tr("Next: %1 · %2").arg(Clock.phaseLabel(next.phase)).arg(Clock.fmtDuration(next.totalMs));
        _chime();
        _toast(title, body);
    }

    // --- pomodoro ------------------------------------------------------------------
    function _setPomo(next) {
        pomo = next;
        _savePomo();
        _syncDnd();
    }

    function _syncDnd() {
        const want = pomoCfg.dndDuringWork && pomo.phase === "work" && pomo.status === "running";
        if (want && !SessionData.doNotDisturb) {
            SessionData.setDoNotDisturb(true);
            _dndOwned = true;
        } else if (!want && _dndOwned) {
            // Only undo DND that this plugin turned on.
            SessionData.setDoNotDisturb(false);
            _dndOwned = false;
        }
    }

    function _credit(t) {
        const key = Clock.dayKey(t);
        const next = Object.assign({}, history);
        next[key] = (next[key] || 0) + 1;
        // Keep a month; the UI shows a week.
        const cutoff = Clock.dayKey(t - 31 * Clock.DAY);
        for (const k in next)
            if (k < cutoff)
                delete next[k];
        history = next;
        _save("history", history);
    }

    function pomoStart() {
        _setPomo(Clock.pomoStart(pomo, Date.now()));
    }

    function pomoPause() {
        _setPomo(Clock.pomoPause(pomo, Date.now()));
    }

    function pomoToggle() {
        _setPomo(Clock.pomoToggle(pomo, Date.now()));
    }

    function pomoSkip() {
        _setPomo(Clock.pomoSkip(pomo, pomoCfg, Date.now()).state);
    }

    function pomoReset() {
        _setPomo(Clock.pomoReset(pomoCfg));
    }

    function setPomoValue(key, value) {
        const next = Object.assign({}, pomoOverrides);
        next[key] = value;
        pomoOverrides = next;
        _save("pomoOverrides", pomoOverrides);
        _setPomo(Clock.pomoApplyConfig(pomo, pomoCfg, Date.now()));
    }

    // Drops popout edits so the settings / home-manager values apply again.
    function resetPomoConfig() {
        pomoOverrides = {};
        _save("pomoOverrides", pomoOverrides);
        _setPomo(Clock.pomoApplyConfig(pomo, pomoCfg, Date.now()));
    }

    function pomoHistory(days) {
        const out = [];
        const t = Date.now();
        for (let i = days - 1; i >= 0; i--) {
            const d = new Date(t - i * Clock.DAY);
            out.push({
                key: Clock.dayKey(d),
                label: i === 0 ? I18n.tr("Today") : Clock.DAY_SHORT[d.getDay()],
                count: history[Clock.dayKey(d)] || 0
            });
        }
        return out;
    }

    // --- timers --------------------------------------------------------------------
    function timerAdd(ms, label) {
        if (!(ms > 0))
            return null;
        const t = Date.now();
        const timer = Clock.newTimer(Clock.makeId("timer", t), ms, label || "", t);
        timers = timers.concat([timer]);
        _saveTimers();
        return timer;
    }

    function _mapTimer(id, fn) {
        timers = timers.map(x => x.id === id ? fn(x) : x);
        _saveTimers();
    }

    function timerPause(id) {
        _mapTimer(id, x => Clock.timerPause(x, Date.now()));
    }

    function timerResume(id) {
        _mapTimer(id, x => Clock.timerResume(x, Date.now()));
    }

    function timerToggle(id) {
        _mapTimer(id, x => x.status === "running" ? Clock.timerPause(x, Date.now()) : Clock.timerResume(x, Date.now()));
    }

    function timerAddTime(id, ms) {
        // +1 min on a finished timer restarts it, so it is no longer ringing.
        ringing = ringing.filter(r => r.refId !== id);
        _mapTimer(id, x => Clock.timerAddTime(x, ms, Date.now()));
    }

    function timerCancel(id) {
        ringing = ringing.filter(r => r.refId !== id);
        timers = timers.filter(x => x.id !== id);
        _saveTimers();
    }

    function setPresets(list) {
        presetOverride = list.slice().sort((a, b) => a - b);
        _save("timerPresets", presetOverride);
    }

    function addPreset(minutes) {
        if (minutes > 0 && timerPresets.indexOf(minutes) < 0)
            setPresets(timerPresets.concat([minutes]));
    }

    function removePreset(minutes) {
        setPresets(timerPresets.filter(m => m !== minutes));
    }

    // --- stopwatch -------------------------------------------------------------------
    function _setSw(next) {
        stopwatch = next;
        _saveStopwatch();
    }

    function swToggle() {
        const t = Date.now();
        _setSw(Clock.swRunning(stopwatch) ? Clock.swPause(stopwatch, t) : Clock.swStart(stopwatch, t));
    }

    function swLap() {
        _setSw(Clock.swLap(stopwatch, Date.now()));
    }

    function swReset() {
        _setSw(Clock.newStopwatch());
    }

    // --- alarms ----------------------------------------------------------------------
    function alarmAdd(hour, minute, label, days) {
        const a = {
            id: Clock.makeId("alarm", Date.now()),
            hour: hour,
            minute: minute,
            label: label || "",
            days: days || 0,
            enabled: true,
            snoozeUntil: null
        };
        alarms = Clock.sortAlarms(alarms.concat([a]));
        _saveAlarms();
        return a;
    }

    function alarmUpdate(id, patch) {
        alarms = Clock.sortAlarms(alarms.map(a => a.id === id ? Object.assign({}, a, patch) : a));
        _saveAlarms();
    }

    function alarmToggle(id) {
        const a = alarms.find(x => x.id === id);
        if (a)
            // Switching off also cancels a pending snooze.
            alarmUpdate(id, a.enabled ? {
                enabled: false,
                snoozeUntil: null
            } : {
                enabled: true
            });
    }

    function alarmRemove(id) {
        ringing = ringing.filter(r => r.refId !== id);
        alarms = alarms.filter(a => a.id !== id);
        _saveAlarms();
    }

    // --- IPC-friendly summary ----------------------------------------------------------
    function statusLine() {
        const t = Date.now();
        const parts = [];
        if (ringing.length)
            parts.push("ringing\t" + ringing.map(r => r.title).join(", "));
        parts.push("pomodoro\t" + pomo.phase + "\t" + pomo.status + "\t" + Clock.fmtDuration(Clock.pomoRemaining(pomo, t), {
            countdown: true
        }) + "\t" + todayPomodoros + " today");
        for (const x of timers)
            parts.push("timer\t" + (x.label || "-") + "\t" + x.status + "\t" + Clock.fmtDuration(Clock.timerRemaining(x, t), {
                countdown: true
            }));
        if (swActive)
            parts.push("stopwatch\t" + (Clock.swRunning(stopwatch) ? "running" : "paused") + "\t" + Clock.fmtDuration(Clock.swElapsed(stopwatch, t), {
                centis: true
            }));
        const na = Clock.nextAlarm(alarms, t);
        if (na)
            parts.push("alarm\t" + (na.alarm.label || "-") + "\t" + Clock.fmtTimeOfDay(na.alarm.hour, na.alarm.minute, true) + "\tin " + Clock.fmtHuman(na.at - t));
        return parts.join("\n");
    }

    Component.onCompleted: {
        loadSettings();
        restore();
    }

    Component.onDestruction: {
        // lastCheck is not saved here: the 30 s save is close enough, and writing
        // plugin state while the plugin is being torn down trips PluginService.
        if (_dndOwned)
            SessionData.setDoNotDisturb(false);
    }
}
