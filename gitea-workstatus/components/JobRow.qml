import QtQuick
import QtQuick.Layouts
import Quickshell

import "../Model.js" as Model

Item {
    id: row

    property var data: ({})
    property bool selected: false

    signal openJob()
    signal openRepo()

    implicitHeight: contentLayout.implicitHeight + 10
    width: parent ? parent.width : 0

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: {
            if (selected) return Qt.rgba(Quickshell.Colors.accent.r, Quickshell.Colors.accent.g, Quickshell.Colors.accent.b, 0.1);
            if (mouseArea.containsMouse) return Qt.rgba(Quickshell.Colors.textPrimary.r, Quickshell.Colors.textPrimary.g, Quickshell.Colors.textPrimary.b, 0.04);
            return "transparent";
        }
        border.color: selected ? Qt.rgba(Quickshell.Colors.accent.r, Quickshell.Colors.accent.g, Quickshell.Colors.accent.b, 0.3) : "transparent"
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
        anchors.margins: 8
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                width: 8; height: 8; radius: 4
                color: {
                    switch (data.status) {
                        case "running":
                        case "waiting":
                        case "queued": return Quickshell.Colors.warning;
                        case "success": return Quickshell.Colors.success;
                        case "failure": return Quickshell.Colors.error;
                        case "cancelled":
                        case "skipped": return Quickshell.Colors.textMuted;
                        default: return Quickshell.Colors.textMuted;
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
                font.pixelSize: 12
                color: Quickshell.Colors.textPrimary
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                text: data.status || ""
                font.pixelSize: 10
                color: {
                    switch (data.status) {
                        case "running":
                        case "waiting": return Quickshell.Colors.warning;
                        case "success": return Quickshell.Colors.success;
                        case "failure": return Quickshell.Colors.error;
                        default: return Quickshell.Colors.textMuted;
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: data.repo || ""
                font.family: "monospace"
                font.pixelSize: 10
                color: Quickshell.Colors.accentSecondary
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
                font.family: "monospace"
                font.pixelSize: 10
                color: Quickshell.Colors.textSecondary
                Layout.maximumWidth: 120
                elide: Text.ElideRight
            }

            Text {
                visible: !!data.event
                text: data.event || ""
                font.pixelSize: 9
                color: Quickshell.Colors.textMuted
                opacity: 0.5
            }

            Item { Layout.fillWidth: true }

            Text {
                text: Model.timeAgo(data.updated || data.started)
                font.pixelSize: 10
                color: Quickshell.Colors.textMuted
                opacity: 0.6
            }
        }
    }
}
