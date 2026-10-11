import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "Config.js" as Config

// Settings page, shown inline in Settings -> Plugins.
//
// Every defaultValue is read from Config.DEFAULTS, so the page and the runtime
// cannot disagree about a default.
//
// These are defaults. Pomodoro lengths, timer presets and alarms edited in the
// popout are kept in plugin state and take precedence; the popout's "Adjust"
// card has a button to drop those edits again.
//
// Nix users: when home-manager manages plugin settings, plugin_settings.json is
// a read-only store symlink and nothing set here persists. Use
// programs.dankClock.settings (this flake's module) instead.
PluginSettings {
    id: root

    pluginId: "dankClock"

    readonly property var defaults: Config.DEFAULTS

    component Heading: StyledText {
        width: root.width
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    component Note: StyledText {
        width: root.width
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Note {
        text: qsTr("These are defaults. Changes made in the popout (pomodoro lengths, timer presets, alarms) are stored separately and win.")
    }

    // --------------------------------------------------------------- pomodoro
    Heading {
        text: qsTr("Pomodoro")
    }

    SliderSetting {
        settingKey: "workMin"
        label: qsTr("Focus length")
        defaultValue: root.defaults.workMin
        minimum: 1
        maximum: 120
        unit: "min"
        leftIcon: "timer"
    }

    SliderSetting {
        settingKey: "shortBreakMin"
        label: qsTr("Short break")
        defaultValue: root.defaults.shortBreakMin
        minimum: 1
        maximum: 60
        unit: "min"
        leftIcon: "coffee"
    }

    SliderSetting {
        settingKey: "longBreakMin"
        label: qsTr("Long break")
        defaultValue: root.defaults.longBreakMin
        minimum: 1
        maximum: 120
        unit: "min"
        leftIcon: "self_improvement"
    }

    SliderSetting {
        settingKey: "cyclesBeforeLongBreak"
        label: qsTr("Focus sessions before a long break")
        defaultValue: root.defaults.cyclesBeforeLongBreak
        minimum: 1
        maximum: 12
        leftIcon: "repeat"
    }

    ToggleSetting {
        settingKey: "autoStartBreaks"
        label: qsTr("Start breaks automatically")
        defaultValue: root.defaults.autoStartBreaks
    }

    ToggleSetting {
        settingKey: "autoStartWork"
        label: qsTr("Start focus automatically after a break")
        defaultValue: root.defaults.autoStartWork
    }

    ToggleSetting {
        settingKey: "dndDuringWork"
        label: qsTr("Do Not Disturb while focusing")
        description: qsTr("Only turns DND off again if this plugin turned it on.")
        defaultValue: root.defaults.dndDuringWork
    }

    // ------------------------------------------------------------------ timer
    Heading {
        text: qsTr("Timer")
    }

    StringSetting {
        settingKey: "timerPresets"
        label: qsTr("Presets (minutes)")
        description: qsTr("Comma-separated. Presets added or removed in the popout replace this list.")
        placeholder: root.defaults.timerPresets
        defaultValue: root.defaults.timerPresets
    }

    // ----------------------------------------------------------------- alarms
    Heading {
        text: qsTr("Alarms")
    }

    SliderSetting {
        settingKey: "snoozeMin"
        label: qsTr("Snooze length")
        defaultValue: root.defaults.snoozeMin
        minimum: 1
        maximum: 30
        unit: "min"
        leftIcon: "snooze"
    }

    SliderSetting {
        settingKey: "missedGraceMin"
        label: qsTr("Ring late alarms up to")
        description: qsTr("An alarm or timer that came due while the shell was down rings if it is at most this late; older ones only show a \"missed\" toast.")
        defaultValue: root.defaults.missedGraceMin
        minimum: 0
        maximum: 60
        unit: "min"
        leftIcon: "history"
    }

    // ------------------------------------------------------------------ sound
    Heading {
        text: qsTr("Sound")
    }

    StringSetting {
        settingKey: "soundFile"
        label: qsTr("Alarm sound")
        description: qsTr("Looped until dismissed. \"alarm\" is bundled; also a freedesktop sound name (bell), \"<theme>/<name>\" (ocean/bell) or an absolute path. Empty: silent.")
        placeholder: root.defaults.soundFile
        defaultValue: root.defaults.soundFile
    }

    StringSetting {
        settingKey: "chimeFile"
        label: qsTr("Pomodoro chime")
        description: qsTr("Played once when a focus session or break ends. chime is bundled; same naming as above. Empty: silent.")
        placeholder: root.defaults.chimeFile
        defaultValue: root.defaults.chimeFile
    }

    SliderSetting {
        settingKey: "soundVolume"
        label: qsTr("Volume")
        defaultValue: root.defaults.soundVolume
        minimum: 0
        maximum: 150
        unit: "%"
        leftIcon: "volume_up"
    }

    SliderSetting {
        settingKey: "ringTimeoutS"
        label: qsTr("Stop ringing after")
        description: qsTr("The sound stops on its own; the alarm stays in the bar until dismissed.")
        defaultValue: root.defaults.ringTimeoutS
        minimum: 5
        maximum: 600
        unit: "s"
        leftIcon: "timer_off"
    }

    // -------------------------------------------------------------------- bar
    Heading {
        text: qsTr("Bar widget")
    }

    SelectionSetting {
        settingKey: "barIdle"
        label: qsTr("When nothing is running, show")
        options: [
            {
                label: qsTr("Icon only"),
                value: "icon"
            },
            {
                label: qsTr("Pomodoro length"),
                value: "pomodoro"
            },
            {
                label: qsTr("Next alarm (within 24 h)"),
                value: "nextAlarm"
            }
        ]
        defaultValue: root.defaults.barIdle
    }

    StringSetting {
        settingKey: "barPriority"
        label: qsTr("What the pill shows first")
        description: qsTr("Order of ringing, pomodoro, timer, stopwatch. Missing entries are appended in that default order.")
        placeholder: root.defaults.barPriority
        defaultValue: root.defaults.barPriority
    }

    ToggleSetting {
        settingKey: "showProgressInBar"
        label: qsTr("Progress line under the pill")
        defaultValue: root.defaults.showProgressInBar
    }

    ToggleSetting {
        settingKey: "use24h"
        label: qsTr("24-hour time")
        defaultValue: root.defaults.use24h
    }

    // ---------------------------------------------------------- notifications
    Heading {
        text: qsTr("Notifications")
    }

    ToggleSetting {
        settingKey: "toasts"
        label: qsTr("Show a toast when something rings or finishes")
        defaultValue: root.defaults.toasts
    }
}
