.pragma library

// Single source of truth for plugin settings.
//
// Every surface (bar widget, Control Center card, daemon, settings page) reads
// its defaults from this table, so they cannot drift apart. ClockSettings.qml
// takes its `defaultValue`s from here too.
//
// These are *defaults*. Durations, presets and alarms edited in the popout are
// stored in plugin state (see ClockService.qml), because on a home-manager
// setup plugin_settings.json is a read-only store symlink and nothing typed in
// the settings page would persist.
var DEFAULTS = {
    // --- Pomodoro -----------------------------------------------------------
    workMin: 25,
    shortBreakMin: 5,
    longBreakMin: 15,
    cyclesBeforeLongBreak: 4,
    autoStartBreaks: false,
    autoStartWork: false,
    dndDuringWork: false,

    // --- Timer --------------------------------------------------------------
    timerPresets: "1,5,10,15,25,60",   // minutes, comma-separated

    // --- Alarms -------------------------------------------------------------
    snoozeMin: 9,
    missedGraceMin: 5,

    // --- Sound --------------------------------------------------------------
    // "alarm" and "chime" are bundled (KDE Ocean, see sounds/README.md). Any
    // other bare name is a freedesktop sound ("bell"), "<theme>/<name>" picks
    // another installed theme ("ocean/bell"), and an absolute path is used
    // as-is. "" disables the sound.
    soundFile: "alarm",
    chimeFile: "chime",
    soundVolume: 100,          // percent
    ringTimeoutS: 60,          // stop ringing on its own after this long

    // --- Bar ----------------------------------------------------------------
    barIdle: "icon",           // "icon" | "nextAlarm" | "pomodoro"
    barPriority: "ringing,pomodoro,timer,stopwatch",
    showProgressInBar: true,
    use24h: true,

    // --- Notifications ------------------------------------------------------
    toasts: true
};

// Bounds for numeric settings. Anything outside is clamped rather than
// rejected, so a fat-fingered home-manager value still yields a working plugin.
var RANGES = {
    workMin: [1, 240],
    shortBreakMin: [1, 120],
    longBreakMin: [1, 240],
    cyclesBeforeLongBreak: [1, 12],
    snoozeMin: [1, 60],
    missedGraceMin: [0, 120],
    soundVolume: [0, 150],
    ringTimeoutS: [5, 600]
};

var CHOICES = {
    barIdle: ["icon", "nextAlarm", "pomodoro"]
};

function _coerce(key, raw) {
    var def = DEFAULTS[key];
    if (raw === undefined || raw === null)
        return def;
    if (typeof def === "number") {
        var n = Number(raw);
        if (!isFinite(n) || raw === "")
            return def;
        var r = RANGES[key];
        if (r)
            n = Math.min(r[1], Math.max(r[0], n));
        return Math.round(n);
    }
    if (typeof def === "boolean") {
        if (typeof raw === "boolean")
            return raw;
        if (raw === "true" || raw === 1 || raw === "1")
            return true;
        if (raw === "false" || raw === 0 || raw === "0")
            return false;
        return def;
    }
    var s = String(raw);
    if (CHOICES[key] && CHOICES[key].indexOf(s) < 0)
        return def;
    return s;
}

// Full, typed settings object from whatever pluginData holds.
function resolve(pluginData) {
    var src = pluginData || {};
    var out = {};
    for (var key in DEFAULTS)
        out[key] = _coerce(key, src[key]);
    return out;
}

// The pomodoro subset, with user overrides from plugin state layered on top.
var POMO_KEYS = ["workMin", "shortBreakMin", "longBreakMin", "cyclesBeforeLongBreak", "autoStartBreaks", "autoStartWork", "dndDuringWork"];

function pomodoroConfig(cfg, overrides) {
    var o = overrides || {};
    var out = {};
    for (var i = 0; i < POMO_KEYS.length; i++) {
        var k = POMO_KEYS[i];
        out[k] = o[k] !== undefined ? _coerce(k, o[k]) : cfg[k];
    }
    return out;
}

// "1, 5,10,abc,5,0" -> [1, 5, 10]: positive, de-duplicated, ascending minutes.
function parsePresets(csv) {
    var seen = {};
    var out = [];
    String(csv || "").split(",").forEach(function (p) {
        var n = Number(p.trim());
        if (p.trim() !== "" && isFinite(n) && n > 0 && !seen[n]) {
            seen[n] = true;
            out.push(n);
        }
    });
    return out.sort(function (a, b) {
        return a - b;
    });
}
