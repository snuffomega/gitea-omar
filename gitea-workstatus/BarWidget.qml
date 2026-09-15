import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Omarchy.Themes
import Omarchy.Widgets

import "Model.js" as Model

BarWidgetItem {
    id: root

    property string moduleName: "gitea.workstatus"
    property int refreshIntervalSec: config.refreshIntervalSec ?? 180
    property string giteaUrl: config.giteaUrl ?? ""
    property int maxStaleHours: config.maxStaleHours ?? 6
    property bool notifyOnFailure: config.notifyOnFailure ?? true
    property bool notifyOnReviewRequest: config.notifyOnReviewRequest ?? true
    property string mutedRepos: config.mutedRepos ?? ""

    property string stateFile: StandardPaths.state + "/omarchy/gitea-workstatus/overview.json"
    property var barSummary: ({ total: 0, attention: 0, running: 0, failed: 0, review: 0, healthy: true })
    property var prevSummary: ({})
    property bool panelOpen: false
    property bool stale: false
    property bool hasError: false
    property string errorMsg: ""

    implicitWidth: barRow.implicitWidth + Style.space(16)
    implicitHeight: Style.bar.sizeHorizontal

    function open() { panelOpen = true; panelLoader.active = true; }
    function close() { panelOpen = false; }
    function toggle() { panelOpen ? close() : open(); }
    function refresh() { collector.running = true; }
    function next() {}

    Component.onCompleted: {
        Model.setMutedRepos(mutedRepos);
        loadData();
        collector.running = true;
    }

    onMutedReposChanged: Model.setMutedRepos(mutedRepos)

    function loadData() {
        fileReader.path = stateFile;
        fileReader.reload();
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

        prevSummary = barSummary;
        Model.parseOverview(content);
        barSummary = Model.getBarSummary();
        hasError = false;
        errorMsg = "";

        var meta = Model.getMeta();
        stale = meta && meta.stale === true;

        if (notifyOnFailure || notifyOnReviewRequest) {
            var notes = Model.getNewNotifications(prevSummary);
            for (var i = 0; i < notes.length; i++) {
                if (notes[i].type === "failure" && notifyOnFailure) {
                    Notifications.send("Gitea: " + notes[i].message);
                } else if (notes[i].type === "review" && notifyOnReviewRequest) {
                    Notifications.send("Gitea: " + notes[i].message);
                }
            }
        }
    }

    FileView {
        id: fileReader
        path: root.stateFile
        onTextChanged: root.processData(text)
    }

    Process {
        id: collector
        command: [Qt.resolvedUrl("bin/gitea-collect").toString().replace("file://", "")]
        environment: ({
            GITEA_WS_MAX_STALE_HOURS: root.maxStaleHours.toString()
        })
        onExited: {
            root.loadData();
        }
    }

    Timer {
        interval: root.refreshIntervalSec * 1000
        running: true
        repeat: true
        onTriggered: collector.running = true
    }

    // Watch for file changes
    FileSystemWatcher {
        files: [root.stateFile]
        onFileChanged: root.loadData()
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
            spacing: Style.space(6)

            // Gitea icon (git-pull-request style)
            Text {
                text: "\u2387"
                font.family: Style.font.family
                font.pixelSize: Style.space(14)
                color: {
                    if (hasError) return Palette.text.muted;
                    if (barSummary.attention > 0 || barSummary.failed > 0) return Palette.status.error;
                    if (barSummary.running > 0) return Palette.status.warning;
                    if (barSummary.review > 0) return Palette.accent.primary;
                    return Palette.text.secondary;
                }
                opacity: stale ? 0.5 : 1.0

                SequentialAnimation on opacity {
                    running: barSummary.running > 0
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                }
            }

            // Compact counts — only show non-zero
            Row {
                spacing: Style.space(4)
                visible: !hasError && barSummary.total > 0

                // Failed CI
                Row {
                    spacing: Style.space(2)
                    visible: barSummary.failed > 0
                    Text {
                        text: "\u2718"
                        font.pixelSize: Style.space(10)
                        color: Palette.status.error
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: barSummary.failed
                        font.family: Style.font.family
                        font.pixelSize: Style.space(11)
                        font.weight: Font.DemiBold
                        color: Palette.status.error
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Review requested
                Row {
                    spacing: Style.space(2)
                    visible: barSummary.review > 0
                    Text {
                        text: "\u25CF"
                        font.pixelSize: Style.space(8)
                        color: Palette.accent.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: barSummary.review
                        font.family: Style.font.family
                        font.pixelSize: Style.space(11)
                        font.weight: Font.DemiBold
                        color: Palette.accent.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Running jobs
                Row {
                    spacing: Style.space(2)
                    visible: barSummary.running > 0
                    Text {
                        text: "\u25E6"
                        font.pixelSize: Style.space(10)
                        color: Palette.status.warning
                        anchors.verticalCenter: parent.verticalCenter

                        SequentialAnimation on opacity {
                            running: true
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }
                    Text {
                        text: barSummary.running
                        font.family: Style.font.family
                        font.pixelSize: Style.space(11)
                        color: Palette.status.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Ready to merge (quiet indicator)
                Row {
                    spacing: Style.space(2)
                    visible: barSummary.ready > 0 && barSummary.attention === 0
                    Text {
                        text: "\u2714"
                        font.pixelSize: Style.space(10)
                        color: Palette.status.success
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: barSummary.ready
                        font.family: Style.font.family
                        font.pixelSize: Style.space(11)
                        color: Palette.status.success
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Error/empty state
            Text {
                visible: hasError
                text: "!"
                font.family: Style.font.family
                font.pixelSize: Style.space(11)
                font.weight: Font.Bold
                color: Palette.text.muted
            }
        }
    }

    // === Panel Loader ===
    Loader {
        id: panelLoader
        active: root.panelOpen
        sourceComponent: Panel {}
        onLoaded: {
            item.barWidget = root;
            item.visible = true;
        }
    }
}
