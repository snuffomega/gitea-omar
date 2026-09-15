import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: filter

    property var repos: []
    property string currentFilter: ""

    signal filterChanged(string repo)

    implicitHeight: filterRow.implicitHeight
    width: parent ? parent.width : 0

    RowLayout {
        id: filterRow
        anchors.fill: parent
        spacing: 4

        Rectangle {
            width: allText.implicitWidth + 10
            height: 22
            radius: 3
            color: currentFilter === "" ?
                Qt.rgba(Quickshell.Colors.accent.r, Quickshell.Colors.accent.g, Quickshell.Colors.accent.b, 0.15) :
                (allMouse.containsMouse ?
                    Qt.rgba(Quickshell.Colors.textPrimary.r, Quickshell.Colors.textPrimary.g, Quickshell.Colors.textPrimary.b, 0.06) :
                    "transparent")
            border.color: currentFilter === "" ?
                Qt.rgba(Quickshell.Colors.accent.r, Quickshell.Colors.accent.g, Quickshell.Colors.accent.b, 0.3) :
                "transparent"
            border.width: currentFilter === "" ? 1 : 0

            Text {
                id: allText
                anchors.centerIn: parent
                text: "All"
                font.pixelSize: 10
                color: currentFilter === "" ? Quickshell.Colors.textPrimary : Quickshell.Colors.textMuted
            }

            MouseArea {
                id: allMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: filter.filterChanged("")
            }
        }

        Flickable {
            Layout.fillWidth: true
            height: 22
            contentWidth: repoRow.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: repoRow
                spacing: 4

                Repeater {
                    model: filter.repos
                    Rectangle {
                        width: repoText.implicitWidth + 10
                        height: 22
                        radius: 3
                        property bool isActive: currentFilter === modelData
                        color: isActive ?
                            Qt.rgba(Quickshell.Colors.accent.r, Quickshell.Colors.accent.g, Quickshell.Colors.accent.b, 0.15) :
                            (chipMouse.containsMouse ?
                                Qt.rgba(Quickshell.Colors.textPrimary.r, Quickshell.Colors.textPrimary.g, Quickshell.Colors.textPrimary.b, 0.06) :
                                "transparent")
                        border.color: isActive ?
                            Qt.rgba(Quickshell.Colors.accent.r, Quickshell.Colors.accent.g, Quickshell.Colors.accent.b, 0.3) :
                            "transparent"
                        border.width: isActive ? 1 : 0

                        Text {
                            id: repoText
                            anchors.centerIn: parent
                            text: {
                                var parts = modelData.split("/");
                                return parts.length > 1 ? parts[1] : modelData;
                            }
                            font.family: "monospace"
                            font.pixelSize: 10
                            color: isActive ? Quickshell.Colors.textPrimary : Quickshell.Colors.textSecondary
                        }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: filter.filterChanged(isActive ? "" : modelData)
                        }
                    }
                }
            }
        }
    }
}
