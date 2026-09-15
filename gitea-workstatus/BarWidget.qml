import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications as Notif

import "Model.js" as Model

// BarWidget is the standard Omarchy bar-widget root type.
// Settings are read via setting("key") which returns the manifest default
// or the user-configured value.
BarWidget {
    id: root

    property string moduleName: "gitea.workstatus"
    property int refreshIntervalSec: setting("refreshIntervalSec")
    property string giteaUrl: setting("giteaUrl")
    property int maxStaleHours: setting("maxStaleHours")
    property bool notifyOnFailure: setting("notifyOnFailure")
    property bool notifyOnReviewRequest: setting("notifyOnReviewRequest")
    property string mutedRepos: setting("mutedRepos")

    property string stateDir: StandardPaths.writableLocation(StandardPaths.StateLocation) + "/omarchy/gitea-workstatus"
    property string stateFile: stateDir + "/overview.json"

    property var barSummary: ({ total: 0, attention: 0, running: 0, failed: 0, review: 0, ready: 0, healthy: true })
    property bool panelOpen: false
    property bool stale: false
    property bool hasError: false
    property string errorMsg: ""
    property int dataRevision: 0

    implicitWidth: barRow.implicitWidth + Quickshell.Sizes.spacing * 4
    implicitHeight: Quickshell.Sizes.barHeight

    function open() { panelOpen = true; panelLoader.active = true; }
    function close() { panelOpen = false; panelLoader.active = false; }
    function toggle() { panelOpen ? close() : open(); }
    function refresh() { collector.running = true; }
    function next() {}

    Component.onCompleted: {
        Model.setMutedRepos(mutedRepos);
        fileReader.reload();
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

        // Identity-based notifications
        var notes = Model.getNewNotifications(notifyOnFailure, notifyOnReviewRequest);
        for (var i = 0; i < notes.length; i++) {
            notifier.send("Gitea", notes[i].message);
        }
    }

    // Desktop notification sender
    Notif.NotificationServer {
        id: notifier
        function send(title, body) {
            var n = createNotification();
            n.summary = title;
            n.body = body;
            n.send();
        }
    }

    // File watcher for overview.json
    FileView {
        id: fileReader
        path: root.stateFile
        watchChanges: true
        onLoaded: root.processData(text())
        onFileChanged: root.processData(text())
    }

    // Collector process — launch via bash to avoid executable-bit issues
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

    // === Bar Widget Content ===
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
            spacing: 6

            Text {
                text: "\u2387"
                font.pixelSize: 14
                color: {
                    if (root.hasError) return Quickshell.Colors.textMuted;
                    if (root.barSummary.attention > 0 || root.barSummary.failed > 0) return Quickshell.Colors.error;
                    if (root.barSummary.running > 0) return Quickshell.Colors.warning;
                    if (root.barSummary.review > 0) return Quickshell.Colors.accent;
                    return Quickshell.Colors.textSecondary;
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
                spacing: 4
                visible: !root.hasError && root.barSummary.total > 0

                Row {
                    spacing: 2
                    visible: root.barSummary.failed > 0
                    Text {
                        text: "\u2718"
                        font.pixelSize: 10
                        color: Quickshell.Colors.error
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.barSummary.failed
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Quickshell.Colors.error
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    spacing: 2
                    visible: root.barSummary.review > 0
                    Text {
                        text: "\u25CF"
                        font.pixelSize: 8
                        color: Quickshell.Colors.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.barSummary.review
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Quickshell.Colors.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    spacing: 2
                    visible: root.barSummary.running > 0
                    Text {
                        text: "\u25E6"
                        font.pixelSize: 10
                        color: Quickshell.Colors.warning
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
                        font.pixelSize: 11
                        color: Quickshell.Colors.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    spacing: 2
                    visible: root.barSummary.ready > 0 && root.barSummary.attention === 0
                    Text {
                        text: "\u2714"
                        font.pixelSize: 10
                        color: Quickshell.Colors.success
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.barSummary.ready
                        font.pixelSize: 11
                        color: Quickshell.Colors.success
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Text {
                visible: root.hasError
                text: "!"
                font.pixelSize: 11
                font.weight: Font.Bold
                color: Quickshell.Colors.textMuted
            }
        }
    }

    // === Panel Loader ===
    Loader {
        id: panelLoader
        active: root.panelOpen
        source: "Panel.qml"
        onLoaded: {
            item.barWidget = root;
        }
    }
}
