import QtQuick
import QtQuick.Layouts
import Omarchy.Themes
import Omarchy.Widgets

import "../Model.js" as Model

Item {
    id: row

    property var data: ({})
    property bool selected: false
    property string giteaUrl: ""

    signal openPr()
    signal openRepo()

    implicitHeight: contentLayout.implicitHeight + Style.space(12)
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
        onClicked: row.openPr()
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(4)

        // Top line: status + title + repo
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            // Status indicator
            Rectangle {
                width: Style.space(8)
                height: Style.space(8)
                radius: width / 2
                color: {
                    switch (data.status_label) {
                        case "ci_failed": return Palette.status.error;
                        case "changes_requested": return Palette.status.error;
                        case "review_requested": return Palette.accent.primary;
                        case "ci_running": return Palette.status.warning;
                        case "ready": return Palette.status.success;
                        case "approved": return Palette.status.success;
                        case "ci_passed": return Palette.status.info;
                        default: return Palette.text.muted;
                    }
                }

                SequentialAnimation on opacity {
                    running: data.status_label === "ci_running"
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            // PR title
            Text {
                Layout.fillWidth: true
                text: data.title || ""
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                font.weight: data.needs_attention ? Font.DemiBold : Font.Normal
                color: Palette.text.primary
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Draft badge
            Rectangle {
                visible: data.draft === true
                width: draftText.implicitWidth + Style.space(8)
                height: draftText.implicitHeight + Style.space(4)
                radius: Style.cornerRadius * 0.3
                color: Qt.rgba(Palette.text.muted.r, Palette.text.muted.g, Palette.text.muted.b, 0.15)
                Text {
                    id: draftText
                    anchors.centerIn: parent
                    text: "draft"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(9)
                    color: Palette.text.muted
                }
            }

            // PR number
            Text {
                text: "#" + (data.id || "")
                font.family: Style.font.monospace
                font.pixelSize: Style.space(10)
                color: Palette.text.muted
            }
        }

        // Second line: repo, branch, author, time
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            // Repo name (clickable)
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

            Text {
                text: "\u2192"
                font.pixelSize: Style.space(9)
                color: Palette.text.muted
                opacity: 0.4
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

            Item { Layout.fillWidth: true }

            // Author
            Text {
                text: data.author || ""
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Palette.text.muted
            }

            // Timestamp
            Text {
                text: Model.timeAgo(data.updated)
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Palette.text.muted
                opacity: 0.6
            }
        }

        // Third line: review/CI detail + blocker (only when meaningful)
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            visible: hasReviewInfo || hasCiInfo || data.blocker

            property bool hasReviewInfo: data.reviews && (data.reviews.approved > 0 || data.reviews.changes_requested > 0)
            property bool hasCiInfo: data.ci && data.ci.total > 0

            // Review summary
            Row {
                spacing: Style.space(4)
                visible: parent.hasReviewInfo

                Text {
                    text: {
                        var parts = [];
                        if (data.reviews.approved > 0) parts.push("\u2713 " + data.reviews.approved);
                        if (data.reviews.changes_requested > 0) parts.push("\u2718 " + data.reviews.changes_requested);
                        return parts.join("  ");
                    }
                    font.family: Style.font.family
                    font.pixelSize: Style.space(10)
                    color: data.reviews.changes_requested > 0 ? Palette.status.error : Palette.status.success
                }
            }

            // CI summary
            Row {
                spacing: Style.space(3)
                visible: parent.hasCiInfo

                Text {
                    text: {
                        if (!data.ci) return "";
                        return data.ci.passed + "/" + data.ci.total + " checks";
                    }
                    font.family: Style.font.family
                    font.pixelSize: Style.space(10)
                    color: {
                        if (!data.ci) return Palette.text.muted;
                        if (data.ci.failed > 0) return Palette.status.error;
                        if (data.ci.pending_count > 0) return Palette.status.warning;
                        return Palette.status.success;
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Blocker reason
            Text {
                visible: !!data.blocker
                text: data.blocker || ""
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                font.italic: true
                color: Palette.status.error
                opacity: 0.85
                Layout.maximumWidth: Style.space(200)
                elide: Text.ElideRight
            }
        }

        // Labels row
        Flow {
            Layout.fillWidth: true
            spacing: Style.space(4)
            visible: data.labels && data.labels.length > 0

            Repeater {
                model: data.labels || []
                Rectangle {
                    width: labelText.implicitWidth + Style.space(8)
                    height: labelText.implicitHeight + Style.space(3)
                    radius: Style.cornerRadius * 0.25
                    color: modelData.color ? ("#" + modelData.color) : Palette.surface.secondary
                    opacity: 0.7

                    Text {
                        id: labelText
                        anchors.centerIn: parent
                        text: modelData.name || ""
                        font.family: Style.font.family
                        font.pixelSize: Style.space(9)
                        color: Palette.text.primary
                    }
                }
            }
        }
    }
}
