import QtQuick
import qs.Common
import qs.Widgets
import "Clock.js" as Clock

// Stopwatch with laps. Centiseconds need a faster repaint than the service's
// tick, so this view runs its own short timer, and only while it is on screen.
Column {
    id: tab

    readonly property var sw: ClockService.stopwatch
    readonly property bool running: Clock.swRunning(sw)
    readonly property var extremes: Clock.lapExtremes(sw.laps)
    property real t: Date.now()

    spacing: Theme.spacingM

    Timer {
        interval: 33
        repeat: true
        running: tab.running && tab.visible
        onTriggered: tab.t = Date.now()
    }

    Connections {
        target: ClockService
        function onStopwatchChanged() {
            tab.t = Date.now();
        }
    }

    Card {
        width: tab.width
        padding: Theme.spacingL

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Clock.fmtDuration(Clock.swElapsed(tab.sw, tab.t), {
                centis: true
            })
            font.pixelSize: 52
            font.weight: Font.Medium
            font.features: {
                "tnum": 1
            }
            color: Theme.surfaceText
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: tab.sw.laps.length > 0
            text: I18n.tr("Lap %1  %2").arg(tab.sw.laps.length + 1).arg(Clock.fmtDuration(Clock.swCurrentSplit(tab.sw, tab.t), {
                centis: true
            }))
            font.pixelSize: Theme.fontSizeMedium
            font.features: {
                "tnum": 1
            }
            color: Theme.surfaceVariantText
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.spacingM

        // Lap while running, Reset once paused, like every phone stopwatch.
        DankButton {
            width: 130
            iconName: tab.running ? "flag" : "restart_alt"
            text: tab.running ? I18n.tr("Lap") : I18n.tr("Reset")
            backgroundColor: Theme.surfaceContainerHigh
            textColor: Theme.surfaceText
            enabled: tab.running || ClockService.swActive
            opacity: enabled ? 1 : 0.5
            onClicked: tab.running ? ClockService.swLap() : ClockService.swReset()
        }

        DankButton {
            width: 130
            iconName: tab.running ? "pause" : "play_arrow"
            text: tab.running ? I18n.tr("Pause") : ClockService.swActive ? I18n.tr("Resume") : I18n.tr("Start")
            onClicked: ClockService.swToggle()
        }
    }

    Card {
        width: tab.width
        visible: tab.sw.laps.length > 0
        padding: Theme.spacingS
        spacing: 0

        Repeater {
            model: tab.sw.laps

            Item {
                id: lapRow
                required property var modelData
                readonly property bool best: modelData.n === tab.extremes.best
                readonly property bool worst: modelData.n === tab.extremes.worst

                width: parent.width
                height: 32

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Lap %1").arg(lapRow.modelData.n)
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }

                // The fastest/slowest marker is an icon, not a coloured number:
                // severity colours are unreliable as text on some themes.
                DankIcon {
                    anchors.right: splitText.left
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    visible: lapRow.best || lapRow.worst
                    name: lapRow.best ? "arrow_downward" : "arrow_upward"
                    size: 14
                    color: lapRow.best ? Theme.primary : Theme.error
                }

                StyledText {
                    id: splitText
                    anchors.right: totalText.left
                    anchors.rightMargin: Theme.spacingL
                    anchors.verticalCenter: parent.verticalCenter
                    text: Clock.fmtDuration(lapRow.modelData.splitMs, {
                        centis: true
                    })
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: lapRow.best || lapRow.worst ? Font.Bold : Font.Normal
                    font.features: {
                        "tnum": 1
                    }
                    color: Theme.surfaceText
                }

                StyledText {
                    id: totalText
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: Clock.fmtDuration(lapRow.modelData.totalMs, {
                        centis: true
                    })
                    font.pixelSize: Theme.fontSizeSmall
                    font.features: {
                        "tnum": 1
                    }
                    color: Theme.surfaceVariantText
                }
            }
        }
    }
}
