import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: badge

    property string label: ""
    property int count: 0
    property color accent: Quickshell.Colors.textMuted
    property bool active: false

    signal clicked()

    implicitWidth: badgeRow.implicitWidth + 12
    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: 3
        color: {
            if (active) return Qt.rgba(accent.r, accent.g, accent.b, 0.15);
            if (mouseArea.containsMouse) return Qt.rgba(accent.r, accent.g, accent.b, 0.08);
            return "transparent";
        }
        border.color: active ? Qt.rgba(accent.r, accent.g, accent.b, 0.3) : "transparent"
        border.width: active ? 1 : 0

        Behavior on color { ColorAnimation { duration: 100 } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: badge.clicked()
    }

    RowLayout {
        id: badgeRow
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: badge.count.toString()
            font.pixelSize: 11
            font.weight: badge.active ? Font.DemiBold : Font.Normal
            color: badge.count > 0 ? badge.accent : Quickshell.Colors.textMuted
        }

        Text {
            text: badge.label
            font.pixelSize: 10
            color: badge.active ? Quickshell.Colors.textPrimary : Quickshell.Colors.textMuted
        }
    }
}
