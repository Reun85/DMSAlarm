import QtQuick
import qs.Common
import qs.Widgets

// Shown at the top of the popout while anything is ringing: one row per source
// with Dismiss and a kind-appropriate secondary action.
Column {
    id: banner

    spacing: Theme.spacingS
    visible: ClockService.ringing.length > 0

    Repeater {
        model: ClockService.ringing

        Rectangle {
            id: row
            required property var modelData

            width: banner.width
            implicitHeight: content.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.primary, 0.16)
            border.color: Theme.primary
            border.width: 1

            SequentialAnimation on opacity {
                running: !ClockService.silenced
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.7; duration: 600; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            }

            Row {
                id: content
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: row.modelData.kind === "alarm" ? "alarm" : row.modelData.kind === "timer" ? "timer" : "nutrition"
                    size: Theme.iconSize + 4
                    color: Theme.primary
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: content.width - Theme.iconSize - 4 - actions.width - Theme.spacingM * 2
                    spacing: 2

                    StyledText {
                        width: parent.width
                        text: row.modelData.title
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: row.modelData.body || ""
                        visible: text.length > 0
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: actions
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS

                    DankButton {
                        text: row.modelData.kind === "alarm" ? I18n.tr("Snooze") : row.modelData.kind === "timer" ? I18n.tr("+1 min") : I18n.tr("Start")
                        buttonHeight: 32
                        horizontalPadding: Theme.spacingM
                        backgroundColor: Theme.surfaceContainerHigh
                        textColor: Theme.surfaceText
                        onClicked: ClockService.snooze(row.modelData.key)
                    }

                    DankButton {
                        text: I18n.tr("Dismiss")
                        buttonHeight: 32
                        horizontalPadding: Theme.spacingM
                        onClicked: ClockService.dismiss(row.modelData.key)
                    }
                }
            }
        }
    }
}
