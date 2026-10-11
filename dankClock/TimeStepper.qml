import QtQuick
import qs.Common
import qs.Widgets

// One numeric field with up/down buttons, wheel and drag support, wrapping or
// clamping at its bounds. Used for h/m/s on the timer, hour/minute on alarms,
// and the pomodoro durations.
Column {
    id: stepper

    property int value: 0
    property int from: 0
    property int to: 59
    property int step: 1
    property bool wrap: false
    property bool pad: true
    property string caption: ""
    property int fontSize: Theme.fontSizeXLarge * 1.6

    signal edited(int value)

    spacing: 2
    width: Math.max(numberText.implicitWidth, 48)

    function set(v) {
        let n = v;
        if (wrap) {
            const span = to - from + 1;
            n = ((n - from) % span + span) % span + from;
        } else {
            n = Math.max(from, Math.min(to, n));
        }
        if (n !== value)
            edited(n);
    }

    DankActionButton {
        anchors.horizontalCenter: parent.horizontalCenter
        iconName: "keyboard_arrow_up"
        buttonSize: 28
        onClicked: stepper.set(stepper.value + stepper.step)
    }

    StyledText {
        id: numberText
        anchors.horizontalCenter: parent.horizontalCenter
        text: stepper.pad && stepper.value < 10 ? "0" + stepper.value : String(stepper.value)
        font.pixelSize: stepper.fontSize
        font.weight: Font.Medium
        font.features: {
            "tnum": 1
        }
        color: Theme.surfaceText

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                stepper.set(stepper.value + (wheel.angleDelta.y > 0 ? stepper.step : -stepper.step));
                wheel.accepted = true;
            }
        }
    }

    DankActionButton {
        anchors.horizontalCenter: parent.horizontalCenter
        iconName: "keyboard_arrow_down"
        buttonSize: 28
        onClicked: stepper.set(stepper.value - stepper.step)
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: stepper.caption.length > 0
        text: stepper.caption
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
