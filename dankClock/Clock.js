.pragma library

// Pure time logic for dankClock: formatting, timers, stopwatch, the pomodoro
// state machine and alarm scheduling.
//
// Every running thing is described by absolute wall-clock timestamps (endsAt,
// startedAt) plus an accumulated remainder, never by a counter decremented on
// each tick. A missed tick, a slow frame, a suspend or a whole shell restart
// therefore cannot make anything drift: the next evaluation simply reads the
// clock again. It also means the service needs only one coarse tick.
//
// No QML imports, so tests/run.mjs can exercise all of it under node. All
// functions are pure: they take state and `now` and return new objects.

var SECOND = 1000;
var MINUTE = 60 * SECOND;
var HOUR = 60 * MINUTE;
var DAY = 24 * HOUR;

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------
function pad2(n) {
    return (n < 10 ? "0" : "") + n;
}

// "m:ss" / "h:mm:ss", optionally with centiseconds. Countdowns round *up* so a
// timer reads 0:01 until it actually fires, and never shows 0:00 while running.
function fmtDuration(ms, opts) {
    var o = opts || {};
    var v = Math.max(0, Number(ms) || 0);
    var totalS = o.countdown ? Math.ceil(v / SECOND) : Math.floor(v / SECOND);
    var h = Math.floor(totalS / 3600);
    var m = Math.floor((totalS % 3600) / 60);
    var s = totalS % 60;
    var out = (h > 0 || o.showHours) ? h + ":" + pad2(m) + ":" + pad2(s) : m + ":" + pad2(s);
    if (o.centis)
        out += "." + pad2(Math.floor((v % SECOND) / 10));
    return out;
}

// Coarse, human "7h 12m" / "45m" / "<1m" for "rings in …" captions.
function fmtHuman(ms) {
    var v = Math.max(0, Number(ms) || 0);
    if (v < MINUTE)
        return "<1m";
    var totalM = Math.floor(v / MINUTE);
    var d = Math.floor(totalM / 1440);
    var h = Math.floor((totalM % 1440) / 60);
    var m = totalM % 60;
    if (d > 0)
        return d + "d " + h + "h";
    if (h > 0)
        return m > 0 ? h + "h " + m + "m" : h + "h";
    return m + "m";
}

function fmtTimeOfDay(hour, minute, use24h) {
    if (use24h)
        return pad2(hour) + ":" + pad2(minute);
    var h12 = hour % 12 === 0 ? 12 : hour % 12;
    return h12 + ":" + pad2(minute) + (hour < 12 ? " AM" : " PM");
}

function dayKey(date) {
    var d = new Date(date);
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

// ---------------------------------------------------------------------------
// Parsing (IPC and text fields)
// ---------------------------------------------------------------------------
// Accepts "90s", "5m", "1h30m", "1h 30m 10s", "1:30" (m:ss), "1:02:03" (h:mm:ss),
// and a bare number, which means minutes. Returns ms, or null if unparseable
// or zero.
function parseDuration(text) {
    var s = String(text === undefined || text === null ? "" : text).trim().toLowerCase();
    if (!s)
        return null;
    var ms = 0;
    if (/^\d+(\.\d+)?$/.test(s)) {
        ms = parseFloat(s) * MINUTE;
    } else if (/^\d+(:\d{1,2}){1,2}$/.test(s)) {
        var parts = s.split(":").map(Number);
        if (parts.length === 2)
            ms = parts[0] * MINUTE + parts[1] * SECOND;
        else
            ms = parts[0] * HOUR + parts[1] * MINUTE + parts[2] * SECOND;
    } else {
        var re = /(\d+(?:\.\d+)?)\s*(hours?|hrs|hr|h|minutes?|mins|min|m|seconds?|secs|sec|s)\s*/g;
        var consumed = 0;
        var match;
        while ((match = re.exec(s)) !== null) {
            if (match.index !== consumed)
                return null;
            consumed = re.lastIndex;
            var n = parseFloat(match[1]);
            var u = match[2].charAt(0);
            ms += n * (u === "h" ? HOUR : u === "m" ? MINUTE : SECOND);
        }
        if (consumed !== s.length)
            return null;
    }
    ms = Math.round(ms);
    return ms > 0 ? ms : null;
}

// "7:30", "07:30", "7.30", "730", "19:05". Returns {hour, minute} or null.
function parseTimeOfDay(text) {
    var s = String(text === undefined || text === null ? "" : text).trim().toLowerCase();
    var pm = /pm$/.test(s), am = /am$/.test(s);
    s = s.replace(/\s*(am|pm)$/, "");
    var m = /^(\d{1,2})(?:[:.]?(\d{2}))?$/.exec(s);
    if (!m)
        return null;
    var hour = parseInt(m[1], 10);
    var minute = m[2] ? parseInt(m[2], 10) : 0;
    if (pm || am) {
        if (hour < 1 || hour > 12)
            return null;
        hour = (hour % 12) + (pm ? 12 : 0);
    }
    if (hour > 23 || minute > 59)
        return null;
    return { hour: hour, minute: minute };
}

// ---------------------------------------------------------------------------
// Countdown timers
// ---------------------------------------------------------------------------
// { id, label, durationMs, status: "running"|"paused"|"done", endsAt, remainingMs }
function newTimer(id, durationMs, label, now) {
    return {
        id: id,
        label: label || "",
        durationMs: durationMs,
        status: "running",
        endsAt: now + durationMs,
        remainingMs: durationMs
    };
}

function timerRemaining(t, now) {
    if (t.status === "running")
        return Math.max(0, t.endsAt - now);
    if (t.status === "done")
        return 0;
    return Math.max(0, t.remainingMs);
}

function timerProgress(t, now) {
    if (!t.durationMs)
        return 0;
    return Math.min(1, Math.max(0, 1 - timerRemaining(t, now) / t.durationMs));
}

function timerPause(t, now) {
    if (t.status !== "running")
        return t;
    return Object.assign({}, t, { status: "paused", remainingMs: timerRemaining(t, now), endsAt: null });
}

function timerResume(t, now) {
    if (t.status !== "paused")
        return t;
    return Object.assign({}, t, { status: "running", endsAt: now + t.remainingMs });
}

// +N on a finished timer restarts it for N, which is what "+1 min" on a ringing
// timer is expected to do.
function timerAddTime(t, ms, now) {
    if (t.status === "running")
        return Object.assign({}, t, { endsAt: t.endsAt + ms, durationMs: t.durationMs + ms });
    if (t.status === "paused")
        return Object.assign({}, t, { remainingMs: t.remainingMs + ms, durationMs: t.durationMs + ms });
    return Object.assign({}, t, { status: "running", endsAt: now + ms, remainingMs: ms, durationMs: ms });
}

function timerIsDue(t, now) {
    return t.status === "running" && now >= t.endsAt;
}

function timerFinish(t) {
    return Object.assign({}, t, { status: "done", endsAt: null, remainingMs: 0 });
}

// ---------------------------------------------------------------------------
// Stopwatch
// ---------------------------------------------------------------------------
// { startedAt: ms|null, accumulatedMs, laps: [{ n, totalMs, splitMs }] }  laps newest first
function newStopwatch() {
    return { startedAt: null, accumulatedMs: 0, laps: [] };
}

function swRunning(sw) {
    return sw.startedAt !== null && sw.startedAt !== undefined;
}

function swElapsed(sw, now) {
    return sw.accumulatedMs + (swRunning(sw) ? Math.max(0, now - sw.startedAt) : 0);
}

function swStart(sw, now) {
    if (swRunning(sw))
        return sw;
    return Object.assign({}, sw, { startedAt: now });
}

function swPause(sw, now) {
    if (!swRunning(sw))
        return sw;
    return Object.assign({}, sw, { startedAt: null, accumulatedMs: swElapsed(sw, now) });
}

function swLap(sw, now) {
    var total = swElapsed(sw, now);
    if (total <= 0)
        return sw;
    var prevTotal = sw.laps.length ? sw.laps[0].totalMs : 0;
    var lap = { n: sw.laps.length + 1, totalMs: total, splitMs: total - prevTotal };
    return Object.assign({}, sw, { laps: [lap].concat(sw.laps) });
}

// The lap currently in progress, for display above the recorded laps.
function swCurrentSplit(sw, now) {
    var prevTotal = sw.laps.length ? sw.laps[0].totalMs : 0;
    return Math.max(0, swElapsed(sw, now) - prevTotal);
}

// Lap numbers of the fastest and slowest split; only meaningful from two laps.
function lapExtremes(laps) {
    if (!laps || laps.length < 2)
        return { best: -1, worst: -1 };
    var best = laps[0], worst = laps[0];
    for (var i = 1; i < laps.length; i++) {
        if (laps[i].splitMs < best.splitMs)
            best = laps[i];
        if (laps[i].splitMs > worst.splitMs)
            worst = laps[i];
    }
    return { best: best.n, worst: worst.n };
}

// ---------------------------------------------------------------------------
// Pomodoro
// ---------------------------------------------------------------------------
// cfg: { workMin, shortBreakMin, longBreakMin, cyclesBeforeLongBreak }
// state: { phase: "work"|"shortBreak"|"longBreak", status: "idle"|"running"|"paused",
//          endsAt, remainingMs, totalMs, cycle }
// `cycle` counts work sessions completed in the current set (0 … n-1). It drives
// the long break and the dots in the UI.
var PHASES = ["work", "shortBreak", "longBreak"];

function phaseMs(phase, cfg) {
    var min = phase === "work" ? cfg.workMin : phase === "shortBreak" ? cfg.shortBreakMin : cfg.longBreakMin;
    return Math.max(1, Number(min) || 1) * MINUTE;
}

function phaseLabel(phase) {
    return phase === "work" ? "Focus" : phase === "shortBreak" ? "Short break" : "Long break";
}

function pomoInitial(cfg) {
    var total = phaseMs("work", cfg);
    return { phase: "work", status: "idle", endsAt: null, remainingMs: total, totalMs: total, cycle: 0 };
}

// Restores a persisted state defensively: anything malformed falls back to idle.
function pomoSanitize(s, cfg) {
    if (!s || PHASES.indexOf(s.phase) < 0 || ["idle", "running", "paused"].indexOf(s.status) < 0)
        return pomoInitial(cfg);
    var out = Object.assign({}, s);
    out.cycle = Math.max(0, Math.floor(Number(s.cycle) || 0));
    out.totalMs = Number(s.totalMs) > 0 ? Number(s.totalMs) : phaseMs(s.phase, cfg);
    out.remainingMs = Number(s.remainingMs) >= 0 ? Number(s.remainingMs) : out.totalMs;
    if (out.status === "running" && !(Number(s.endsAt) > 0))
        out.status = "paused";
    if (out.status !== "running")
        out.endsAt = null;
    return out;
}

function pomoRemaining(s, now) {
    return s.status === "running" ? Math.max(0, s.endsAt - now) : Math.max(0, s.remainingMs);
}

function pomoProgress(s, now) {
    return s.totalMs ? Math.min(1, Math.max(0, 1 - pomoRemaining(s, now) / s.totalMs)) : 0;
}

function pomoStart(s, now) {
    if (s.status === "running")
        return s;
    return Object.assign({}, s, { status: "running", endsAt: now + s.remainingMs });
}

function pomoPause(s, now) {
    if (s.status !== "running")
        return s;
    return Object.assign({}, s, { status: "paused", remainingMs: pomoRemaining(s, now), endsAt: null });
}

function pomoToggle(s, now) {
    return s.status === "running" ? pomoPause(s, now) : pomoStart(s, now);
}

function pomoReset(cfg) {
    return pomoInitial(cfg);
}

function pomoIsDue(s, now) {
    return s.status === "running" && now >= s.endsAt;
}

function nextPhaseOf(s, cfg) {
    var n = Math.max(1, Math.floor(Number(cfg.cyclesBeforeLongBreak) || 1));
    if (s.phase === "work") {
        var done = s.cycle + 1;
        return done >= n ? { phase: "longBreak", cycle: done } : { phase: "shortBreak", cycle: done };
    }
    if (s.phase === "longBreak")
        return { phase: "work", cycle: 0 };
    return { phase: "work", cycle: s.cycle };
}

// Moves to the following phase. `run` decides whether it starts counting at once.
// Returns { state, completedWork } — completedWork is true only when a focus
// session ran to its end, so a skip is never credited in the history.
function pomoAdvance(s, cfg, now, run, credited) {
    var next = nextPhaseOf(s, cfg);
    var total = phaseMs(next.phase, cfg);
    var state = {
        phase: next.phase,
        status: run ? "running" : "idle",
        endsAt: run ? now + total : null,
        remainingMs: total,
        totalMs: total,
        cycle: next.cycle
    };
    return { state: state, completedWork: !!credited && s.phase === "work" };
}

// Natural end of a phase: auto-start follows the user's settings.
function pomoComplete(s, cfg, now) {
    var next = nextPhaseOf(s, cfg);
    var run = next.phase === "work" ? !!cfg.autoStartWork : !!cfg.autoStartBreaks;
    return pomoAdvance(s, cfg, now, run, true);
}

// Manual skip: keeps running if it was running, otherwise waits.
function pomoSkip(s, cfg, now) {
    return pomoAdvance(s, cfg, now, s.status === "running", false);
}

// Durations changed while a phase is in progress: keep the elapsed time, apply
// the new length, and never end up already expired (at least 1 s left).
function pomoApplyConfig(s, cfg, now) {
    var total = phaseMs(s.phase, cfg);
    if (total === s.totalMs)
        return s;
    if (s.status === "idle")
        return Object.assign({}, s, { totalMs: total, remainingMs: total });
    var elapsed = s.totalMs - pomoRemaining(s, now);
    var remaining = Math.max(SECOND, total - elapsed);
    var out = Object.assign({}, s, { totalMs: total, remainingMs: remaining });
    if (s.status === "running")
        out.endsAt = now + remaining;
    return out;
}

// ---------------------------------------------------------------------------
// Alarms
// ---------------------------------------------------------------------------
// { id, hour, minute, label, days (bitmask, bit 0 = Sunday … bit 6 = Saturday;
//   0 = one-shot), enabled, snoozeUntil: ms|null }
var DAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
var WEEKDAYS = 0x3E;   // Mon–Fri
var WEEKENDS = 0x41;   // Sat + Sun
var EVERY_DAY = 0x7F;

function dayOn(mask, day) {
    return (mask & (1 << day)) !== 0;
}

function toggleDay(mask, day) {
    return mask ^ (1 << day);
}

function daysLabel(mask) {
    if (!mask)
        return "Once";
    if (mask === EVERY_DAY)
        return "Every day";
    if (mask === WEEKDAYS)
        return "Weekdays";
    if (mask === WEEKENDS)
        return "Weekends";
    var out = [];
    // Monday-first reads more naturally in a list.
    var order = [1, 2, 3, 4, 5, 6, 0];
    for (var i = 0; i < order.length; i++)
        if (dayOn(mask, order[i]))
            out.push(DAY_SHORT[order[i]]);
    return out.join(", ");
}

// The calendar occurrence of hour:minute on the day `offset` days from `base`,
// built from local date fields. Constructing it this way (rather than adding
// 24 h multiples) keeps it on the wall-clock time across DST changes; on a
// spring-forward day a nonexistent 02:30 becomes 03:30, as every clock does.
function occurrenceOn(base, offset, hour, minute) {
    var d = new Date(base);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + offset, hour, minute, 0, 0).getTime();
}

// Next scheduled ring strictly after `now`, ignoring snooze. null if disabled.
function alarmNextScheduled(a, now) {
    if (!a.enabled)
        return null;
    for (var off = 0; off <= 7; off++) {
        var t = occurrenceOn(now, off, a.hour, a.minute);
        if (t <= now)
            continue;
        if (!a.days || dayOn(a.days, new Date(t).getDay()))
            return t;
    }
    return null;
}

// Next time this alarm will ring, counting a pending snooze.
function alarmNextFire(a, now) {
    var sched = alarmNextScheduled(a, now);
    var snooze = (a.snoozeUntil && a.snoozeUntil > now) ? a.snoozeUntil : null;
    if (sched === null)
        return snooze;
    if (snooze === null)
        return sched;
    return Math.min(sched, snooze);
}

// Latest occurrence (scheduled or snoozed) in the window (from, to], or null.
function alarmOccurrenceIn(a, from, to) {
    var best = null;
    if (a.snoozeUntil && a.snoozeUntil > from && a.snoozeUntil <= to)
        best = a.snoozeUntil;
    if (a.enabled) {
        for (var off = 0; off >= -8; off--) {
            var t = occurrenceOn(to, off, a.hour, a.minute);
            if (t > to)
                continue;
            if (t <= from)
                break;
            if (!a.days || dayOn(a.days, new Date(t).getDay())) {
                if (best === null || t > best)
                    best = t;
                break;
            }
        }
    }
    return best;
}

// Alarms that came due in (from, to]. An occurrence more than graceMs before
// `to` is reported as missed rather than rung — that is the shell having been
// down, or the machine asleep, and ringing an hour late helps nobody.
function dueAlarms(alarms, from, to, graceMs) {
    var out = [];
    for (var i = 0; i < alarms.length; i++) {
        var at = alarmOccurrenceIn(alarms[i], from, to);
        if (at !== null)
            out.push({ alarm: alarms[i], at: at, missed: to - at > graceMs });
    }
    return out;
}

// State of an alarm once it has rung (or been missed): snooze cleared, one-shot
// alarms switched off.
function alarmAfterFire(a) {
    return Object.assign({}, a, { snoozeUntil: null, enabled: a.days ? a.enabled : false });
}

function alarmSnooze(a, now, ms) {
    return Object.assign({}, a, { snoozeUntil: now + ms });
}

function sortAlarms(alarms) {
    return alarms.slice().sort(function (x, y) {
        return (x.hour * 60 + x.minute) - (y.hour * 60 + y.minute) || String(x.id).localeCompare(String(y.id));
    });
}

// Next alarm across the list: { alarm, at } or null.
function nextAlarm(alarms, now) {
    var best = null;
    for (var i = 0; i < alarms.length; i++) {
        var at = alarmNextFire(alarms[i], now);
        if (at !== null && (best === null || at < best.at))
            best = { alarm: alarms[i], at: at };
    }
    return best;
}

// ---------------------------------------------------------------------------
// Bar summary
// ---------------------------------------------------------------------------
// Picks what the pill shows. `items` maps kind -> descriptor or null, e.g.
// { ringing: {...}, pomodoro: {...}, timer: null, stopwatch: {...} }.
// `priority` is a comma-separated order; unknown kinds are ignored and missing
// ones are appended in the default order, so a typo can never hide a timer.
var DEFAULT_PRIORITY = ["ringing", "pomodoro", "timer", "stopwatch"];

function priorityOrder(csv) {
    var seen = {};
    var out = [];
    String(csv || "").split(",").forEach(function (k) {
        var key = k.trim();
        if (DEFAULT_PRIORITY.indexOf(key) >= 0 && !seen[key]) {
            seen[key] = true;
            out.push(key);
        }
    });
    DEFAULT_PRIORITY.forEach(function (k) {
        if (!seen[k])
            out.push(k);
    });
    return out;
}

function pickPrimary(items, csv) {
    var order = priorityOrder(csv);
    for (var i = 0; i < order.length; i++) {
        var v = items[order[i]];
        if (v)
            return { kind: order[i], item: v };
    }
    return null;
}

// Id generator that stays unique across restarts without a persisted counter.
function makeId(prefix, now) {
    return prefix + "-" + now.toString(36) + "-" + Math.floor(Math.random() * 1e6).toString(36);
}
