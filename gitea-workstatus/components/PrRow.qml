import QtQuick
import QtQuick.Layouts
import Quickshell

import "../Model.js" as Model

Item {
    id: row

    property var data: ({})
    property bool selected: false
    property string giteaUrl: ""

    signal openPr()
    signal openRepo()

    implicitHeight: contentLayout.implicitHeight + 12
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
        onClicked: row.openPr()
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                width: 8; height: 8; radius: 4
                color: {
                    switch (data.status_label) {
                        case "ci_failed": return Quickshell.Colors.error;
                        case "changes_requested": return Quickshell.Colors.error;
                        case "review_requested": return Quickshell.Colors.accent;
                        case "ci_running": return Quickshell.Colors.warning;
                        case "ready": return Quickshell.Colors.success;
                        case "approved":
                        case "approved_ci_passed": return Quickshell.Colors.success;
                        case "ci_passed": return Quickshell.Colors.info;
                        case "draft": return Quickshell.Colors.textMuted;
                        case "conflicted": return Quickshell.Colors.warning;
                        default: return Quickshell.Colors.textMuted;
                    }
                }

                SequentialAnimation on opacity {
                    running: data.status_label === "ci_running"
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            Text {
                Layout.fillWidth: true
                text: data.title || ""
                font.pixelSize: 12
                font.weight: data.needs_attention ? Font.DemiBold : Font.Normal
                color: Quickshell.Colors.textPrimary
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Rectangle {
                visible: data.draft === true
                width: draftText.implicitWidth + 8
                height: draftText.implicitHeight + 4
                radius: 2
                color: Qt.rgba(Quickshell.Colors.textMuted.r, Quickshell.Colors.textMuted.g, Quickshell.Colors.textMuted.b, 0.15)
                Text {
                    id: draftText
                    anchors.centerIn: parent
                    text: "draft"
                    font.pixelSize: 9
                    color: Quickshell.Colors.textMuted
                }
            }

            Rectangle {
                visible: data.status_label === "conflicted"
                width: conflictText.implicitWidth + 8
                height: conflictText.implicitHeight + 4
                radius: 2
                color: Qt.rgba(Quickshell.Colors.warning.r, Quickshell.Colors.warning.g, Quickshell.Colors.warning.b, 0.15)
                Text {
                    id: conflictText
                    anchors.centerIn: parent
                    text: "conflicts"
                    font.pixelSize: 9
                    color: Quickshell.Colors.warning
                }
            }

            Text {
                text: "#" + (data.id || "")
                font.family: "monospace"
                font.pixelSize: 10
                color: Quickshell.Colors.textMuted
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
                text: "\u2192"
                font.pixelSize: 9
                color: Quickshell.Colors.textMuted
                opacity: 0.4
            }

            Text {
                text: data.branch || ""
                font.family: "monospace"
                font.pixelSize: 10
                color: Quickshell.Colors.textSecondary
                Layout.maximumWidth: 120
                elide: Text.ElideRight
            }

            Item { Layout.fillWidth: true }

            Text {
                text: data.author || ""
                font.pixelSize: 10
                color: Quickshell.Colors.textMuted
            }

            Text {
                text: Model.timeAgo(data.updated)
                font.pixelSize: 10
                color: Quickshell.Colors.textMuted
                opacity: 0.6
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: hasReviewInfo || hasCiInfo || !!data.blocker

            property bool hasReviewInfo: data.reviews && (data.reviews.approved > 0 || data.reviews.changes_requested > 0)
            property bool hasCiInfo: data.ci && data.ci.total > 0

            Row {
                spacing: 4
                visible: parent.hasReviewInfo

                Text {
                    text: {
                        var parts = [];
                        if (data.reviews.approved > 0) parts.push("\u2713 " + data.reviews.approved);
                        if (data.reviews.changes_requested > 0) parts.push("\u2718 " + data.reviews.changes_requested);
                        return parts.join("  ");
                    }
                    font.pixelSize: 10
                    color: data.reviews.changes_requested > 0 ? Quickshell.Colors.error : Quickshell.Colors.success
                }
            }

            Row {
                spacing: 3
                visible: parent.hasCiInfo

                Text {
                    text: {
                        if (!data.ci) return "";
                        return data.ci.passed + "/" + data.ci.total + " checks";
                    }
                    font.pixelSize: 10
                    color: {
                        if (!data.ci) return Quickshell.Colors.textMuted;
                        if (data.ci.failed > 0) return Quickshell.Colors.error;
                        if (data.ci.pending_count > 0) return Quickshell.Colors.warning;
                        return Quickshell.Colors.success;
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: !!data.blocker
                text: data.blocker || ""
                font.pixelSize: 10
                font.italic: true
                color: Quickshell.Colors.error
                opacity: 0.85
                Layout.maximumWidth: 200
                elide: Text.ElideRight
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 4
            visible: data.labels && data.labels.length > 0

            Repeater {
                model: data.labels || []
                Rectangle {
                    width: labelText.implicitWidth + 8
                    height: labelText.implicitHeight + 3
                    radius: 2
                    color: modelData.color ? ("#" + modelData.color) : Quickshell.Colors.surfaceSecondary
                    opacity: 0.7

                    Text {
                        id: labelText
                        anchors.centerIn: parent
                        text: modelData.name || ""
                        font.pixelSize: 9
                        color: Quickshell.Colors.textPrimary
                    }
                }
            }
        }
    }
}
