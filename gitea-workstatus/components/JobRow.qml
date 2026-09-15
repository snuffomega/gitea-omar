import QtQuick
import QtQuick.Layouts
import Omarchy.Themes
import Omarchy.Widgets

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
        radius: Style.cornerRadius * 0.5
        color: {
            if (selected) return Qt.rgba(Palette.accent.primary.r, Palette.accent.primary.g, Palette.accent.primary.b, 0.1);
            if (mouseArea.containsMouse) return Qt.rgba(Palette.text.primary.r, Palette.text.primary.g, Palette.text.primary.b, 0.04);
            return "transparent";
        }
        border.color: selected ? Qt.rgba(Palette.accent.primary.r, Palette.accent.primary.g, Palette.accent.primary.b, 0.3) : "transparent"
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

            // Status icon
            Rectangle {
                width: Style.space(8)
                height: Style.space(8)
                radius: width / 2
                color: {
                    switch (data.status) {
                        case "running":
                        case "waiting": return Palette.status.warning;
                        case "success": return Palette.status.success;
                        case "failure": return Palette.status.error;
                        case "cancelled": return Palette.text.muted;
                        default: return Palette.text.muted;
                    }
                }

                SequentialAnimation on opacity {
                    running: data.status === "running" || data.status === "waiting"
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            // Workflow name
            Text {
                Layout.fillWidth: true
                text: data.workflow || ""
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                color: Palette.text.primary
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Status text
            Text {
                text: data.status || ""
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: {
                    switch (data.status) {
                        case "running": return Palette.status.warning;
                        case "success": return Palette.status.success;
                        case "failure": return Palette.status.error;
                        default: return Palette.text.muted;
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            // Repo
            Text {
                text: data.repo || ""
                font.family: Style.font.monospace
                font.pixelSize: Style.space(10)
                color: Palette.accent.secondary
                opacity: repoMouse.containsMouse ? 1.0 : 0.7

                MouseArea {
                    id: repoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.openRepo()
                }
            }

            // Branch
            Text {
                text: data.branch || ""
                font.family: Style.font.monospace
                font.pixelSize: Style.space(10)
                color: Palette.text.secondary
                Layout.maximumWidth: Style.space(120)
                elide: Text.ElideRight
            }

            // Event type
            Text {
                visible: !!data.event
                text: data.event || ""
                font.family: Style.font.family
                font.pixelSize: Style.space(9)
                color: Palette.text.muted
                opacity: 0.5
            }

            Item { Layout.fillWidth: true }

            // Timestamp
            Text {
                text: Model.timeAgo(data.updated || data.started)
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Palette.text.muted
                opacity: 0.6
            }
        }
    }
}
