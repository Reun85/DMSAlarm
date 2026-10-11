import QtQuick
import qs.Common

// Dependency check. Runs before the plugin loads; done(null) allows activation.
//
// Sound is the only external dependency, and the plugin is still useful
// without it (toasts, the ringing pill), so a missing player is logged and the
// plugin loads anyway. ClockService also toasts once if playback fails.
//
// Must stay non-visual (a QtObject): it is not placed in the scene graph.
QtObject {
    function check(done) {
        Proc.runCommand("dankClock.depCheck", ["sh", "-c", "command -v pw-play >/dev/null || command -v paplay >/dev/null"], (stdout, exitCode) => {
            if (exitCode !== 0)
                console.warn("dankClock: neither pw-play nor paplay found; alarms will be silent");
            done(null);
        });
    }
}
