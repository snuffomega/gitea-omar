import QtQuick
import QtQuick.Layouts
import qs.Commons

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
        spacing: Style.space(4)

        Rectangle {
            width: allText.implicitWidth + Style.space(10)
            height: Style.space(22)
            radius: Style.space(3)
            color: currentFilter === "" ?
                Qt.rgba(Color.accent.primary.r, Color.accent.primary.g, Color.accent.primary.b, 0.15) :
                (allMouse.containsMouse ?
                    Qt.rgba(Color.text.primary.r, Color.text.primary.g, Color.text.primary.b, 0.06) :
                    "transparent")
            border.color: currentFilter === "" ?
                Qt.rgba(Color.accent.primary.r, Color.accent.primary.g, Color.accent.primary.b, 0.3) :
                "transparent"
            border.width: currentFilter === "" ? 1 : 0

            Text {
                id: allText
                anchors.centerIn: parent
                text: "All"
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: currentFilter === "" ? Color.text.primary : Color.text.muted
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
            height: Style.space(22)
            contentWidth: repoRow.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: repoRow
                spacing: Style.space(4)

                Repeater {
                    model: filter.repos
                    Rectangle {
                        width: repoText.implicitWidth + Style.space(10)
                        height: Style.space(22)
                        radius: Style.space(3)
                        property bool isActive: currentFilter === modelData
                        color: isActive ?
                            Qt.rgba(Color.accent.primary.r, Color.accent.primary.g, Color.accent.primary.b, 0.15) :
                            (chipMouse.containsMouse ?
                                Qt.rgba(Color.text.primary.r, Color.text.primary.g, Color.text.primary.b, 0.06) :
                                "transparent")
                        border.color: isActive ?
                            Qt.rgba(Color.accent.primary.r, Color.accent.primary.g, Color.accent.primary.b, 0.3) :
                            "transparent"
                        border.width: isActive ? 1 : 0

                        Text {
                            id: repoText
                            anchors.centerIn: parent
                            text: {
                                var parts = modelData.split("/");
                                return parts.length > 1 ? parts[1] : modelData;
                            }
                            font.family: Style.font.monospace
                            font.pixelSize: Style.space(10)
                            color: isActive ? Color.text.primary : Color.text.secondary
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
