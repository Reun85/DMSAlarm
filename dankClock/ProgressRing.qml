import QtQuick
import qs.Common

// Circular progress arc drawn on a Canvas. Content (time, labels) goes inside as
// children, centred by the caller.
Item {
    id: ring

    property real progress: 0          // 0 … 1
    property color color: Theme.primary
    property color trackColor: Theme.withAlpha(Theme.surfaceText, 0.1)
    property real lineWidth: 8

    implicitWidth: 200
    implicitHeight: 200

    onProgressChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const r = Math.min(width, height) / 2 - ring.lineWidth / 2;
            const cx = width / 2, cy = height / 2;
            const start = -Math.PI / 2;
            ctx.lineWidth = ring.lineWidth;
            ctx.lineCap = "round";

            ctx.strokeStyle = ring.trackColor;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
            ctx.stroke();

            const p = Math.max(0, Math.min(1, ring.progress));
            if (p > 0) {
                ctx.strokeStyle = ring.color;
                ctx.beginPath();
                ctx.arc(cx, cy, r, start, start + p * 2 * Math.PI);
                ctx.stroke();
            }
        }
    }
}
