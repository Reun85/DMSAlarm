// Fixture tests for the pure logic modules.
//
// Clock.js and Config.js are QML JS libraries: plain JavaScript apart from the
// leading `.pragma library` line, which node cannot parse. Strip it and import
// the rest as an ES module.
//
// Alarm scheduling depends on the local time zone, so the zone is pinned before
// anything touches Date. Europe/Budapest has DST, which the alarm fixtures use.
process.env.TZ = "Europe/Budapest";

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

async function load(file) {
    const src = readFileSync(join(root, "dankClock", file), "utf8")
        .replace(/^\s*\.pragma\s+library\s*$/m, "");
    // Export every top-level function and var without listing them by hand.
    const names = [...src.matchAll(/^(?:function\s+([A-Za-z_]\w*)|var\s+([A-Za-z_]\w*))/gm)]
        .map(m => m[1] || m[2]);
    const mod = src + "\nexport { " + names.join(", ") + " };";
    const url = "data:text/javascript;base64," + Buffer.from(mod).toString("base64");
    return import(url);
}

const C = await load("Clock.js");
const Cfg = await load("Config.js");

let passed = 0;
const failures = [];

function check(name, actual, expected) {
    const a = JSON.stringify(actual), e = JSON.stringify(expected);
    if (a === e) passed++;
    else failures.push(`${name}\n    expected ${e}\n    actual   ${a}`);
}

function ok(name, cond) {
    check(name, !!cond, true);
}

const S = 1000, M = 60 * S, H = 60 * M;
// Local wall-clock instant, independent of the machine's own zone thanks to TZ.
const at = (y, mo, d, h = 0, mi = 0, s = 0) => new Date(y, mo - 1, d, h, mi, s).getTime();

// --- formatting -------------------------------------------------------------
check("fmt 0", C.fmtDuration(0), "0:00");
check("fmt 59.99s floors", C.fmtDuration(59990), "0:59");
check("fmt 59.99s countdown ceils", C.fmtDuration(59990, { countdown: true }), "1:00");
check("fmt 0.2s countdown", C.fmtDuration(200, { countdown: true }), "0:01");
check("fmt 25m", C.fmtDuration(25 * M), "25:00");
check("fmt hours", C.fmtDuration(H + 2 * M + 3 * S), "1:02:03");
check("fmt >24h", C.fmtDuration(26 * H), "26:00:00");
check("fmt showHours", C.fmtDuration(5 * S, { showHours: true }), "0:00:05");
check("fmt centis", C.fmtDuration(61234, { centis: true }), "1:01.23");
check("fmt negative clamps", C.fmtDuration(-5000), "0:00");
check("human <1m", C.fmtHuman(30 * S), "<1m");
check("human 45m", C.fmtHuman(45 * M + 59 * S), "45m");
check("human 7h12m", C.fmtHuman(7 * H + 12 * M), "7h 12m");
check("human 2h", C.fmtHuman(2 * H), "2h");
check("human days", C.fmtHuman(50 * H), "2d 2h");
check("tod 24h", C.fmtTimeOfDay(7, 5, true), "07:05");
check("tod 12h am", C.fmtTimeOfDay(0, 30, false), "12:30 AM");
check("tod 12h pm", C.fmtTimeOfDay(13, 0, false), "1:00 PM");
check("tod 12h noon", C.fmtTimeOfDay(12, 0, false), "12:00 PM");
check("dayKey", C.dayKey(at(2026, 3, 9, 23, 59)), "2026-03-09");

// --- parsing ----------------------------------------------------------------
check("parse bare = minutes", C.parseDuration("5"), 5 * M);
check("parse 90s", C.parseDuration("90s"), 90 * S);
check("parse 1h30m", C.parseDuration("1h30m"), 90 * M);
check("parse spaced", C.parseDuration("1h 2m 3s"), H + 2 * M + 3 * S);
check("parse words", C.parseDuration("2 min"), 2 * M);
check("parse m:ss", C.parseDuration("1:30"), 90 * S);
check("parse h:mm:ss", C.parseDuration("1:00:05"), H + 5 * S);
check("parse decimal", C.parseDuration("1.5m"), 90 * S);
check("parse junk", C.parseDuration("abc"), null);
check("parse trailing junk", C.parseDuration("5m x"), null);
check("parse zero", C.parseDuration("0"), null);
check("parse empty", C.parseDuration(""), null);
check("tod parse 7:30", C.parseTimeOfDay("7:30"), { hour: 7, minute: 30 });
check("tod parse 0730", C.parseTimeOfDay("0730"), { hour: 7, minute: 30 });
check("tod parse 7", C.parseTimeOfDay("7"), { hour: 7, minute: 0 });
check("tod parse pm", C.parseTimeOfDay("7:15 pm"), { hour: 19, minute: 15 });
check("tod parse 12am", C.parseTimeOfDay("12am"), { hour: 0, minute: 0 });
check("tod parse bad hour", C.parseTimeOfDay("25:00"), null);
check("tod parse bad min", C.parseTimeOfDay("7:60"), null);

// --- timers -----------------------------------------------------------------
{
    const t0 = 1_000_000;
    let t = C.newTimer("a", 5 * M, "tea", t0);
    check("timer remaining start", C.timerRemaining(t, t0), 5 * M);
    check("timer remaining mid", C.timerRemaining(t, t0 + M), 4 * M);
    check("timer progress mid", Math.round(C.timerProgress(t, t0 + M) * 100), 20);
    ok("timer not due", !C.timerIsDue(t, t0 + 5 * M - 1));
    ok("timer due", C.timerIsDue(t, t0 + 5 * M));
    t = C.timerPause(t, t0 + M);
    check("timer paused status", t.status, "paused");
    check("timer paused freezes", C.timerRemaining(t, t0 + 10 * H), 4 * M);
    ok("paused never due", !C.timerIsDue(t, t0 + 10 * H));
    t = C.timerResume(t, t0 + 2 * M);
    check("timer resume", C.timerRemaining(t, t0 + 2 * M), 4 * M);
    check("timer resume endsAt", t.endsAt, t0 + 6 * M);
    t = C.timerAddTime(t, M, t0 + 2 * M);
    check("timer +1m running", C.timerRemaining(t, t0 + 2 * M), 5 * M);
    check("timer +1m duration", t.durationMs, 6 * M);
    let p = C.timerAddTime(C.timerPause(t, t0 + 3 * M), M, t0 + 3 * M);
    check("timer +1m paused", C.timerRemaining(p, t0 + 9 * M), 5 * M);
    let d = C.timerFinish(t);
    check("timer done remaining", C.timerRemaining(d, t0), 0);
    d = C.timerAddTime(d, M, t0 + 100 * M);
    check("timer +1m on done restarts", [d.status, C.timerRemaining(d, t0 + 100 * M)], ["running", M]);
    check("pause idempotent on paused", C.timerPause(p, t0).remainingMs, p.remainingMs);
}

// --- stopwatch --------------------------------------------------------------
{
    let sw = C.newStopwatch();
    check("sw idle elapsed", C.swElapsed(sw, 5000), 0);
    check("sw lap at zero is no-op", C.swLap(sw, 0).laps.length, 0);
    sw = C.swStart(sw, 1000);
    check("sw running elapsed", C.swElapsed(sw, 4000), 3000);
    sw = C.swLap(sw, 4000);
    sw = C.swLap(sw, 9000);
    sw = C.swPause(sw, 10000);
    check("sw paused elapsed", C.swElapsed(sw, 99999), 9000);
    sw = C.swStart(sw, 20000);
    check("sw resumed elapsed", C.swElapsed(sw, 21000), 10000);
    sw = C.swLap(sw, 22000);
    check("sw laps newest first", sw.laps.map(l => l.n), [3, 2, 1]);
    check("sw splits", sw.laps.map(l => l.splitMs), [3000, 5000, 3000]);
    check("sw totals", sw.laps.map(l => l.totalMs), [11000, 8000, 3000]);
    check("sw current split", C.swCurrentSplit(sw, 23000), 1000);
    // Ties go to the earliest-seen in newest-first order, i.e. the latest lap.
    check("lap extremes", C.lapExtremes(sw.laps), { best: 3, worst: 2 });
    check("lap extremes one lap", C.lapExtremes([{ n: 1, splitMs: 5 }]), { best: -1, worst: -1 });
    ok("swStart idempotent", C.swStart(sw, 99999).startedAt === 20000);
}

// --- pomodoro ---------------------------------------------------------------
{
    const cfg = { workMin: 25, shortBreakMin: 5, longBreakMin: 15, cyclesBeforeLongBreak: 4, autoStartBreaks: false, autoStartWork: false };
    let s = C.pomoInitial(cfg);
    check("pomo initial", [s.phase, s.status, s.remainingMs, s.cycle], ["work", "idle", 25 * M, 0]);
    s = C.pomoStart(s, 0);
    check("pomo start", [s.status, s.endsAt], ["running", 25 * M]);
    s = C.pomoPause(s, 10 * M);
    check("pomo pause", [s.status, C.pomoRemaining(s, 99 * H)], ["paused", 15 * M]);
    s = C.pomoToggle(s, 20 * M);
    check("pomo toggle resumes", C.pomoRemaining(s, 20 * M), 15 * M);
    ok("pomo due", C.pomoIsDue(s, 35 * M));

    // Full cycle: W S W S W S W L W
    let seq = [];
    let credited = 0;
    let st = C.pomoStart(C.pomoInitial(cfg), 0);
    let now = 0;
    for (let i = 0; i < 9; i++) {
        seq.push(st.phase[0] === "w" ? "W" : st.phase === "shortBreak" ? "S" : "L");
        now = st.status === "running" ? st.endsAt : now;
        const r = C.pomoComplete(st, cfg, now);
        if (r.completedWork)
            credited++;
        st = C.pomoStart(r.state, now);
    }
    check("pomo cycle sequence", seq.join(""), "WSWSWSWLW");
    check("pomo credited work sessions", credited, 5);

    // auto-start
    let a = C.pomoComplete(C.pomoStart(C.pomoInitial(cfg), 0), Object.assign({}, cfg, { autoStartBreaks: true }), 25 * M);
    check("auto-start break", [a.state.phase, a.state.status, a.state.endsAt], ["shortBreak", "running", 30 * M]);
    let b = C.pomoComplete(a.state, cfg, 30 * M);
    check("no auto-start work", [b.state.phase, b.state.status], ["work", "idle"]);
    check("break completion not credited", b.completedWork, false);

    // skip
    let k = C.pomoSkip(C.pomoStart(C.pomoInitial(cfg), 0), cfg, 5 * M);
    check("skip running keeps running", [k.state.phase, k.state.status, k.completedWork], ["shortBreak", "running", false]);
    let k2 = C.pomoSkip(C.pomoInitial(cfg), cfg, 0);
    check("skip idle stays idle", [k2.state.phase, k2.state.status], ["shortBreak", "idle"]);
    check("skip advances cycle", k2.state.cycle, 1);

    // long break after n=2
    const cfg2 = Object.assign({}, cfg, { cyclesBeforeLongBreak: 2 });
    let l = C.pomoComplete(C.pomoInitial(cfg2), cfg2, 0).state;            // S, cycle 1
    l = C.pomoComplete(l, cfg2, 0).state;                                   // W
    l = C.pomoComplete(l, cfg2, 0).state;                                   // L, cycle 2
    check("long break at n", [l.phase, l.cycle, l.totalMs], ["longBreak", 2, 15 * M]);
    l = C.pomoComplete(l, cfg2, 0).state;
    check("after long break resets cycle", [l.phase, l.cycle], ["work", 0]);

    // duration change
    let r = C.pomoStart(C.pomoInitial(cfg), 0);
    r = C.pomoApplyConfig(r, Object.assign({}, cfg, { workMin: 50 }), 10 * M);
    check("rescale running keeps elapsed", [r.totalMs, C.pomoRemaining(r, 10 * M)], [50 * M, 40 * M]);
    r = C.pomoApplyConfig(r, Object.assign({}, cfg, { workMin: 5 }), 10 * M);
    check("rescale shorter than elapsed leaves 1s", C.pomoRemaining(r, 10 * M), S);
    let idle = C.pomoApplyConfig(C.pomoInitial(cfg), Object.assign({}, cfg, { workMin: 30 }), 0);
    check("rescale idle", [idle.totalMs, idle.remainingMs], [30 * M, 30 * M]);
    let paused = C.pomoApplyConfig(C.pomoPause(C.pomoStart(C.pomoInitial(cfg), 0), 5 * M), Object.assign({}, cfg, { workMin: 30 }), 99 * M);
    check("rescale paused", [paused.status, paused.remainingMs, paused.endsAt], ["paused", 25 * M, null]);

    // sanitize
    check("sanitize garbage", C.pomoSanitize({ phase: "nap" }, cfg).status, "idle");
    check("sanitize null", C.pomoSanitize(null, cfg).phase, "work");
    check("sanitize running w/o endsAt -> paused", C.pomoSanitize({ phase: "work", status: "running", remainingMs: 1000, totalMs: 2000 }, cfg).status, "paused");
    check("phaseMs guards zero", C.phaseMs("work", { workMin: 0 }), M);
}

// --- alarms -----------------------------------------------------------------
{
    // 2026-10-12 is a Monday.
    const mon0700 = at(2026, 10, 12, 7, 0);
    const once = { id: "a", hour: 7, minute: 30, days: 0, enabled: true, snoozeUntil: null };
    check("one-shot later today", C.alarmNextScheduled(once, mon0700), at(2026, 10, 12, 7, 30));
    check("one-shot tomorrow", C.alarmNextScheduled(once, at(2026, 10, 12, 8, 0)), at(2026, 10, 13, 7, 30));
    check("exact minute is not 'next'", C.alarmNextScheduled(once, at(2026, 10, 12, 7, 30)), at(2026, 10, 13, 7, 30));
    check("disabled has no next", C.alarmNextScheduled(Object.assign({}, once, { enabled: false }), mon0700), null);

    const weekdays = Object.assign({}, once, { days: C.WEEKDAYS });
    const fri0800 = at(2026, 10, 16, 8, 0);
    check("weekdays skip weekend", C.alarmNextScheduled(weekdays, fri0800), at(2026, 10, 19, 7, 30));
    const sunOnly = Object.assign({}, once, { days: 1 });
    check("sunday only wraps week", C.alarmNextScheduled(sunOnly, at(2026, 10, 18, 9, 0)), at(2026, 10, 25, 7, 30));

    // snooze
    const sn = C.alarmSnooze(Object.assign({}, once, { enabled: false }), mon0700, 9 * M);
    check("snooze next fire", C.alarmNextFire(sn, mon0700), mon0700 + 9 * M);
    check("snooze earlier than schedule wins", C.alarmNextFire(C.alarmSnooze(once, mon0700, 5 * M), mon0700), mon0700 + 5 * M);

    // due detection
    check("due in window", C.dueAlarms([once], at(2026, 10, 12, 7, 29, 59), at(2026, 10, 12, 7, 30, 0), 5 * M).map(d => [d.at, d.missed]),
          [[at(2026, 10, 12, 7, 30), false]]);
    check("not due before", C.dueAlarms([once], at(2026, 10, 12, 7, 29), at(2026, 10, 12, 7, 29, 59), 5 * M).length, 0);
    check("not refired after window", C.dueAlarms([once], at(2026, 10, 12, 7, 30), at(2026, 10, 12, 7, 31), 5 * M).length, 0);
    check("missed beyond grace", C.dueAlarms([once], at(2026, 10, 12, 6, 0), at(2026, 10, 12, 9, 0), 5 * M).map(d => d.missed), [true]);
    check("within grace rings", C.dueAlarms([once], at(2026, 10, 12, 6, 0), at(2026, 10, 12, 7, 33), 5 * M).map(d => d.missed), [false]);
    check("snooze due", C.dueAlarms([sn], mon0700 + 8 * M, mon0700 + 9 * M, 5 * M).length, 1);
    check("weekday filter in window", C.dueAlarms([sunOnly], at(2026, 10, 12, 7, 0), at(2026, 10, 12, 8, 0), 5 * M).length, 0);

    check("after fire disables one-shot", C.alarmAfterFire(sn).enabled, false);
    check("after fire keeps repeating", C.alarmAfterFire(Object.assign({}, weekdays, { snoozeUntil: 5 })).enabled, true);
    check("after fire clears snooze", C.alarmAfterFire(Object.assign({}, weekdays, { snoozeUntil: 5 })).snoozeUntil, null);

    // DST, Europe/Budapest: spring forward 2026-03-29 02:00 -> 03:00,
    // fall back 2026-10-25 03:00 -> 02:00.
    const daily = { id: "d", hour: 7, minute: 0, days: C.EVERY_DAY, enabled: true, snoozeUntil: null };
    const beforeSpring = at(2026, 3, 28, 8, 0);
    const nextSpring = C.alarmNextScheduled(daily, beforeSpring);
    check("DST spring keeps 07:00 wall time", new Date(nextSpring).getHours(), 7);
    check("DST spring: 23 wall hours are 22 real hours", (nextSpring - beforeSpring) / H, 22);
    const beforeFall = at(2026, 10, 24, 8, 0);
    const nextFall = C.alarmNextScheduled(daily, beforeFall);
    check("DST fall keeps 07:00 wall time", new Date(nextFall).getHours(), 7);
    check("DST fall: 23 wall hours are 24 real hours", (nextFall - beforeFall) / H, 24);
    const gap = { id: "g", hour: 2, minute: 30, days: 0, enabled: true, snoozeUntil: null };
    const g = C.alarmNextScheduled(gap, at(2026, 3, 29, 0, 0));
    check("nonexistent 02:30 rings at 03:30", [new Date(g).getDate(), new Date(g).getHours(), new Date(g).getMinutes()], [29, 3, 30]);

    // labels / helpers
    check("days once", C.daysLabel(0), "Once");
    check("days every", C.daysLabel(C.EVERY_DAY), "Every day");
    check("days weekdays", C.daysLabel(C.WEEKDAYS), "Weekdays");
    check("days weekends", C.daysLabel(C.WEEKENDS), "Weekends");
    check("days list monday-first", C.daysLabel((1 << 0) | (1 << 1) | (1 << 3)), "Mon, Wed, Sun");
    check("toggleDay", C.toggleDay(0, 2), 4);
    check("sort alarms", C.sortAlarms([{ id: "b", hour: 9, minute: 0 }, { id: "a", hour: 6, minute: 45 }]).map(a => a.id), ["a", "b"]);
    const na = C.nextAlarm([weekdays, Object.assign({}, once, { id: "z", hour: 7, minute: 10 })], mon0700);
    check("nextAlarm picks soonest", [na.alarm.id, na.at], ["z", at(2026, 10, 12, 7, 10)]);
    check("nextAlarm none", C.nextAlarm([], mon0700), null);
}

// --- bar priority -----------------------------------------------------------
check("priority default", C.priorityOrder(""), ["ringing", "pomodoro", "timer", "stopwatch"]);
check("priority custom + fill", C.priorityOrder("timer, bogus, stopwatch"), ["timer", "stopwatch", "ringing", "pomodoro"]);
check("pick primary", C.pickPrimary({ ringing: null, pomodoro: null, timer: { x: 1 }, stopwatch: { y: 1 } }, "stopwatch,timer").kind, "stopwatch");
check("pick primary none", C.pickPrimary({}, ""), null);
ok("ids unique", C.makeId("t", 1) !== C.makeId("t", 1));

// --- config -----------------------------------------------------------------
{
    const d = Cfg.resolve({});
    check("config defaults", d, Cfg.DEFAULTS);
    check("config null", Cfg.resolve(null).workMin, 25);
    const r = Cfg.resolve({ workMin: "50", autoStartBreaks: "true", barIdle: "nonsense", snoozeMin: 999, soundVolume: "", toasts: 0, extra: 1 });
    check("config string number", r.workMin, 50);
    check("config string bool", r.autoStartBreaks, true);
    check("config bad choice", r.barIdle, "icon");
    check("config clamps", r.snoozeMin, 60);
    check("config empty number -> default", r.soundVolume, 100);
    check("config numeric bool", r.toasts, false);
    ok("config drops unknown keys", !("extra" in r));
    check("config NaN", Cfg.resolve({ workMin: "abc" }).workMin, 25);
    check("config rounds", Cfg.resolve({ workMin: 12.6 }).workMin, 13);

    const pc = Cfg.pomodoroConfig(d, { workMin: 45, autoStartWork: true, junk: 1 });
    check("pomo cfg overrides", [pc.workMin, pc.shortBreakMin, pc.autoStartWork], [45, 5, true]);
    ok("pomo cfg has no junk", !("junk" in pc));
    check("pomo cfg override clamps", Cfg.pomodoroConfig(d, { cyclesBeforeLongBreak: 0 }).cyclesBeforeLongBreak, 1);

    check("presets parse", Cfg.parsePresets("10, 5,abc,5,0,-3, 1.5"), [1.5, 5, 10]);
    check("presets empty", Cfg.parsePresets(""), []);
}

// --- report -----------------------------------------------------------------
if (failures.length) {
    console.error(failures.join("\n\n"));
    console.error(`\n${failures.length} failed, ${passed} passed`);
    process.exit(1);
}
console.log(`${passed} checks passed`);
