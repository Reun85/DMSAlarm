import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Bar popout: anything ringing on top, then the four tools as tabs. The tab is
// remembered in the service for the session and starts on the pomodoro.
PopoutComponent {
    id: popout

    readonly property var tabs: [
        {
            key: "pomodoro",
            text: I18n.tr("Pomodoro"),
            icon: "timer"
        },
        {
            key: "timer",
            text: I18n.tr("Timer"),
            icon: "hourglass_top"
        },
        {
            key: "stopwatch",
            text: I18n.tr("Stopwatch"),
            icon: "timer_play"
        },
        {
            key: "alarms",
            text: I18n.tr("Alarms"),
            icon: "alarm"
        }
    ]
    readonly property int tabIndex: Math.max(0, tabs.findIndex(t => t.key === ClockService.currentTab))

    // A fixed body height keeps the popout from jumping in size between tabs;
    // longer content scrolls.
    readonly property real bodyHeight: 520

    spacing: Theme.spacingS

    RingingBanner {
        width: popout.width
    }

    DankTabBar {
        id: tabBar
        width: popout.width
        tabHeight: 48
        model: popout.tabs
        currentIndex: popout.tabIndex
        onTabClicked: index => ClockService.currentTab = popout.tabs[index].key
        Component.onCompleted: Qt.callLater(updateIndicator)
    }

    DankFlickable {
        id: scroll

        width: popout.width
        height: popout.bodyHeight
        implicitHeight: popout.bodyHeight
        contentWidth: width
        contentHeight: stack.implicitHeight + Theme.spacingS
        clip: true

        StackLayout {
            id: stack
            // A Flickable's children live in its contentItem, whose width is
            // not bound to the Flickable; bind it or the body collapses.
            width: scroll.width
            currentIndex: popout.tabIndex
            implicitHeight: children[currentIndex] ? children[currentIndex].implicitHeight : 0

            onCurrentIndexChanged: scroll.contentY = 0

            PomodoroTab {
                Layout.fillWidth: true
            }

            TimerTab {
                Layout.fillWidth: true
            }

            StopwatchTab {
                Layout.fillWidth: true
            }

            AlarmsTab {
                Layout.fillWidth: true
            }
        }
    }
}
