import QtQuick
import qs.Common
import qs.Widgets
import "Clock.js" as Clock

// Pomodoro: ring + controls, the adjustable cycle, and a week of history.
// `compact` drops the adjust and history blocks (Control Center detail).
Column {
    id: tab

    property bool compact: false

    readonly property var pomo: ClockService.pomo
    readonly property var pcfg: ClockService.pomoCfg
    readonly property real remaining: Clock.pomoRemaining(pomo, ClockService.now)
    readonly property color phaseColor: pomo.phase === "work" ? Theme.primary : pomo.phase === "shortBreak" ? Theme.secondary : Theme.tertiary

    spacing: Theme.spacingM

    // --------------------------------------------------------------- phase row
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.spacingS

        Repeater {
            model: [
                {
                    phase: "work",
                    icon: "timer",
                    min: tab.pcfg.workMin
                },
                {
                    phase: "shortBreak",
                    icon: "coffee",
                    min: tab.pcfg.shortBreakMin
                },
                {
                    phase: "longBreak",
                    icon: "self_improvement",
                    min: tab.pcfg.longBreakMin
                }
            ]

            Rectangle {
                id: chip
                required property var modelData
                readonly property bool current: tab.pomo.phase === modelData.phase

                width: chipRow.implicitWidth + Theme.spacingM * 2
                height: 30
                radius: height / 2
                color: current ? Theme.withAlpha(tab.phaseColor, 0.18) : "transparent"
                border.color: current ? tab.phaseColor : Theme.outlineMedium
                border.width: 1

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: chip.modelData.icon
                        size: 16
                        color: chip.current ? tab.phaseColor : Theme.surfaceVariantText
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Clock.phaseLabel(chip.modelData.phase) + " · " + chip.modelData.min + "m"
                        font.pixelSize: Theme.fontSizeSmall
                        color: chip.current ? Theme.surfaceText : Theme.surfaceVariantText
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------- ring
    ProgressRing {
        id: ring
        anchors.horizontalCenter: parent.horizontalCenter
        width: tab.compact ? 150 : 200
        height: width
        lineWidth: tab.compact ? 7 : 10
        progress: Clock.pomoProgress(tab.pomo, ClockService.now)
        color: tab.phaseColor

        Column {
            anchors.centerIn: parent
            spacing: 2

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Clock.phaseLabel(tab.pomo.phase)
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Clock.fmtDuration(tab.remaining, {
                    countdown: true
                })
                font.pixelSize: tab.compact ? 34 : 44
                font.weight: Font.Medium
                font.features: {
                    "tnum": 1
                }
                color: Theme.surfaceText
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tab.pomo.status === "paused" ? I18n.tr("Paused") : tab.pomo.status === "idle" ? I18n.tr("Ready") : I18n.tr("Ends %1").arg(Qt.formatTime(new Date(tab.pomo.endsAt), ClockService.cfg.use24h ? "HH:mm" : "h:mm AP"))
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }

    // ------------------------------------------------------------- cycle dots
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6

        Repeater {
            model: tab.pcfg.cyclesBeforeLongBreak

            Rectangle {
                required property int index
                // Filled for completed sessions; the one in progress is hollow
                // in the phase colour.
                readonly property bool done: index < tab.pomo.cycle
                readonly property bool active: tab.pomo.phase === "work" && index === tab.pomo.cycle

                width: 10
                height: 10
                radius: 5
                color: done ? Theme.primary : "transparent"
                border.color: done || active ? Theme.primary : Theme.outlineMedium
                border.width: 1.5
            }
        }
    }

    // --------------------------------------------------------------- controls
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.spacingM

        DankActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "restart_alt"
            buttonSize: 40
            tooltipText: I18n.tr("Reset")
            onClicked: ClockService.pomoReset()
        }

        DankButton {
            anchors.verticalCenter: parent.verticalCenter
            width: 140
            iconName: tab.pomo.status === "running" ? "pause" : "play_arrow"
            text: tab.pomo.status === "running" ? I18n.tr("Pause") : tab.pomo.status === "paused" ? I18n.tr("Resume") : I18n.tr("Start")
            onClicked: ClockService.pomoToggle()
        }

        DankActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "skip_next"
            buttonSize: 40
            tooltipText: I18n.tr("Skip to %1").arg(Clock.phaseLabel(Clock.nextPhaseOf(tab.pomo, tab.pcfg).phase).toLowerCase())
            onClicked: ClockService.pomoSkip()
        }
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: tab.compact
        text: I18n.tr("%1 focus sessions today").arg(ClockService.todayPomodoros)
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    // ----------------------------------------------------------------- adjust
    component ValueRow: Item {
        id: vr
        property string label: ""
        property string icon: ""
        property int value: 0
        property int from: 1
        property int to: 120
        property string unit: "min"
        signal edited(int value)

        width: parent ? parent.width : 0
        height: 36

        function set(v) {
            const n = Math.max(from, Math.min(to, v));
            if (n !== value)
                edited(n);
        }

        DankIcon {
            id: vrIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            name: vr.icon
            size: 18
            color: Theme.surfaceVariantText
        }

        StyledText {
            anchors.left: vrIcon.right
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: vr.label
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            DankActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "remove"
                buttonSize: 28
                onClicked: vr.set(vr.value - 1)
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                horizontalAlignment: Text.AlignHCenter
                text: vr.value + (vr.unit ? " " + vr.unit : "")
                font.pixelSize: Theme.fontSizeMedium
                font.features: {
                    "tnum": 1
                }
                color: Theme.surfaceText

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: wheel => {
                        // Shift = coarse steps, for 25 -> 50 without 25 clicks.
                        const step = (wheel.modifiers & Qt.ShiftModifier) ? 5 : 1;
                        vr.set(vr.value + (wheel.angleDelta.y > 0 ? step : -step));
                        wheel.accepted = true;
                    }
                }
            }

            DankActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "add"
                buttonSize: 28
                onClicked: vr.set(vr.value + 1)
            }
        }
    }

    component ToggleRow: DankToggle {
        width: parent ? parent.width : 0
    }

    Card {
        width: tab.width
        visible: !tab.compact

        Item {
            width: parent.width
            height: 28

            StyledText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Adjust")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            DankActionButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: Object.keys(ClockService.pomoOverrides).length > 0
                iconName: "settings_backup_restore"
                buttonSize: 28
                tooltipText: I18n.tr("Back to the configured defaults")
                onClicked: ClockService.resetPomoConfig()
            }
        }

        ValueRow {
            label: I18n.tr("Focus")
            icon: "timer"
            value: tab.pcfg.workMin
            to: 240
            onEdited: v => ClockService.setPomoValue("workMin", v)
        }

        ValueRow {
            label: I18n.tr("Short break")
            icon: "coffee"
            value: tab.pcfg.shortBreakMin
            onEdited: v => ClockService.setPomoValue("shortBreakMin", v)
        }

        ValueRow {
            label: I18n.tr("Long break")
            icon: "self_improvement"
            value: tab.pcfg.longBreakMin
            to: 240
            onEdited: v => ClockService.setPomoValue("longBreakMin", v)
        }

        ValueRow {
            label: I18n.tr("Long break every")
            icon: "repeat"
            value: tab.pcfg.cyclesBeforeLongBreak
            to: 12
            unit: I18n.tr("× focus")
            onEdited: v => ClockService.setPomoValue("cyclesBeforeLongBreak", v)
        }

        ToggleRow {
            text: I18n.tr("Start breaks automatically")
            checked: tab.pcfg.autoStartBreaks
            onToggled: c => ClockService.setPomoValue("autoStartBreaks", c)
        }

        ToggleRow {
            text: I18n.tr("Start focus automatically")
            checked: tab.pcfg.autoStartWork
            onToggled: c => ClockService.setPomoValue("autoStartWork", c)
        }

        ToggleRow {
            text: I18n.tr("Do Not Disturb while focusing")
            checked: tab.pcfg.dndDuringWork
            onToggled: c => ClockService.setPomoValue("dndDuringWork", c)
        }
    }

    // ---------------------------------------------------------------- history
    Card {
        id: historyCard

        // Depends on `today` (changes once a day), never on `now`, so the bars
        // are not rebuilt on every tick.
        readonly property var days: {
            ClockService.history;
            ClockService.today;
            return ClockService.pomoHistory(7);
        }
        readonly property int peak: Math.max(1, ...days.map(d => d.count))

        width: tab.width
        visible: !tab.compact

        Item {
            width: parent.width
            height: 24

            StyledText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Focus sessions")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            StyledText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("%1 today").arg(ClockService.todayPomodoros)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        Row {
            width: parent.width
            height: 72
            spacing: Theme.spacingXS

            Repeater {
                model: historyCard.days

                Column {
                    id: bar
                    required property var modelData
                    required property int index

                    width: (parent.width - Theme.spacingXS * 6) / 7
                    height: parent.height
                    spacing: 2

                    Item {
                        width: parent.width
                        height: parent.height - dayLabel.height - countLabel.height - 4

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width, 18)
                            height: Math.max(3, parent.height * bar.modelData.count / historyCard.peak)
                            radius: 3
                            color: bar.index === 6 ? Theme.primary : Theme.withAlpha(Theme.primary, bar.modelData.count ? 0.5 : 0.15)
                        }
                    }

                    StyledText {
                        id: countLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: bar.modelData.count
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        id: dayLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: bar.modelData.label
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: bar.index === 6 ? Theme.surfaceText : Theme.surfaceVariantText
                    }
                }
            }
        }
    }
}
