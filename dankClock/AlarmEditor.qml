import QtQuick
import qs.Common
import qs.Widgets
import "Clock.js" as Clock

// Inline editor for one alarm. `alarm` null = a new one. Edits are held locally
// and only applied on Save, so Cancel really cancels.
Card {
    id: editor

    property var alarm: null
    property int hour: 7
    property int minute: 0
    property int days: 0
    property string label: ""

    signal done

    spacing: Theme.spacingM

    function load() {
        if (alarm) {
            hour = alarm.hour;
            minute = alarm.minute;
            days = alarm.days;
            label = alarm.label;
        } else {
            // A new alarm starts at the next full hour: a sane, quick default.
            const d = new Date(Date.now() + Clock.HOUR);
            hour = d.getHours();
            minute = 0;
            days = 0;
            label = "";
        }
        labelField.text = label;
    }

    function save() {
        const lbl = labelField.text.trim();
        if (alarm)
            ClockService.alarmUpdate(alarm.id, {
                hour: hour,
                minute: minute,
                days: days,
                label: lbl,
                enabled: true,
                snoozeUntil: null
            });
        else
            ClockService.alarmAdd(hour, minute, lbl, days);
        done();
    }

    onAlarmChanged: load()
    Component.onCompleted: load()

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.spacingS

        TimeStepper {
            value: editor.hour
            to: 23
            wrap: true
            caption: I18n.tr("hour")
            onEdited: v => editor.hour = v
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -8
            text: ":"
            font.pixelSize: Theme.fontSizeXLarge * 1.6
            color: Theme.surfaceVariantText
        }

        TimeStepper {
            value: editor.minute
            wrap: true
            step: 1
            caption: I18n.tr("minute")
            onEdited: v => editor.minute = v
        }
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property real at: Clock.alarmNextScheduled({
            hour: editor.hour,
            minute: editor.minute,
            days: editor.days,
            enabled: true
        }, ClockService.now)
        text: I18n.tr("Rings in %1").arg(Clock.fmtHuman(at - ClockService.now))
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    DankTextField {
        id: labelField
        width: parent.width
        placeholderText: I18n.tr("Label (optional)")
        leftIconName: "label"
        onAccepted: editor.save()
    }

    // Day toggles, Monday first.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4

        Repeater {
            model: [1, 2, 3, 4, 5, 6, 0]

            Rectangle {
                id: dayChip
                required property int modelData
                readonly property bool on: Clock.dayOn(editor.days, modelData)

                width: 38
                height: 32
                radius: 16
                color: on ? Theme.primary : "transparent"
                border.color: on ? Theme.primary : Theme.outlineMedium
                border.width: 1

                StyledText {
                    anchors.centerIn: parent
                    text: Clock.DAY_SHORT[dayChip.modelData].slice(0, 2)
                    font.pixelSize: Theme.fontSizeSmall
                    // primaryText is the token paired with a primary fill.
                    color: dayChip.on ? Theme.primaryText : Theme.surfaceText
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.days = Clock.toggleDay(editor.days, dayChip.modelData)
                }
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.spacingXS

        Repeater {
            model: [
                {
                    text: I18n.tr("Once"),
                    mask: 0
                },
                {
                    text: I18n.tr("Weekdays"),
                    mask: Clock.WEEKDAYS
                },
                {
                    text: I18n.tr("Weekends"),
                    mask: Clock.WEEKENDS
                },
                {
                    text: I18n.tr("Every day"),
                    mask: Clock.EVERY_DAY
                }
            ]

            Rectangle {
                id: quick
                required property var modelData
                readonly property bool on: editor.days === modelData.mask

                width: quickText.implicitWidth + Theme.spacingM * 2
                height: 28
                radius: 14
                color: on ? Theme.withAlpha(Theme.primary, 0.16) : "transparent"
                border.color: on ? Theme.primary : Theme.outlineMedium
                border.width: 1

                StyledText {
                    id: quickText
                    anchors.centerIn: parent
                    text: quick.modelData.text
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.days = quick.modelData.mask
                }
            }
        }
    }

    Item {
        width: parent.width
        height: 40

        DankButton {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: editor.alarm !== null
            iconName: "delete"
            text: I18n.tr("Delete")
            backgroundColor: Theme.surfaceContainerHigh
            textColor: Theme.surfaceText
            onClicked: {
                ClockService.alarmRemove(editor.alarm.id);
                editor.done();
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankButton {
                text: I18n.tr("Cancel")
                backgroundColor: Theme.surfaceContainerHigh
                textColor: Theme.surfaceText
                onClicked: editor.done()
            }

            DankButton {
                iconName: "check"
                text: I18n.tr("Save")
                onClicked: editor.save()
            }
        }
    }
}
