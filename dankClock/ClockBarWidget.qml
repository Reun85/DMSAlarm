import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "Clock.js" as Clock

// Bar pill + popout + Control Center tile. All state lives in the ClockService
// singleton; this file only decides what to show.
//
// The pill shows the most important running thing (order set by barPriority):
// something ringing, else the pomodoro, else the soonest timer, else the
// stopwatch. Idle, it is an icon (or the pomodoro length / next alarm).
//
// Clicks: left opens the popout, right starts/pauses the pomodoro. While
// something rings, left dismisses and right snoozes, so an alarm can be dealt
// with without opening anything.
PluginComponent {
    id: root

    layerNamespacePlugin: "dank-clock"

    readonly property var cfg: ClockService.cfg
    readonly property real now: ClockService.now
    readonly property bool isRinging: ClockService.ringing.length > 0

    readonly property var primary: Clock.pickPrimary({
        ringing: isRinging ? ClockService.ringing[ClockService.ringing.length - 1] : null,
        pomodoro: ClockService.pomoActive ? ClockService.pomo : null,
        timer: ClockService.soonestTimer,
        stopwatch: ClockService.swActive ? ClockService.stopwatch : null
    }, cfg.barPriority)

    readonly property color pomoColor: ClockService.pomo.phase === "work" ? Theme.primary : ClockService.pomo.phase === "shortBreak" ? Theme.secondary : Theme.tertiary

    function phaseIcon(phase) {
        return phase === "work" ? "timer" : phase === "shortBreak" ? "coffee" : "self_improvement";
    }

    // { icon, text, color, progress (-1 = none), dim }
    readonly property var view: {
        const p = primary;
        const accent = Theme.widgetTextColor || Theme.surfaceText;
        if (!p) {
            if (cfg.barIdle === "pomodoro")
                return {
                    icon: "timer",
                    text: Clock.fmtDuration(ClockService.pomo.remainingMs, {
                        countdown: true
                    }),
                    color: accent,
                    progress: -1,
                    dim: true
                };
            const na = ClockService.nextAlarm;
            if (cfg.barIdle === "nextAlarm" && na && na.at - now < Clock.DAY)
                return {
                    icon: "alarm",
                    text: Clock.fmtTimeOfDay(na.alarm.hour, na.alarm.minute, cfg.use24h),
                    color: accent,
                    progress: -1,
                    dim: true
                };
            return {
                icon: "timer",
                text: "",
                color: accent,
                progress: -1,
                dim: false
            };
        }
        switch (p.kind) {
        case "ringing":
            return {
                icon: p.item.kind === "alarm" ? "alarm" : p.item.kind === "timer" ? "timer_off" : "notifications_active",
                text: p.item.title,
                color: Theme.primary,
                progress: -1,
                dim: false
            };
        case "pomodoro":
            return {
                icon: p.item.status === "paused" ? "pause_circle" : phaseIcon(p.item.phase),
                text: Clock.fmtDuration(Clock.pomoRemaining(p.item, now), {
                    countdown: true
                }),
                color: pomoColor,
                progress: Clock.pomoProgress(p.item, now),
                dim: p.item.status !== "running"
            };
        case "timer":
            {
                const extra = ClockService.activeTimers.length - 1;
                return {
                    icon: p.item.status === "paused" ? "pause_circle" : "hourglass_top",
                    text: Clock.fmtDuration(Clock.timerRemaining(p.item, now), {
                        countdown: true
                    }) + (extra > 0 ? " +" + extra : ""),
                    color: Theme.primary,
                    progress: Clock.timerProgress(p.item, now),
                    dim: p.item.status !== "running"
                };
            }
        case "stopwatch":
            return {
                icon: "timer_play",
                text: Clock.fmtDuration(Clock.swElapsed(p.item, now)),
                color: Theme.primary,
                progress: -1,
                dim: !Clock.swRunning(p.item)
            };
        }
        return {
            icon: "timer",
            text: "",
            color: accent,
            progress: -1,
            dim: false
        };
    }

    pillClickAction: isRinging ? (() => ClockService.dismissAll()) : null
    pillRightClickAction: isRinging ? (() => ClockService.snoozeAll()) : (() => ClockService.pomoToggle())

    // ---------------------------------------------------------------------
    // Pill
    // ---------------------------------------------------------------------
    // BasePill sizes itself from the content root's implicit size and draws its
    // own background, hover and ripple, so the content is bare.
    component Pulse: SequentialAnimation {
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation {
            to: 0.35
            duration: 500
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            to: 1
            duration: 500
            easing.type: Easing.InOutQuad
        }
    }

    component PillIcon: DankIcon {
        name: root.view.icon
        size: root.iconSize
        color: root.view.color
        opacity: root.view.dim ? 0.7 : 1
    }

    component PillText: StyledText {
        visible: text.length > 0
        color: Theme.widgetTextColor || Theme.surfaceText
        opacity: root.view.dim ? 0.7 : 1
        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
        // Tabular figures, so the pill does not change width every second.
        font.features: {
            "tnum": 1
        }
        elide: Text.ElideRight
    }

    // Thin progress line under the pill content.
    component Progress: Rectangle {
        property real fullWidth: 0
        visible: root.cfg.showProgressInBar && root.view.progress >= 0
        height: 2
        radius: 1
        width: fullWidth * Math.max(0, root.view.progress)
        color: root.view.color
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: hRow.implicitWidth
            implicitHeight: hRow.implicitHeight

            Pulse on opacity {
                running: root.isRinging && !ClockService.silenced
            }

            Row {
                id: hRow
                spacing: Theme.spacingXS

                PillIcon {
                    anchors.verticalCenter: parent.verticalCenter
                }

                PillText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.view.text
                    width: Math.min(implicitWidth, 160)
                }
            }

            Progress {
                anchors.left: parent.left
                anchors.top: hRow.bottom
                anchors.topMargin: 1
                fullWidth: hRow.width
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            Pulse on opacity {
                running: root.isRinging && !ClockService.silenced
            }

            PillIcon {
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // "12:34" stacks as "12" over "34" to fit a narrow bar; labels
            // (a ringing alarm's title) are not useful at this width.
            PillText {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.primary && root.primary.kind === "ringing" ? "" : root.view.text.replace(/ \+\d+$/, "").split(":").slice(-2).join("\n")
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale) - 1
                lineHeight: 0.9
            }

            Progress {
                anchors.horizontalCenter: parent.horizontalCenter
                fullWidth: root.iconSize
            }
        }
    }

    // ---------------------------------------------------------------------
    // Popout
    // ---------------------------------------------------------------------
    popoutWidth: 440

    popoutContent: Component {
        ClockPopout {}
    }

    // ---------------------------------------------------------------------
    // Control Center tile: the pomodoro, toggled from the tile itself
    // ---------------------------------------------------------------------
    // DMS probes this component headlessly (createObject(null)) to read
    // ccWidgetIcon; nothing here may throw if the service is not ready.
    ccWidgetIcon: "timer"
    ccWidgetPrimaryText: I18n.tr("Pomodoro")
    ccWidgetSecondaryText: {
        const p = ClockService.pomo;
        if (!p || !p.phase)
            return "";
        const rem = Clock.fmtDuration(Clock.pomoRemaining(p, ClockService.now), {
            countdown: true
        });
        if (p.status === "idle")
            return I18n.tr("Ready") + " · " + rem;
        return Clock.phaseLabel(p.phase) + " · " + rem + (p.status === "paused" ? " · " + I18n.tr("paused") : "");
    }
    ccWidgetIsActive: ClockService.pomo ? ClockService.pomo.status === "running" : false
    ccWidgetIsToggle: true
    onCcWidgetToggled: ClockService.pomoToggle()

    ccDetailHeight: 360
    ccDetailContent: Component {
        Rectangle {
            implicitHeight: ccBody.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.nestedSurface
            border.color: Theme.outlineMedium
            border.width: Theme.layerOutlineWidth

            PomodoroTab {
                id: ccBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                compact: true
            }
        }
    }
}
