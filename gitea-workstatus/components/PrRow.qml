import QtQuick
import QtQuick.Layouts
import qs.Commons

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
        onClicked: row.openPr()
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(4)

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Rectangle {
                width: Style.space(8); height: Style.space(8); radius: Style.space(4)
                color: {
                    switch (data.status_label) {
                        case "ci_failed": return Color.status.error;
                        case "changes_requested": return Color.status.error;
                        case "review_requested": return Color.accent.primary;
                        case "ci_running": return Color.status.warning;
                        case "approved_ci_passed":
                        case "approved": return Color.status.success;
                        case "ci_passed": return Color.accent.secondary;
                        case "draft": return Color.text.muted;
                        case "conflicted": return Color.status.warning;
                        default: return Color.text.muted;
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
                font.family: Style.font.family
                font.pixelSize: Style.space(12)
                font.weight: data.needs_attention ? Font.DemiBold : Font.Normal
                color: Color.text.primary
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Rectangle {
                visible: data.draft === true
                width: draftText.implicitWidth + Style.space(8)
                height: draftText.implicitHeight + Style.space(4)
                radius: Style.space(2)
                color: Qt.rgba(Color.text.muted.r, Color.text.muted.g, Color.text.muted.b, 0.15)
                Text {
                    id: draftText
                    anchors.centerIn: parent
                    text: "draft"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(9)
                    color: Color.text.muted
                }
            }

            Rectangle {
                visible: data.status_label === "conflicted"
                width: conflictText.implicitWidth + Style.space(8)
                height: conflictText.implicitHeight + Style.space(4)
                radius: Style.space(2)
                color: Qt.rgba(Color.status.warning.r, Color.status.warning.g, Color.status.warning.b, 0.15)
                Text {
                    id: conflictText
                    anchors.centerIn: parent
                    text: "conflicts"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(9)
                    color: Color.status.warning
                }
            }

            Text {
                text: "#" + (data.id || "")
                font.family: Style.font.monospace
                font.pixelSize: Style.space(10)
                color: Color.text.muted
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
                text: "\u2192"
                font.pixelSize: Style.space(9)
                color: Color.text.muted
                opacity: 0.4
            }

            Text {
                text: data.branch || ""
                font.family: Style.font.monospace
                font.pixelSize: Style.space(10)
                color: Color.text.secondary
                Layout.maximumWidth: Style.space(120)
                elide: Text.ElideRight
            }

            Item { Layout.fillWidth: true }

            Text {
                text: data.author || ""
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Color.text.muted
            }

            Text {
                text: Model.timeAgo(data.updated)
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                color: Color.text.muted
                opacity: 0.6
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            visible: hasReviewInfo || hasCiInfo || !!data.blocker

            property bool hasReviewInfo: data.reviews && (data.reviews.approved > 0 || data.reviews.changes_requested > 0)
            property bool hasCiInfo: data.ci && data.ci.total > 0

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
                    color: data.reviews.changes_requested > 0 ? Color.status.error : Color.status.success
                }
            }

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
                        if (!data.ci) return Color.text.muted;
                        if (data.ci.failed > 0) return Color.status.error;
                        if (data.ci.pending_count > 0) return Color.status.warning;
                        return Color.status.success;
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: !!data.blocker
                text: data.blocker || ""
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
                font.italic: true
                color: Color.status.error
                opacity: 0.85
                Layout.maximumWidth: Style.space(200)
                elide: Text.ElideRight
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Style.space(4)
            visible: data.labels && data.labels.length > 0

            Repeater {
                model: data.labels || []
                Rectangle {
                    width: labelText.implicitWidth + Style.space(8)
                    height: labelText.implicitHeight + Style.space(3)
                    radius: Style.space(2)
                    color: modelData.color ? ("#" + modelData.color) : Color.popups.background
                    opacity: 0.7

                    Text {
                        id: labelText
                        anchors.centerIn: parent
                        text: modelData.name || ""
                        font.family: Style.font.family
                        font.pixelSize: Style.space(9)
                        color: Color.text.primary
                    }
                }
            }
        }
    }
}
