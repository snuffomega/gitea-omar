import QtQuick
import QtQuick.Layouts
import qs.Commons

import "../Model.js" as Model

Item {
    id: row

    property var data: ({})
    property bool selected: false

    signal openJob()
    signal openRepo()

    implicitHeight: contentLayout.implicitHeight + Style.space(10)
    width: parent ? parent.width : 0

    Rectangle {
        anchors.fill: parent
        radius: Style.space(4)
        color: {
            if (selected) return Qt.rgba(Color.accent.primary.r, Color.accent.primary.g, Color.accent.primary.b, 0.1);
            if (mouseArea.containsMouse) return Qt.rgba(Color.text.primary.r, Color.text.primary.g, Color.text.primary.b, 0.04);
            return "transparent";
        }
        border.color: selected ? Qt.rgba(Color.accent.primary.r, Color.accent.primary.g, Color.accent.primary.b, 0.3) : "transparent"
        border.width: selected ? 1 : 0

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.openJob()
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(3)

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Rectangle {
                width: Style.space(8); height: Style.space(8); radius: Style.space(4)
                color: {
                    switch (data.status) {
                        case "running":
                        case "waiting":
                        case "queued": return Color.status.warning;
                        case "success": return Color.status.success;
                        case "failure": return Color.status.error;
                        case "cancelled":
                        case "skipped": return Color.text.muted;
                        default: return Color.text.muted;
                    }
                }

                SequentialAnimation on opacity {
                    running: data.status === "running" || data.status === "waiting" || data.status === "queued"
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            Text {
                Layout.fillWidth: true
                text: data.workflow || ""
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                color: Color.text.primary
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                text: data.status || ""
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: {
                    switch (data.status) {
                        case "running":
                        case "waiting": return Color.status.warning;
                        case "success": return Color.status.success;
                        case "failure": return Color.status.error;
                        default: return Color.text.muted;
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
                text: data.repo || ""
                font.family: Style.font.monospace
                font.pixelSize: Style.space(10)
                color: Color.accent.secondary
                opacity: repoMouse.containsMouse ? 1.0 : 0.7

                MouseArea {
                    id: repoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.openRepo()
                }
            }

            Text {
                text: data.branch || ""
                font.family: Style.font.monospace
                font.pixelSize: Style.space(10)
                color: Color.text.secondary
                Layout.maximumWidth: Style.space(120)
                elide: Text.ElideRight
            }

            Text {
                visible: !!data.event
                text: data.event || ""
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
                color: Color.text.muted
                opacity: 0.5
            }

            Item { Layout.fillWidth: true }

            Text {
                text: Model.timeAgo(data.updated || data.started)
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Color.text.muted
                opacity: 0.6
            }
        }
    }
}
