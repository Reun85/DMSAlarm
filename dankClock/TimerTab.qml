import QtQuick
import qs.Common
import qs.Widgets
import "Clock.js" as Clock

// Countdown timers: compose a duration (steppers or a preset), then any number
// of named timers run side by side.
Column {
    id: tab

    property int hours: 0
    property int minutes: 5
    property int seconds: 0
    readonly property int totalMs: ((hours * 60 + minutes) * 60 + seconds) * 1000

    spacing: Theme.spacingM

    function startCurrent() {
        if (totalMs <= 0)
            return;
        ClockService.timerAdd(totalMs, labelField.text.trim());
        labelField.text = "";
    }

    function presetLabel(min) {
        if (min >= 60 && min % 60 === 0)
            return (min / 60) + " h";
        if (min < 1)
            return Math.round(min * 60) + " s";
        return min + " min";
    }

    // ------------------------------------------------------------- composer
    Card {
        width: tab.width
        spacing: Theme.spacingM

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingS

            TimeStepper {
                value: tab.hours
                to: 23
                caption: I18n.tr("hours")
                onEdited: v => tab.hours = v
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -8
                text: ":"
                font.pixelSize: Theme.fontSizeXLarge * 1.6
                color: Theme.surfaceVariantText
            }

            TimeStepper {
                value: tab.minutes
                wrap: true
                caption: I18n.tr("min")
                onEdited: v => tab.minutes = v
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -8
                text: ":"
                font.pixelSize: Theme.fontSizeXLarge * 1.6
                color: Theme.surfaceVariantText
            }

            TimeStepper {
                value: tab.seconds
                wrap: true
                step: 5
                caption: I18n.tr("sec")
                onEdited: v => tab.seconds = v
            }
        }

        DankTextField {
            id: labelField
            width: parent.width
            placeholderText: I18n.tr("Label (optional)")
            leftIconName: "label"
            onAccepted: tab.startCurrent()
        }

        // Presets: click starts one at once. Right-click removes it; the last
        // chip saves the composed duration as a new preset.
        Flow {
            width: parent.width
            spacing: Theme.spacingXS

            Repeater {
                model: ClockService.timerPresets

                Rectangle {
                    id: preset
                    required property var modelData

                    width: presetText.implicitWidth + Theme.spacingM * 2
                    height: 30
                    radius: 15
                    color: presetArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.14) : "transparent"
                    border.color: Theme.outlineMedium
                    border.width: 1

                    StyledText {
                        id: presetText
                        anchors.centerIn: parent
                        text: tab.presetLabel(preset.modelData)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }

                    MouseArea {
                        id: presetArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                ClockService.removePreset(preset.modelData);
                            else
                                ClockService.timerAdd(preset.modelData * Clock.MINUTE, labelField.text.trim());
                        }
                    }
                }
            }

            DankActionButton {
                iconName: "bookmark_add"
                buttonSize: 30
                tooltipText: I18n.tr("Save %1 as a preset (right-click a preset to remove it)").arg(Clock.fmtDuration(tab.totalMs))
                onClicked: ClockService.addPreset(tab.totalMs / Clock.MINUTE)
            }
        }

        DankButton {
            width: parent.width
            iconName: "play_arrow"
            text: tab.totalMs > 0 ? I18n.tr("Start %1").arg(Clock.fmtDuration(tab.totalMs)) : I18n.tr("Set a duration")
            enabled: tab.totalMs > 0
            opacity: enabled ? 1 : 0.5
            onClicked: tab.startCurrent()
        }
    }

    // ------------------------------------------------------------- running
    StyledText {
        visible: ClockService.timers.length > 0
        text: I18n.tr("Running")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    Repeater {
        model: ClockService.timers

        Card {
            id: row
            required property var modelData
            readonly property var live: ClockService.timers.find(t => t.id === modelData.id) || modelData
            readonly property real remaining: Clock.timerRemaining(live, ClockService.now)

            width: tab.width
            padding: Theme.spacingS

            Item {
                width: parent.width
                height: 52

                ProgressRing {
                    id: mini
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    lineWidth: 4
                    progress: Clock.timerProgress(row.live, ClockService.now)
                    color: row.live.status === "done" ? Theme.error : Theme.primary

                    DankIcon {
                        anchors.centerIn: parent
                        name: row.live.status === "done" ? "alarm" : row.live.status === "paused" ? "pause" : "timer"
                        size: 18
                        color: Theme.surfaceVariantText
                    }
                }

                Column {
                    anchors.left: mini.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: buttons.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    StyledText {
                        text: Clock.fmtDuration(row.remaining, {
                            countdown: true
                        })
                        font.pixelSize: Theme.fontSizeXLarge
                        font.weight: Font.Medium
                        font.features: {
                            "tnum": 1
                        }
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: (row.live.label || I18n.tr("Timer")) + " · " + Clock.fmtDuration(row.live.durationMs)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                Row {
                    id: buttons
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    DankActionButton {
                        visible: row.live.status !== "done"
                        iconName: row.live.status === "running" ? "pause" : "play_arrow"
                        tooltipText: row.live.status === "running" ? I18n.tr("Pause") : I18n.tr("Resume")
                        onClicked: ClockService.timerToggle(row.live.id)
                    }

                    DankActionButton {
                        iconName: "more_time"
                        tooltipText: I18n.tr("+1 minute")
                        onClicked: ClockService.timerAddTime(row.live.id, Clock.MINUTE)
                    }

                    DankActionButton {
                        iconName: "close"
                        tooltipText: I18n.tr("Cancel")
                        onClicked: ClockService.timerCancel(row.live.id)
                    }
                }
            }
        }
    }
}
