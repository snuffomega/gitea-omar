import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui

import "Model.js" as Model

Ui.BarWidget {
    id: root

    property int refreshIntervalSec: setting("refreshIntervalSec", 180)
    property string giteaUrl: setting("giteaUrl", "")
    property int maxStaleHours: setting("maxStaleHours", 6)
    property bool notifyOnFailure: setting("notifyOnFailure", true)
    property bool notifyOnReviewRequest: setting("notifyOnReviewRequest", true)
    property string mutedRepos: setting("mutedRepos", "")

    property string stateDir: {
        var xdg = Qt.getenv("XDG_STATE_HOME")
        return (xdg || Qt.getenv("HOME") + "/.local/state") + "/omarchy/gitea-workstatus"
    }
    property string stateFile: stateDir + "/overview.json"

    property var barSummary: ({ total: 0, attention: 0, running: 0, failed: 0, review: 0, ready: 0, healthy: true })
    property bool panelOpen: false
    property bool stale: false
    property bool hasError: false
    property string errorMsg: ""
    property int dataRevision: 0

    implicitWidth: barRow.implicitWidth + Style.space(16)
    implicitHeight: Style.bar.sizeHorizontal

    function open() { panelOpen = true; }
    function close() { panelOpen = false; }
    function toggle() { panelOpen ? close() : open(); }
    function refresh() { collector.running = true; }
    function next() {}

    Component.onCompleted: {
        Model.setMutedRepos(mutedRepos);
        collector.running = true;
    }

    onMutedReposChanged: {
        Model.setMutedRepos(mutedRepos);
        barSummary = Model.getBarSummary();
        dataRevision = Model.revision();
    }

    function processData(content) {
        if (!content || content.trim() === "") {
            hasError = true;
            errorMsg = "No status data yet";
            return;
        }

        var parsed;
        try { parsed = JSON.parse(content); } catch(e) {
            hasError = true;
            errorMsg = "Corrupt status data";
            return;
        }

        if (parsed.error) {
            hasError = true;
            errorMsg = parsed.error;
            return;
        }

        Model.parseOverview(content);
        barSummary = Model.getBarSummary();
        dataRevision = Model.revision();
        hasError = false;
        errorMsg = "";

        var meta = Model.getMeta();
        stale = meta && meta.stale === true;

        if (stale) return;

        var notes = Model.getNewNotifications(notifyOnFailure, notifyOnReviewRequest);
        for (var i = 0; i < notes.length; i++) {
            sendNotification(notes[i].message);
        }
    }

    function sendNotification(body) {
        notifProcess.notifBody = body;
        notifProcess.running = true;
    }

    Process {
        id: notifProcess
        property string notifBody: ""
        command: ["notify-send", "--app-name=Gitea", "Gitea", notifBody]
    }

    FileView {
        id: fileReader
        path: root.stateFile
        watchChanges: true
        onLoadedChanged: if (loaded) root.processData(text())
        onFileChanged: root.processData(text())
    }

    Process {
        id: collector
        command: ["bash", Qt.resolvedUrl("bin/gitea-collect").toString().replace("file://", "")]
        environment: ({
            GITEA_WS_MAX_STALE_HOURS: root.maxStaleHours.toString()
        })
    }

    Timer {
        interval: root.refreshIntervalSec * 1000
        running: true
        repeat: true
        onTriggered: collector.running = true
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) root.toggle();
            else if (mouse.button === Qt.RightButton) root.refresh();
        }
        cursorShape: Qt.PointingHandCursor

        RowLayout {
            id: barRow
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
                text: "\u2387"
                font.family: Style.font.family
                font.pixelSize: Style.space(14)
                color: {
                    if (root.hasError) return Color.text.muted;
                    if (root.barSummary.attention > 0 || root.barSummary.failed > 0) return Color.status.error;
                    if (root.barSummary.running > 0) return Color.status.warning;
                    if (root.barSummary.review > 0) return Color.accent.primary;
                    return Color.text.secondary;
                }
                opacity: root.stale ? 0.5 : 1.0

                SequentialAnimation on opacity {
                    running: root.barSummary.running > 0 && !root.stale
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                }
            }

            Row {
                spacing: Style.space(4)
                visible: !root.hasError && root.barSummary.total > 0

                Row {
                    spacing: Style.space(2)
                    visible: root.barSummary.failed > 0
                    Text {
                        text: "\u2718"
                        font.pixelSize: Style.space(10)
                        color: Color.status.error
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.barSummary.failed
                        font.family: Style.font.family
                        font.pixelSize: Style.space(11)
                        font.weight: Font.DemiBold
                        color: Color.status.error
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    spacing: Style.space(2)
                    visible: root.barSummary.review > 0
                    Text {
                        text: "\u25CF"
                        font.pixelSize: Style.space(8)
                        color: Color.accent.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.barSummary.review
                        font.family: Style.font.family
                        font.pixelSize: Style.space(11)
                        font.weight: Font.DemiBold
                        color: Color.accent.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    spacing: Style.space(2)
                    visible: root.barSummary.running > 0
                    Text {
                        text: "\u25E6"
                        font.pixelSize: Style.space(10)
                        color: Color.status.warning
                        anchors.verticalCenter: parent.verticalCenter

                        SequentialAnimation on opacity {
                            running: true
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }
                    Text {
                        text: root.barSummary.running
                        font.family: Style.font.family
                        font.pixelSize: Style.space(11)
                        color: Color.status.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    spacing: Style.space(2)
                    visible: root.barSummary.ready > 0 && root.barSummary.attention === 0
                    Text {
                        text: "\u2714"
                        font.pixelSize: Style.space(10)
                        color: Color.status.success
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.barSummary.ready
                        font.family: Style.font.family
                        font.pixelSize: Style.space(11)
                        color: Color.status.success
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Text {
                visible: root.hasError
                text: "!"
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                font.weight: Font.Bold
                color: Color.text.muted
            }
        }
    }

    Loader {
        id: panelLoader
        active: root.panelOpen
        sourceComponent: Component {
            Panel {
                anchorItem: root
                bar: root.bar
                owner: root
                open: root.panelOpen
                barWidget: root
            }
        }
    }
}
