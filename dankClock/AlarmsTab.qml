import QtQuick
import qs.Common
import qs.Widgets
import "Clock.js" as Clock

// Alarm list with an inline editor. Clicking a row edits it; the toggle on the
// right switches it on or off without opening anything.
Column {
    id: tab

    // "" = not editing, "new" = adding, otherwise the id being edited.
    property string editing: ""

    spacing: Theme.spacingM

    Item {
        width: tab.width
        height: 40

        Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: I18n.tr("Alarms")
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            StyledText {
                readonly property var next: ClockService.nextAlarm
                text: next ? I18n.tr("Next: %1 · in %2").arg(Clock.fmtTimeOfDay(new Date(next.at).getHours(), new Date(next.at).getMinutes(), ClockService.cfg.use24h)).arg(Clock.fmtHuman(next.at - ClockService.now)) : I18n.tr("None scheduled")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        DankButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: tab.editing !== "new"
            iconName: "add_alarm"
            text: I18n.tr("Add")
            buttonHeight: 36
            onClicked: tab.editing = "new"
        }
    }

    Loader {
        width: tab.width
        active: tab.editing === "new"
        visible: active
        sourceComponent: AlarmEditor {
            alarm: null
            onDone: tab.editing = ""
        }
    }

    StyledText {
        width: tab.width
        visible: ClockService.alarms.length === 0 && tab.editing === ""
        horizontalAlignment: Text.AlignHCenter
        topPadding: Theme.spacingXL
        bottomPadding: Theme.spacingXL
        text: I18n.tr("No alarms yet.\nAlso from a terminal: dms ipc call dankClock alarm 7:30")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    Repeater {
        model: ClockService.alarms

        Column {
            id: entry
            required property var modelData
            readonly property bool isEditing: tab.editing === modelData.id

            width: tab.width

            // Only the row being edited instantiates an editor.
            Loader {
                width: parent.width
                active: entry.isEditing
                visible: active
                sourceComponent: AlarmEditor {
                    alarm: entry.modelData
                    onDone: tab.editing = ""
                }
            }

            Card {
                width: parent.width
                visible: !entry.isEditing
                padding: Theme.spacingM
                opacity: entry.modelData.enabled || entry.modelData.snoozeUntil ? 1 : 0.6

                Item {
                    width: parent.width
                    height: 52

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tab.editing = entry.modelData.id
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: toggle.left
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            text: Clock.fmtTimeOfDay(entry.modelData.hour, entry.modelData.minute, ClockService.cfg.use24h)
                            font.pixelSize: 30
                            font.weight: Font.Medium
                            font.features: {
                                "tnum": 1
                            }
                            color: Theme.surfaceText
                        }

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            readonly property real at: Clock.alarmNextFire(entry.modelData, ClockService.now)
                            text: {
                                const parts = [];
                                if (entry.modelData.label)
                                    parts.push(entry.modelData.label);
                                parts.push(Clock.daysLabel(entry.modelData.days));
                                if (entry.modelData.snoozeUntil && entry.modelData.snoozeUntil > ClockService.now)
                                    parts.push(I18n.tr("snoozed, %1").arg(Clock.fmtHuman(entry.modelData.snoozeUntil - ClockService.now)));
                                else if (at)
                                    parts.push(I18n.tr("in %1").arg(Clock.fmtHuman(at - ClockService.now)));
                                return parts.join(" · ");
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    DankToggle {
                        id: toggle
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: entry.modelData.enabled
                        onToggled: ClockService.alarmToggle(entry.modelData.id)
                    }
                }
            }
        }
    }
}
