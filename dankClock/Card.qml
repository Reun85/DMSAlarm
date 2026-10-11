import QtQuick
import qs.Common

// Transparency-aware card used for every grouped block in the popout.
// nestedSurface follows the user's popup transparency and blur, where an opaque
// surfaceContainerHigh would not (see DMS's own Control Center details).
Rectangle {
    id: card

    default property alias content: inner.data
    property real padding: Theme.spacingM
    property alias spacing: inner.spacing

    implicitHeight: inner.implicitHeight + padding * 2
    radius: Theme.cornerRadius
    color: Theme.nestedSurface
    border.color: Theme.outlineMedium
    border.width: Theme.layerOutlineWidth

    Column {
        id: inner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: card.padding
        spacing: Theme.spacingS
    }
}
